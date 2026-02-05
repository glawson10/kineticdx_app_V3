import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { requireActiveMemberWithPerm } from "../authz";

type DeleteOutcomeMeasureInput = { clinicId: string; measureId: string };

export async function deleteOutcomeMeasure(req: CallableRequest<DeleteOutcomeMeasureInput>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = (req.data?.clinicId ?? "").trim();
  const measureId = (req.data?.measureId ?? "").trim();
  if (!clinicId || !measureId) {
    throw new HttpsError("invalid-argument", "clinicId and measureId required.");
  }

  const db = admin.firestore();
  const uid = req.auth.uid;

  await requireActiveMemberWithPerm(db, clinicId, uid, "registries.manage");

  // ✅ Matches Firestore rules path
  const ref = db
    .collection("clinics")
    .doc(clinicId)
    .collection("outcomeMeasures")
    .doc(measureId);

  await ref.delete();
  return { success: true };
}
