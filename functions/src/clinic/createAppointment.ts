import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions";

import { createAppointmentInternal } from "./appointments/createAppointmentInternal";

type Input = {
  clinicId: string;
  kind?: "admin" | "new" | "followup";
  patientId?: string;
  serviceId?: string;
  practitionerId?: string;

  // Preferred: epoch millis (unambiguous)
  startMs?: number;
  endMs?: number;

  // Legacy fallback
  start?: string; // ISO date-time
  end?: string; // ISO date-time

  // allow override into closures (requires settings.write)
  allowClosedOverride?: boolean;

  resourceIds?: string[];
};

function getBoolPerm(perms: unknown, key: string): boolean {
  return typeof perms === "object" && perms !== null && (perms as any)[key] === true;
}

function requirePerm(perms: unknown, keys: string[], message: string) {
  const ok = keys.some((k) => getBoolPerm(perms, k));
  if (!ok) throw new HttpsError("permission-denied", message);
}

function parseMillis(label: string, ms?: number): Date | null {
  if (ms == null) return null;
  if (typeof ms !== "number" || !Number.isFinite(ms) || ms <= 0) {
    throw new HttpsError("invalid-argument", `Invalid ${label}Ms.`);
  }
  return new Date(ms);
}

function parseIso(label: string, value?: string): Date | null {
  if (!value) return null;
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) {
    throw new HttpsError("invalid-argument", `Invalid ${label}. Must be ISO8601 string.`);
  }
  return d;
}

async function getMembershipData(
  db: FirebaseFirestore.Firestore,
  clinicId: string,
  uid: string
): Promise<FirebaseFirestore.DocumentData | null> {
  // ✅ Canonical first: members/{uid}
  const canonical = db.collection("clinics").doc(clinicId).collection("members").doc(uid);
  const legacy = db.collection("clinics").doc(clinicId).collection("memberships").doc(uid);

  const c = await canonical.get();
  if (c.exists) return c.data() ?? {};

  const l = await legacy.get();
  if (l.exists) return l.data() ?? {};

  return null;
}


function isActiveMember(data: FirebaseFirestore.DocumentData): boolean {
  const status = (data.status ?? "").toString().toLowerCase().trim();
  if (status === "suspended" || status === "invited") return false;

  if (!("active" in data)) return true;
  return data.active === true;
}

export async function createAppointment(req: CallableRequest<Input>) {
  try {
    if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

    const data = (req.data ?? {}) as Partial<Input>;

    const clinicId = (data.clinicId ?? "").toString().trim();
    const kind: "admin" | "new" | "followup" =
      data.kind === "admin" || data.kind === "new" || data.kind === "followup"
        ? data.kind
        : "followup";

    if (!clinicId) throw new HttpsError("invalid-argument", "clinicId is required.");

    // ─────────────────────────────
    // Time parsing (prefer millis)
    // ─────────────────────────────
    const startMsProvided = data.startMs != null;
    const endMsProvided = data.endMs != null;
    const startIsoProvided = data.start != null;
    const endIsoProvided = data.end != null;

    const anyTimeProvided =
      startMsProvided || endMsProvided || startIsoProvided || endIsoProvided;
    if (!anyTimeProvided) {
      throw new HttpsError("invalid-argument", "startMs/endMs (or start/end) are required.");
    }

    let startDt: Date | null = null;
    let endDt: Date | null = null;

    if (startMsProvided || endMsProvided) {
      if (startMsProvided !== endMsProvided) {
        throw new HttpsError("invalid-argument", "Provide both startMs and endMs.");
      }
      startDt = parseMillis("start", data.startMs);
      endDt = parseMillis("end", data.endMs);
    } else {
      if (startIsoProvided !== endIsoProvided) {
        throw new HttpsError("invalid-argument", "Provide both start and end.");
      }
      startDt = parseIso("start", data.start);
      endDt = parseIso("end", data.end);
    }

    if (!startDt || !endDt) throw new HttpsError("invalid-argument", "Invalid start/end.");
    if (endDt <= startDt) {
      throw new HttpsError("invalid-argument", "Invalid start/end (end must be after start).");
    }

    const db = admin.firestore();
    const uid = req.auth.uid;

    // ─────────────────────────────
    // Membership + permissions (canonical)
    // ─────────────────────────────
    const member = await getMembershipData(db, clinicId, uid);
    if (!member || !isActiveMember(member)) {
      throw new HttpsError("permission-denied", "Not an active clinic member.");
    }

    const perms = member.permissions ?? {};
    const allowClosedOverride = data.allowClosedOverride === true;

    if (allowClosedOverride) {
      requirePerm(
        perms,
        ["settings.write"],
        "No permission to override clinic closures (settings.write required)."
      );
    } else {
      requirePerm(perms, ["schedule.read"], "No schedule access (schedule.read required).");
      requirePerm(
        perms,
        ["schedule.write", "schedule.manage"],
        "No scheduling permission (schedule.write required)."
      );
    }

    if (kind !== "admin") {
      requirePerm(perms, ["patients.read"], "No patient access (patients.read required).");
    }

    return await createAppointmentInternal(db, {
      clinicId,
      kind,
      patientId: data.patientId,
      serviceId: data.serviceId,
      practitionerId: data.practitionerId,
      startDt,
      endDt,
      resourceIds: data.resourceIds,
      actorUid: uid,
      allowClosedOverride,
    });
  } catch (err: any) {
    logger.error("createAppointment failed", {
      err: err?.message ?? String(err),
      stack: err?.stack,
      code: err?.code,
      details: err?.details,
    });

    if (err instanceof HttpsError) throw err;

    throw new HttpsError("internal", "createAppointment crashed. Check function logs.", {
      original: err?.message ?? String(err),
    });
  }
}
