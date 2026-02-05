// functions/src/clinic/updateAppointment.ts
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { writeAuditEvent } from "./audit/audit";

type Input = {
  clinicId: string;
  appointmentId: string;

  // Preferred (unambiguous): epoch millis
  startMs?: number;
  endMs?: number;

  // Legacy fallback (avoid using if possible)
  start?: string; // ISO date-time
  end?: string; // ISO date-time

  // NEW: allow override into closures (requires settings.write)
  allowClosedOverride?: boolean;

  kind?: string; // admin|new|followup
  serviceId?: string | null; // allow null/empty to clear
};

const ALLOW_KIND_CONVERSION = false;

function getBoolPerm(perms: unknown, key: string): boolean {
  return typeof perms === "object" && perms !== null && (perms as any)[key] === true;
}

function requirePerm(perms: unknown, keys: string[], message: string) {
  const ok = keys.some((k) => getBoolPerm(perms, k));
  if (!ok) throw new HttpsError("permission-denied", message);
}

function normalizeKind(k?: string): "admin" | "new" | "followup" | null {
  if (k == null) return null;
  const v = k.toLowerCase().trim();
  const allowed = new Set(["admin", "new", "followup"]);
  if (!allowed.has(v)) {
    throw new HttpsError("invalid-argument", "Invalid kind. Use admin|new|followup.");
  }
  return v as any;
}

function parseMillisToTimestamp(ms?: number) {
  if (ms == null) return null;
  if (typeof ms !== "number" || !Number.isFinite(ms)) return null;
  if (ms <= 0) return null;
  return admin.firestore.Timestamp.fromMillis(ms);
}

function parseIsoToTimestamp(v?: string) {
  if (!v) return null;
  const d = new Date(v);
  if (Number.isNaN(d.getTime())) return null;
  return admin.firestore.Timestamp.fromDate(d);
}

/**
 * Returns IDs of closures overlapped by [startAt, endAt).
 * Overlap rule: start < closure.toAt && end > closure.fromAt
 *
 * Query optimization: only closures with fromAt < endAt can overlap.
 */
async function findOverlappingClosures(params: {
  db: admin.firestore.Firestore;
  clinicId: string;
  startAt: admin.firestore.Timestamp;
  endAt: admin.firestore.Timestamp;
}): Promise<string[]> {
  const { db, clinicId, startAt, endAt } = params;

  const snap = await db
    .collection(`clinics/${clinicId}/closures`)
    .where("active", "==", true)
    .where("fromAt", "<", endAt)
    .get();

  const ids: string[] = [];

  for (const doc of snap.docs) {
    const data = doc.data() as any;
    const fromAt = data?.fromAt as admin.firestore.Timestamp | undefined;
    const toAt = data?.toAt as admin.firestore.Timestamp | undefined;

    if (!fromAt || !toAt) continue;

    const overlaps =
      startAt.toMillis() < toAt.toMillis() && endAt.toMillis() > fromAt.toMillis();

    if (overlaps) ids.push(doc.id);
  }

  return ids;
}

// ✅ Canonical-first membership loader (with legacy fallback)
async function getMembershipData(
  db: FirebaseFirestore.Firestore,
  clinicId: string,
  uid: string
): Promise<FirebaseFirestore.DocumentData | null> {
  const canonical = db.doc(`clinics/${clinicId}/memberships/${uid}`);
  const legacy = db.doc(`clinics/${clinicId}/members/${uid}`);

  const c = await canonical.get();
  if (c.exists) return c.data() ?? {};

  const l = await legacy.get();
  if (l.exists) return l.data() ?? {};

  return null;
}

function isActiveMember(data: FirebaseFirestore.DocumentData): boolean {
  // New model: status can exist
  const status = (data.status ?? "").toString().toLowerCase().trim();
  if (status === "invited" || status === "suspended") return false;

  // Treat missing "active" as active (backwards compatible)
  if (!("active" in data)) return true;
  return (data as any).active === true;
}

export async function updateAppointment(req: CallableRequest<Input>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = (req.data?.clinicId ?? "").toString().trim();
  const appointmentId = (req.data?.appointmentId ?? "").toString().trim();
  if (!clinicId || !appointmentId) {
    throw new HttpsError("invalid-argument", "clinicId and appointmentId are required.");
  }

  const db = admin.firestore();
  const uid = req.auth.uid;

  // ─────────────────────────────
  // Membership + perms (canonical-first)
  // ─────────────────────────────
  const memberData = await getMembershipData(db, clinicId, uid);
  if (!memberData || !isActiveMember(memberData)) {
    throw new HttpsError("permission-denied", "Not a clinic member.");
  }

  const perms = (memberData as any).permissions ?? {};

  // Two paths:
  // - normal reschedule => schedule.write OR schedule.manage
  // - override into closure => settings.write (explicitly required)
  const allowClosedOverride = req.data?.allowClosedOverride === true;

  if (allowClosedOverride) {
    requirePerm(
      perms,
      ["settings.write"],
      "No permission to override clinic closures (settings.write required)."
    );
  } else {
    requirePerm(perms, ["schedule.write", "schedule.manage"], "No scheduling permission.");
  }

  // Load appointment
  const apptRef = db
    .collection("clinics")
    .doc(clinicId)
    .collection("appointments")
    .doc(appointmentId);

  const apptSnap = await apptRef.get();
  if (!apptSnap.exists) throw new HttpsError("not-found", "Appointment not found.");
  const appt = apptSnap.data() ?? {};

  // Build patch
  const patch: Record<string, any> = {};
  const now = admin.firestore.FieldValue.serverTimestamp();

  // Track whether time is changing (so we only check closures when needed)
  let newStartAt: admin.firestore.Timestamp | null = null;
  let newEndAt: admin.firestore.Timestamp | null = null;

  // ─────────────────────────────
  // Time update (start/end)
  // Prefer millis. Require both or neither.
  // ─────────────────────────────
  const startMsProvided = req.data?.startMs != null;
  const endMsProvided = req.data?.endMs != null;

  const startIsoProvided = req.data?.start != null;
  const endIsoProvided = req.data?.end != null;

  const anyTimeProvided = startMsProvided || endMsProvided || startIsoProvided || endIsoProvided;

  if (anyTimeProvided) {
    const useMillis = startMsProvided || endMsProvided;

    if (useMillis) {
      if (startMsProvided !== endMsProvided) {
        throw new HttpsError("invalid-argument", "Provide both startMs and endMs.");
      }

      const startTs = parseMillisToTimestamp(req.data?.startMs);
      const endTs = parseMillisToTimestamp(req.data?.endMs);

      if (!startTs) throw new HttpsError("invalid-argument", "Invalid startMs.");
      if (!endTs) throw new HttpsError("invalid-argument", "Invalid endMs.");
      if (startTs.toMillis() >= endTs.toMillis()) {
        throw new HttpsError("invalid-argument", "start must be before end.");
      }

      newStartAt = startTs;
      newEndAt = endTs;

      // Canonical
      patch.startAt = startTs;
      patch.endAt = endTs;

      // Legacy mirrors (keep while migrating)
      patch.start = startTs;
      patch.end = endTs;
    } else {
      // Legacy ISO fallback
      if (startIsoProvided !== endIsoProvided) {
        throw new HttpsError("invalid-argument", "Provide both start and end.");
      }

      const startTs = parseIsoToTimestamp(req.data?.start);
      const endTs = parseIsoToTimestamp(req.data?.end);

      if (!startTs) throw new HttpsError("invalid-argument", "Invalid start ISO string.");
      if (!endTs) throw new HttpsError("invalid-argument", "Invalid end ISO string.");
      if (startTs.toMillis() >= endTs.toMillis()) {
        throw new HttpsError("invalid-argument", "start must be before end.");
      }

      newStartAt = startTs;
      newEndAt = endTs;

      patch.startAt = startTs;
      patch.endAt = endTs;
      patch.start = startTs;
      patch.end = endTs;
    }
  }

  // ─────────────────────────────
  // kind update
  // ─────────────────────────────
  const kind = normalizeKind(req.data?.kind);
  if (kind != null) {
    const currentKind = (appt["kind"] ?? "").toString().toLowerCase().trim();

    if (!ALLOW_KIND_CONVERSION) {
      const changingAdminness =
        (currentKind === "admin" && kind !== "admin") ||
        (currentKind !== "admin" && kind === "admin");
      if (changingAdminness) {
        throw new HttpsError(
          "failed-precondition",
          "Converting between admin and patient bookings is disabled."
        );
      }
    }

    patch.kind = kind;
  }

  // ─────────────────────────────
  // serviceId update + denormalized serviceName
  // ─────────────────────────────
  if ("serviceId" in (req.data ?? {})) {
    const raw = req.data?.serviceId;
    const sid = (raw ?? "").toString().trim();

    patch.serviceId = sid;

    if (sid) {
      const serviceRef = db
        .collection("clinics")
        .doc(clinicId)
        .collection("services")
        .doc(sid);

      const serviceSnap = await serviceRef.get();
      if (!serviceSnap.exists) {
        throw new HttpsError("failed-precondition", "Selected service does not exist.");
      }
      const s = serviceSnap.data() ?? {};
      patch.serviceName = (s["name"] ?? "").toString();
    } else {
      patch.serviceName = "";
    }
  }

  // ─────────────────────────────
  // If kind changed away from admin, ensure required IDs exist
  // ─────────────────────────────
  if (patch.kind && patch.kind !== "admin") {
    const patientId = (appt["patientId"] ?? "").toString().trim();
    const serviceId = ((patch.serviceId ?? appt["serviceId"]) ?? "").toString().trim();
    const practitionerId = (appt["practitionerId"] ?? "").toString().trim();

    if (!patientId) {
      throw new HttpsError(
        "failed-precondition",
        "Cannot set kind to new/followup without patientId."
      );
    }
    if (!serviceId) {
      throw new HttpsError(
        "failed-precondition",
        "Cannot set kind to new/followup without serviceId."
      );
    }
    if (!practitionerId) {
      throw new HttpsError(
        "failed-precondition",
        "Cannot set kind to new/followup without practitionerId."
      );
    }
  }

  const keys = Object.keys(patch);
  if (keys.length === 0) {
    throw new HttpsError("invalid-argument", "No changes provided.");
  }

  // ─────────────────────────────
  // Block closure overlaps (SERVER-SIDE ENFORCEMENT)
  // + Override marker fields + AUDIT (for override use)
  // ─────────────────────────────
  let overlappedClosureIds: string[] = [];
  let didUseClosureOverride = false;

  // Only check overlaps when time is changing.
  if (newStartAt && newEndAt) {
    overlappedClosureIds = await findOverlappingClosures({
      db,
      clinicId,
      startAt: newStartAt,
      endAt: newEndAt,
    });

    // If overlapping and NOT overriding => block
    if (!allowClosedOverride && overlappedClosureIds.length > 0) {
      throw new HttpsError("failed-precondition", "Appointment overlaps a clinic closure.", {
        closureId: overlappedClosureIds[0],
        closureIds: overlappedClosureIds,
      });
    }

    // If overriding and overlapping => mark appointment + audit
    if (allowClosedOverride && overlappedClosureIds.length > 0) {
      didUseClosureOverride = true;

      patch.closureOverride = true;
      patch.closureOverrideByUid = uid;
      patch.closureOverrideAt = now;

      // Store which closures were involved (handy for UI/reporting)
      patch.closureOverrideClosureIds = overlappedClosureIds;
    }

    // If moved OUT of closures, clear any previous override marker.
    if (overlappedClosureIds.length === 0) {
      patch.closureOverride = false;
      patch.closureOverrideByUid = admin.firestore.FieldValue.delete();
      patch.closureOverrideAt = admin.firestore.FieldValue.delete();
      patch.closureOverrideClosureIds = admin.firestore.FieldValue.delete();
    }
  }

  patch.updatedAt = now;
  patch.updatedByUid = uid;

  await apptRef.update(patch);

  // ✅ IMPORTANT: use the "clinic.closure.override.used" type so your Audit screen filter matches.
  if (didUseClosureOverride) {
    const startMs = newStartAt ? newStartAt.toMillis() : null;
    const endMs = newEndAt ? newEndAt.toMillis() : null;

    await writeAuditEvent(db, clinicId, {
      type: "clinic.closure.override.used",
      actorUid: uid,
      appointmentId,
      metadata: {
        appointmentId,
        closureId: overlappedClosureIds[0] ?? null,
        closureIds: overlappedClosureIds,
        startMs,
        endMs,
        allowClosedOverride: true,
      },
    });
  }

  return { success: true, updatedKeys: Object.keys(patch) };
}
