import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { requireActiveMemberWithPerm } from "../authz";

type DeleteClinicalTestInput = { clinicId: string; testId: string };

export async function deleteClinicalTest(req: CallableRequest<DeleteClinicalTestInput>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = (req.data?.clinicId ?? "").trim();
  const testId = (req.data?.testId ?? "").trim();
  if (!clinicId || !testId) {
    throw new HttpsError("invalid-argument", "clinicId and testId required.");
  }

  const db = admin.firestore();
  const uid = req.auth.uid;

  await requireActiveMemberWithPerm(db, clinicId, uid, "registries.manage");

  // ✅ Matches Firestore rules path
  const ref = db
    .collection("clinics")
    .doc(clinicId)
    .collection("clinicalTestRegistry")
    .doc(testId);

  await ref.delete();
  return { success: true };
}
