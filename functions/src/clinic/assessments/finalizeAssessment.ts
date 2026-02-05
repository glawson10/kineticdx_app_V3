import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { requireActiveMemberWithPerm } from "../authz";
import { assessmentRef } from "../paths";
import { writeAuditEvent } from "../audit/audit";

type Input = {
  clinicId: string;
  assessmentId: string;
  triageStatus?: "green" | "amber" | "red";
};

export async function finalizeAssessment(req: CallableRequest<Input>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = (req.data?.clinicId ?? "").trim();
  const assessmentId = (req.data?.assessmentId ?? "").trim();
  const triageStatus = (req.data?.triageStatus ?? "").trim() as any;

  if (!clinicId || !assessmentId) {
    throw new HttpsError("invalid-argument", "clinicId, assessmentId required.");
  }

  const db = admin.firestore();
  const uid = req.auth.uid;

  await requireActiveMemberWithPerm(db, clinicId, uid, "clinical.write");

  const ref = assessmentRef(db, clinicId, assessmentId);
  const now = admin.firestore.FieldValue.serverTimestamp();

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Assessment not found.");

    const data = snap.data() as any;
    if ((data.status ?? "draft") !== "draft") {
      throw new HttpsError("failed-precondition", "Assessment is not a draft.");
    }

    if (data.consentGiven !== true) {
      throw new HttpsError("failed-precondition", "Consent must be true before finalizing.");
    }

    const patch: Record<string, any> = {
      status: "finalized",
      submittedAt: now,
      finalizedAt: now,
      updatedAt: now,
      updatedByUid: uid,

      pdf: {
        status: "queued",
        storagePath: data.pdf?.storagePath ?? null,
        url: data.pdf?.url ?? null,
        updatedAt: now,
      },
    };

    if (triageStatus === "green" || triageStatus === "amber" || triageStatus === "red") {
      patch.triageStatus = triageStatus;
    }

    tx.update(ref, patch);
  });

  await writeAuditEvent(db, clinicId, {
    type: "assessment.finalized",
    actorUid: uid,
    metadata: { assessmentId },
  });

  return { success: true };
}
