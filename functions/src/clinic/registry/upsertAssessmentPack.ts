import * as admin from "firebase-admin";
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import { requireTemplatesManage, cleanString, asStringArray } from "./_helpers";

type Input = {
  clinicId: string;
  packId?: string | null;
  name: string;
  bodyRegion: string;              // e.g. "shoulder"
  defaultSide?: string | null;     // "left" etc
  noteTypes?: string[];

  objectiveTemplate?: Record<string, any>;
  subjectiveTemplate?: Record<string, any>;

  active?: boolean;
};

export async function upsertAssessmentPack(req: CallableRequest<Input>) {
  const { db, clinicId, uid } = await requireTemplatesManage(req);

  const name = cleanString(req.data?.name, 120);
  const bodyRegion = cleanString(req.data?.bodyRegion, 60);

  if (!name || !bodyRegion) {
    throw new HttpsError("invalid-argument", "name and bodyRegion required.");
  }

  const packId = (req.data?.packId ?? "").toString().trim();
  const ref = packId
    ? db.collection("clinics").doc(clinicId).collection("assessmentPacks").doc(packId)
    : db.collection("clinics").doc(clinicId).collection("assessmentPacks").doc();

  const now = admin.firestore.FieldValue.serverTimestamp();

  const payload = {
    schemaVersion: 1,
    name,
    bodyRegion,
    defaultSide: cleanString(req.data?.defaultSide, 20) || "central",
    noteTypes: asStringArray(req.data?.noteTypes),

    objectiveTemplate: req.data?.objectiveTemplate ?? {},
    subjectiveTemplate: req.data?.subjectiveTemplate ?? {},

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

  return { success: true, packId: ref.id };
}
