import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

type Input = {
  clinicId: string;
  appointmentId: string;
  status: string; // booked | attended | cancelled | missed
};

function getBoolPerm(perms: unknown, key: string): boolean {
  return typeof perms === "object" && perms !== null && (perms as any)[key] === true;
}

function requirePerm(perms: unknown, keys: string[], message: string) {
  const ok = keys.some((k) => getBoolPerm(perms, k));
  if (!ok) throw new HttpsError("permission-denied", message);
}

function normalizeStatus(
  s: string
): "booked" | "attended" | "cancelled" | "missed" {
  const v = (s ?? "").toLowerCase().trim();
  const allowed = new Set(["booked", "attended", "cancelled", "missed"]);
  if (!allowed.has(v)) {
    throw new HttpsError(
      "invalid-argument",
      "Invalid status. Use booked | attended | cancelled | missed."
    );
  }
  return v as any;
}

async function getMembershipData(
  db: FirebaseFirestore.Firestore,
  clinicId: string,
  uid: string
): Promise<FirebaseFirestore.DocumentData | null> {
  const canonical = db.collection("clinics").doc(clinicId).collection("memberships").doc(uid);
  const legacy = db.collection("clinics").doc(clinicId).collection("members").doc(uid);

  const c = await canonical.get();
  if (c.exists) return c.data() ?? {};

  const l = await legacy.get();
  if (l.exists) return l.data() ?? {};

  return null;
}

function isActiveMember(data: FirebaseFirestore.DocumentData): boolean {
  const status = (data.status ?? "").toString().toLowerCase().trim();
  if (status === "suspended" || status === "invited") return false;

  if (!("active" in data)) return true; // back-compat
  return data.active === true;
}

export async function updateAppointmentStatus(req: CallableRequest<Input>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = (req.data?.clinicId ?? "").toString().trim();
  const appointmentId = (req.data?.appointmentId ?? "").toString().trim();
  const status = normalizeStatus((req.data?.status ?? "").toString());

  if (!clinicId || !appointmentId) {
    throw new HttpsError("invalid-argument", "clinicId and appointmentId are required.");
  }

  const db = admin.firestore();
  const uid = req.auth.uid;

  // ─────────────────────────────
  // Membership + permission check (canonical)
  // ─────────────────────────────
  const member = await getMembershipData(db, clinicId, uid);
  if (!member || !isActiveMember(member)) {
    throw new HttpsError("permission-denied", "Not an active clinic member.");
  }

  const perms = member.permissions ?? {};
  requirePerm(perms, ["schedule.write", "schedule.manage"], "No scheduling permission.");

  // ─────────────────────────────
  // Load appointment
  // ─────────────────────────────
  const apptRef = db
    .collection("clinics")
    .doc(clinicId)
    .collection("appointments")
    .doc(appointmentId);

  const apptSnap = await apptRef.get();
  if (!apptSnap.exists) throw new HttpsError("not-found", "Appointment not found.");

  const appt = apptSnap.data() ?? {};

  // Prevent status changes on admin blocks
  const kind = (appt["kind"] ?? "").toString().toLowerCase();
  if (kind === "admin" || !(appt["patientId"] ?? "").toString()) {
    throw new HttpsError(
      "failed-precondition",
      "Admin blocks cannot have attendance status."
    );
  }

  const currentStatus = (appt["status"] ?? "booked").toString().toLowerCase();
  if (currentStatus === status) {
    return { success: true, unchanged: true };
  }

  // ─────────────────────────────
  // Build patch
  // ─────────────────────────────
  const now = admin.firestore.FieldValue.serverTimestamp();
  const patch: Record<string, any> = {
    status,
    updatedAt: now,
    updatedByUid: uid,
  };

  // Clear all status timestamps first
  patch.attendedAt = null;
  patch.cancelledAt = null;
  patch.missedAt = null;

  if (status === "attended") patch.attendedAt = now;
  if (status === "cancelled") patch.cancelledAt = now;
  if (status === "missed") patch.missedAt = now;

  await apptRef.update(patch);

  return { success: true };
}
