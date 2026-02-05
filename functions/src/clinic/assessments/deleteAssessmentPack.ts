import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { requireActiveMemberWithPerm } from "../authz";
import { writeAuditEvent } from "../audit/audit";
import { assessmentPackRef } from "../paths";

type Input = {
  clinicId: string;
  packId: string;
};

export async function deleteAssessmentPack(req: CallableRequest<Input>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = (req.data?.clinicId ?? "").trim();
  const packId = (req.data?.packId ?? "").trim();
  if (!clinicId || !packId) {
    throw new HttpsError("invalid-argument", "clinicId, packId required.");
  }

  const db = admin.firestore();
  const uid = req.auth.uid;

  await requireActiveMemberWithPerm(db, clinicId, uid, "settings.write");

  const ref = assessmentPackRef(db, clinicId, packId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Assessment pack not found.");

  await ref.delete();

  await writeAuditEvent(db, clinicId, {
    type: "assessmentPack.deleted",
    actorUid: uid,
    metadata: { packId },
  });

  return { success: true };
}
