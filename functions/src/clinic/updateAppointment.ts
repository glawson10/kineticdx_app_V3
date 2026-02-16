// functions/src/clinic/updateAppointment.ts
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { writeAuditEvent } from "./audit/audit";

const MIN_DURATION_MINS = 5;
const MAX_DURATION_MINS = 240;

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
  practitionerId?: string | null; // allow reassign
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

function parseTimestamp(v: any): admin.firestore.Timestamp | null {
  if (!v) return null;
  if (v instanceof admin.firestore.Timestamp) return v;
  if (typeof v?.toMillis === "function") return v;
  if (typeof v === "object" && typeof (v as any)._seconds === "number") {
    return new admin.firestore.Timestamp((v as any)._seconds, (v as any)._nanoseconds ?? 0);
  }
  if (typeof v === "number" && Number.isFinite(v)) return admin.firestore.Timestamp.fromMillis(v);
  return null;
}

/**
 * Returns true if the given practitioner has any other non-cancelled appointment
 * overlapping [startAt, endAt), excluding excludeAppointmentId.
 * Used for overlap validation on update/reschedule.
 * When tx is provided, runs inside the transaction for consistency.
 */
async function hasPractitionerOverlap(params: {
  db: admin.firestore.Firestore;
  clinicId: string;
  practitionerId: string;
  startAt: admin.firestore.Timestamp;
  endAt: admin.firestore.Timestamp;
  excludeAppointmentId: string;
  tx?: admin.firestore.Transaction;
}): Promise<boolean> {
  const { db, clinicId, practitionerId, startAt, endAt, excludeAppointmentId, tx } = params;
  const col = db.collection(`clinics/${clinicId}/appointments`);
  const query = col.where("practitionerId", "==", practitionerId).where("startAt", "<", endAt);
  const snap = tx ? await tx.get(query) : await query.get();

  const startMs = startAt.toMillis();
  const endMs = endAt.toMillis();

  for (const doc of snap.docs) {
    if (doc.id === excludeAppointmentId) continue;
    const d = doc.data() as any;
    const status = (d?.status ?? "").toString().toLowerCase();
    if (status === "cancelled") continue;

    const otherStart = parseTimestamp(d?.startAt ?? d?.start);
    const otherEnd = parseTimestamp(d?.endAt ?? d?.end);
    if (!otherStart || !otherEnd) continue;
    const otherStartMs = otherStart.toMillis();
    const otherEndMs = otherEnd.toMillis();
    const overlaps = otherStartMs < endMs && otherEndMs > startMs;
    if (overlaps) return true;
  }
  return false;
}

async function readPractitionerDoc(
  db: admin.firestore.Firestore,
  clinicId: string,
  practitionerId: string
): Promise<{ displayName: string; active: boolean }> {
  const paths = [
    `clinics/${clinicId}/members/${practitionerId}`,
    `clinics/${clinicId}/memberships/${practitionerId}`,
    `clinics/${clinicId}/practitioners/${practitionerId}`,
    `clinics/${clinicId}/staff/${practitionerId}`,
  ];
  for (const path of paths) {
    const snap = await db.doc(path).get();
    if (!snap.exists) continue;
    const d = (snap.data() ?? {}) as any;
    const active =
      d.active === true ||
      d.status === "active" ||
      (d.status as any)?.active === true;
    const displayName =
      (d.displayName ?? d.name ?? "").toString().trim() || practitionerId;
    return { displayName, active };
  }
  return { displayName: practitionerId, active: false };
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
      const durationMins = (endTs.toMillis() - startTs.toMillis()) / (60 * 1000);
      if (durationMins < MIN_DURATION_MINS || durationMins > MAX_DURATION_MINS) {
        throw new HttpsError(
          "invalid-argument",
          `Duration must be between ${MIN_DURATION_MINS} and ${MAX_DURATION_MINS} minutes.`
        );
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
      const durationMins = (endTs.toMillis() - startTs.toMillis()) / (60 * 1000);
      if (durationMins < MIN_DURATION_MINS || durationMins > MAX_DURATION_MINS) {
        throw new HttpsError(
          "invalid-argument",
          `Duration must be between ${MIN_DURATION_MINS} and ${MAX_DURATION_MINS} minutes.`
        );
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
  // practitionerId update + denormalized practitionerName
  // ─────────────────────────────
  if ("practitionerId" in (req.data ?? {})) {
    const raw = req.data?.practitionerId;
    const pid = (raw ?? "").toString().trim();

    const pracResult = await readPractitionerDoc(db, clinicId, pid || "x");
    if (pid && !pracResult.active) {
      throw new HttpsError(
        "failed-precondition",
        "Selected practitioner is not an active clinic member."
      );
    }

    patch.practitionerId = pid || "";
    patch.practitionerName = pid ? pracResult.displayName : "";
  }

  // ─────────────────────────────
  // If kind changed away from admin, ensure required IDs exist
  // ─────────────────────────────
  if (patch.kind && patch.kind !== "admin") {
    const patientId = (appt["patientId"] ?? "").toString().trim();
    const serviceId = ((patch.serviceId ?? appt["serviceId"]) ?? "").toString().trim();
    const practitionerId = ((patch.practitionerId ?? appt["practitionerId"]) ?? "").toString().trim();

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

  // Resolve effective time and practitioner for overlap check
  const effectiveStartAt =
    newStartAt ?? parseTimestamp(appt["startAt"] ?? appt["start"]) ?? null;
  const effectiveEndAt =
    newEndAt ?? parseTimestamp(appt["endAt"] ?? appt["end"]) ?? null;
  const effectivePractitionerId = (
    (patch.practitionerId !== undefined ? patch.practitionerId : appt["practitionerId"]) ?? ""
  ).toString().trim();
  const timeOrPractitionerChanged =
    (newStartAt != null || newEndAt != null) || "practitionerId" in (patch as any);

  await db.runTransaction(async (tx) => {
    const freshSnap = await tx.get(apptRef);
    if (!freshSnap.exists) throw new HttpsError("not-found", "Appointment not found.");

    if (effectivePractitionerId && effectiveStartAt && effectiveEndAt && timeOrPractitionerChanged) {
      const overlap = await hasPractitionerOverlap({
        db,
        clinicId,
        practitionerId: effectivePractitionerId,
        startAt: effectiveStartAt,
        endAt: effectiveEndAt,
        excludeAppointmentId: appointmentId,
        tx,
      });
      if (overlap) {
        throw new HttpsError(
          "failed-precondition",
          "This time slot is already booked for the selected practitioner.",
          { code: "practitioner_overlap" }
        );
      }
    }

    tx.update(apptRef, patch);
  });

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

  await writeAuditEvent(db, clinicId, {
    type: "appointment.updated",
    actorUid: uid,
    appointmentId,
    metadata: {
      appointmentId,
      updatedKeys: Object.keys(patch),
      startAtMs: newStartAt?.toMillis() ?? effectiveStartAt?.toMillis() ?? null,
      endAtMs: newEndAt?.toMillis() ?? effectiveEndAt?.toMillis() ?? null,
    },
  });

  const updatedFields = Object.keys(patch);
  return {
    success: true,
    appointmentId,
    updatedFields,
    startAt: newStartAt?.toMillis() ?? effectiveStartAt?.toMillis() ?? undefined,
    endAt: newEndAt?.toMillis() ?? effectiveEndAt?.toMillis() ?? undefined,
  };
}
