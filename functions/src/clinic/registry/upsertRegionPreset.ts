import * as admin from "firebase-admin";
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import { requireTemplatesManage, cleanString, asStringArray } from "./_helpers";

type Input = {
  clinicId: string;
  regionId?: string | null;        // optional fixed doc id
  region: string;                  // e.g. "cervical"
  displayName?: string | null;
  segments?: string[];
  defaultEnabled?: boolean;
  active?: boolean;
};

export async function upsertRegionPreset(req: CallableRequest<Input>) {
  const { db, clinicId, uid } = await requireTemplatesManage(req);

  const region = cleanString(req.data?.region, 60);
  if (!region) throw new HttpsError("invalid-argument", "region required.");

  const regionId = (req.data?.regionId ?? "").toString().trim();
  const ref = regionId
    ? db.collection("clinics").doc(clinicId).collection("regionPresets").doc(regionId)
    : db.collection("clinics").doc(clinicId).collection("regionPresets").doc(region);

  const now = admin.firestore.FieldValue.serverTimestamp();

  const payload = {
    schemaVersion: 1,
    region,
    displayName: cleanString(req.data?.displayName, 120) || region,
    segments: asStringArray(req.data?.segments),
    defaultEnabled: (req.data?.defaultEnabled ?? true) === true,
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

  return { success: true, regionId: ref.id };
}
