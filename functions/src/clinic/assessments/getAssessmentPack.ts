import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { requireActiveMember } from "../authz";

type Input = {
  clinicId: string;
  packId: string;
};

export async function getAssessmentPack(req: CallableRequest<Input>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = (req.data?.clinicId ?? "").trim();
  const packId = (req.data?.packId ?? "").trim();
  if (!clinicId || !packId) {
    throw new HttpsError("invalid-argument", "clinicId and packId are required.");
  }

  const db = admin.firestore();
  const uid = req.auth.uid;

  await requireActiveMember(db, clinicId, uid);

  const ref = db.collection("clinics").doc(clinicId).collection("assessmentPacks").doc(packId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "assessmentPack not found.");

  return { packId: snap.id, data: snap.data() };
}
