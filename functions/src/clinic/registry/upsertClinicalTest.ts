import * as admin from "firebase-admin";
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import { requireTemplatesManage, cleanString, asStringArray } from "./_helpers";

type Input = {
  clinicId: string;
  testId?: string | null;         // optional fixed ID
  name: string;
  shortName?: string | null;
  bodyRegions?: string[];
  tags?: string[];
  category?: string | null;

  instructions?: string | null;
  positiveCriteria?: string | null;
  contraindications?: string | null;
  interpretation?: string | null;

  resultType?: string | null;     // "ternary" etc
  allowedResults?: string[];

  active?: boolean;
};

export async function upsertClinicalTest(req: CallableRequest<Input>) {
  const { db, clinicId, uid } = await requireTemplatesManage(req);

  const name = cleanString(req.data?.name, 120);
  if (!name) throw new HttpsError("invalid-argument", "name required.");

  const testId = (req.data?.testId ?? "").toString().trim();
  const ref = testId
    ? db.collection("clinics").doc(clinicId).collection("clinicalTestRegistry").doc(testId)
    : db.collection("clinics").doc(clinicId).collection("clinicalTestRegistry").doc();

  const now = admin.firestore.FieldValue.serverTimestamp();

  const payload = {
    schemaVersion: 1,
    name,
    shortName: cleanString(req.data?.shortName, 80) || null,
    bodyRegions: asStringArray(req.data?.bodyRegions),
    tags: asStringArray(req.data?.tags),
    category: cleanString(req.data?.category, 80) || "special_test",

    instructions: cleanString(req.data?.instructions, 5000) || null,
    positiveCriteria: cleanString(req.data?.positiveCriteria, 2000) || null,
    contraindications: cleanString(req.data?.contraindications, 2000) || null,
    interpretation: cleanString(req.data?.interpretation, 5000) || null,

    resultType: cleanString(req.data?.resultType, 40) || "ternary",
    allowedResults: asStringArray(req.data?.allowedResults).length > 0
      ? asStringArray(req.data?.allowedResults)
      : ["positive", "negative", "notTested"],

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

  return { success: true, testId: ref.id };
}
