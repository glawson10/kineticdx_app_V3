import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { requireActiveMemberWithPerm } from "../authz";
import { assessmentRef } from "../paths";
import { writeAuditEvent } from "../audit/audit";

type Input = {
  clinicId: string;
  assessmentId: string;
  consentGiven?: boolean;
  answers?: Record<string, any>;
};

export async function updateAssessment(req: CallableRequest<Input>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = (req.data?.clinicId ?? "").trim();
  const assessmentId = (req.data?.assessmentId ?? "").trim();

  const consentGiven = req.data?.consentGiven;
  const answers = req.data?.answers;

  if (!clinicId || !assessmentId) {
    throw new HttpsError("invalid-argument", "clinicId, assessmentId required.");
  }
  if (answers != null && (typeof answers !== "object" || Array.isArray(answers))) {
    throw new HttpsError("invalid-argument", "answers must be an object.");
  }

  const db = admin.firestore();
  const uid = req.auth.uid;

  await requireActiveMemberWithPerm(db, clinicId, uid, "clinical.write");

  const ref = assessmentRef(db, clinicId, assessmentId);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Assessment not found.");

    const data = snap.data() as any;
    if ((data.status ?? "draft") !== "draft") {
      throw new HttpsError("failed-precondition", "Only draft assessments can be updated.");
    }

    const patch: Record<string, any> = {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedByUid: uid,
    };

    if (typeof consentGiven === "boolean") patch.consentGiven = consentGiven;
    if (answers != null) patch.answers = answers;

    tx.update(ref, patch);
  });

  await writeAuditEvent(db, clinicId, {
    type: "assessment.updated",
    actorUid: uid,
    metadata: { assessmentId },
  });

  return { success: true };
}
