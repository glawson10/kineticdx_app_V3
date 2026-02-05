import * as admin from "firebase-admin";
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import { requireTemplatesManage } from "./_helpers";

type Input = {
  clinicId: string;
  collection: "clinicalTestRegistry" | "assessmentPacks" | "outcomeMeasures" | "regionPresets";
  id: string;
  active: boolean;
};

export async function setRegistryActive(req: CallableRequest<Input>) {
  const { db, clinicId, uid } = await requireTemplatesManage(req);

  const collection = req.data?.collection;
  const id = (req.data?.id ?? "").trim();

  if (!collection || !id) {
    throw new HttpsError("invalid-argument", "collection and id required.");
  }

  const now = admin.firestore.FieldValue.serverTimestamp();

  await db.collection("clinics").doc(clinicId)
    .collection(collection)
    .doc(id)
    .update({
      active: req.data.active === true,
      updatedAt: now,
      updatedByUid: uid,
    });

  return { success: true };
}
