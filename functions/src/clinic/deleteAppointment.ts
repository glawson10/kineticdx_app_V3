import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

type Input = {
  clinicId: string;
  appointmentId: string;
};

function getBoolPerm(perms: unknown, key: string): boolean {
  return typeof perms === "object" && perms !== null && (perms as any)[key] === true;
}

function requirePerm(perms: unknown, keys: string[], message: string) {
  const ok = keys.some((k) => getBoolPerm(perms, k));
  if (!ok) throw new HttpsError("permission-denied", message);
}

export async function deleteAppointment(req: CallableRequest<Input>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = (req.data?.clinicId ?? "").toString().trim();
  const appointmentId = (req.data?.appointmentId ?? "").toString().trim();

  if (!clinicId || !appointmentId) {
    throw new HttpsError("invalid-argument", "clinicId, appointmentId are required.");
  }

  const db = admin.firestore();
  const uid = req.auth.uid;

  const memberRef = db.collection("clinics").doc(clinicId).collection("members").doc(uid);
  const memberSnap = await memberRef.get();
  if (!memberSnap.exists || memberSnap.data()?.active !== true) {
    throw new HttpsError("permission-denied", "Not a clinic member.");
  }

  const perms = memberSnap.data()?.permissions ?? {};
  requirePerm(perms, ["schedule.write", "schedule.manage"], "No scheduling permission.");

  const apptRef = db.collection("clinics").doc(clinicId).collection("appointments").doc(appointmentId);
  const apptSnap = await apptRef.get();
  if (!apptSnap.exists) throw new HttpsError("not-found", "Appointment not found.");

  await apptRef.delete();

  return { success: true };
}
