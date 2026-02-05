import * as admin from "firebase-admin";
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import { requireTemplatesManage, cleanString, asStringArray } from "./_helpers";

type Input = {
  clinicId: string;
  measureId?: string | null;
  name: string;
  fullName?: string | null;
  tags?: string[];
  scoreFormatHint?: string | null;
  active?: boolean;
};

export async function upsertOutcomeMeasure(req: CallableRequest<Input>) {
  const { db, clinicId, uid } = await requireTemplatesManage(req);

  const name = cleanString(req.data?.name, 80);
  if (!name) throw new HttpsError("invalid-argument", "name required.");

  const measureId = (req.data?.measureId ?? "").toString().trim();
  const ref = measureId
    ? db.collection("clinics").doc(clinicId).collection("outcomeMeasures").doc(measureId)
    : db.collection("clinics").doc(clinicId).collection("outcomeMeasures").doc();

  const now = admin.firestore.FieldValue.serverTimestamp();

  const payload = {
    schemaVersion: 1,
    name,
    fullName: cleanString(req.data?.fullName, 200) || null,
    tags: asStringArray(req.data?.tags),
    scoreFormatHint: cleanString(req.data?.scoreFormatHint, 200) || null,
    active: (req.data?.active ?? true) === true,
    updatedAt: now,
    updatedByUid: uid,
  };

  const snap = await ref.get();
  if (!snap.exists) {
    await ref.set({ ...payload, createdAt: now, createdByUid: uid });
  } else {
    await ref.update(payload);
  }

  return { success: true, measureId: ref.id };
}
