import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { requireActiveMemberWithPerm } from "../authz";
import { writeAuditEvent } from "../audit/audit";

type Input = {
  clinicId: string;
  assessmentId: string;
  format?: "pdf" | "html";
};

export async function generateAssessmentPdf(req: CallableRequest<Input>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = (req.data?.clinicId ?? "").trim();
  const assessmentId = (req.data?.assessmentId ?? "").trim();
  if (!clinicId || !assessmentId) {
    throw new HttpsError("invalid-argument", "clinicId and assessmentId are required.");
  }

  const db = admin.firestore();
  const uid = req.auth.uid;

  await requireActiveMemberWithPerm(db, clinicId, uid, "clinical.read");

  const ref = db.collection("clinics").doc(clinicId).collection("assessments").doc(assessmentId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Assessment not found.");

  await writeAuditEvent(db, clinicId, {
    type: "assessment.pdf.requested",
    actorUid: uid,
    metadata: { assessmentId, format: req.data?.format ?? "pdf" },
  });

  return {
    success: false,
    status: "not_implemented",
    message:
      "PDF generation pipeline not implemented yet. Contract is in place; implement later via Storage + renderer.",
  };
}
