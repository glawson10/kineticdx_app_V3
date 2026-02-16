// functions/src/clinic/cancelAppointment.ts
// Status-based cancel (no delete). Projection is updated by onAppointmentWrite_toBusyBlock trigger.
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { writeAuditEvent } from "./audit/audit";

type Input = {
  clinicId: string;
  appointmentId: string;
  reason?: string;
};

function getBoolPerm(perms: unknown, key: string): boolean {
  return typeof perms === "object" && perms !== null && (perms as any)[key] === true;
}

function requirePerm(perms: unknown, keys: string[], message: string) {
  const ok = keys.some((k) => getBoolPerm(perms, k));
  if (!ok) throw new HttpsError("permission-denied", message);
}

async function getMembershipData(
  db: admin.firestore.Firestore,
  clinicId: string,
  uid: string
): Promise<FirebaseFirestore.DocumentData | null> {
  const membersRef = db.doc(`clinics/${clinicId}/members/${uid}`);
  const membershipsRef = db.doc(`clinics/${clinicId}/memberships/${uid}`);
  const membersSnap = await membersRef.get();
  if (membersSnap.exists) return membersSnap.data() ?? {};
  const legacySnap = await membershipsRef.get();
  if (legacySnap.exists) return legacySnap.data() ?? {};
  return null;
}

function isActiveMember(data: FirebaseFirestore.DocumentData): boolean {
  const status = (data.status ?? "").toString().toLowerCase().trim();
  if (status === "invited" || status === "suspended") return false;
  if (!("active" in data)) return true;
  return (data as any).active === true;
}

export async function cancelAppointment(req: CallableRequest<Input>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = (req.data?.clinicId ?? "").toString().trim();
  const appointmentId = (req.data?.appointmentId ?? "").toString().trim();
  const reason = (req.data?.reason ?? "").toString().trim() || undefined;

  if (!clinicId || !appointmentId) {
    throw new HttpsError("invalid-argument", "clinicId and appointmentId are required.");
  }

  const db = admin.firestore();
  const uid = req.auth.uid;

  const memberData = await getMembershipData(db, clinicId, uid);
  if (!memberData || !isActiveMember(memberData)) {
    throw new HttpsError("permission-denied", "Not a clinic member.");
  }

  const perms = (memberData as any).permissions ?? {};
  requirePerm(perms, ["schedule.write", "schedule.manage"], "No scheduling permission.");

  const apptRef = db
    .collection("clinics")
    .doc(clinicId)
    .collection("appointments")
    .doc(appointmentId);

  const apptSnap = await apptRef.get();
  if (!apptSnap.exists) throw new HttpsError("not-found", "Appointment not found.");

  const appt = apptSnap.data() ?? {};
  const currentStatus = (appt["status"] ?? "booked").toString().toLowerCase();

  if (currentStatus === "cancelled") {
    return { success: true, alreadyCancelled: true };
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  await apptRef.update({
    status: "cancelled",
    cancelledAt: now,
    cancelledByUid: uid,
    ...(reason !== undefined && { cancelReason: reason }),
    updatedAt: now,
    updatedByUid: uid,
  });

  await writeAuditEvent(db, clinicId, {
    type: "appointment.cancelled",
    actorUid: uid,
    appointmentId,
    metadata: { appointmentId, reason: reason ?? null },
  });

  return { success: true, alreadyCancelled: false };
}
