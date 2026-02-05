import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { requireActiveMemberWithPerm } from "../authz";
import { schemaVersion } from "../../schema/schemaVersions";
import { writeAuditEvent } from "../audit/audit";

export type SubmitAssessmentInput = {
  clinicId: string;
  packId: string;
  regionKey: string;

  patientId?: string | null;
  appointmentId?: string | null;

  answers: Record<string, any>;

  consentGiven?: boolean;
  triageStatus?: "green" | "amber" | "red" | null;
  clinicianSummary?: string | null;
};

export async function submitAssessment(req: CallableRequest<SubmitAssessmentInput>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = (req.data?.clinicId ?? "").trim();
  const packId = (req.data?.packId ?? "").trim();
  const regionKey = (req.data?.regionKey ?? "").trim();

  const patientId = (req.data?.patientId ?? "").trim() || null;
  const appointmentId = (req.data?.appointmentId ?? "").trim() || null;

  const answers = req.data?.answers ?? null;

  const consentGiven = req.data?.consentGiven === true;
  const triageStatus = (req.data?.triageStatus ?? null) as "green" | "amber" | "red" | null;
  const clinicianSummary = (req.data?.clinicianSummary ?? "").trim() || null;

  if (!clinicId || !packId || !regionKey) {
    throw new HttpsError("invalid-argument", "clinicId, packId, regionKey are required.");
  }
  if (!answers || typeof answers !== "object" || Array.isArray(answers)) {
    throw new HttpsError("invalid-argument", "answers (object) is required.");
  }
  if (consentGiven !== true) {
    throw new HttpsError("failed-precondition", "Consent must be true to submit.");
  }

  const db = admin.firestore();
  const uid = req.auth.uid;

  await requireActiveMemberWithPerm(db, clinicId, uid, "clinical.write");

  const packRef = db.collection("clinics").doc(clinicId).collection("assessmentPacks").doc(packId);
  const packSnap = await packRef.get();
  if (!packSnap.exists) throw new HttpsError("not-found", "assessmentPack not found.");

  const now = admin.firestore.FieldValue.serverTimestamp();
  const ref = db.collection("clinics").doc(clinicId).collection("assessments").doc();

  await ref.set({
    schemaVersion: schemaVersion("assessment"),

    clinicId,
    packId,
    regionKey,

    patientId,
    appointmentId,

    consentGiven: true,
    triageStatus: triageStatus ?? null,

    answers,
    clinicianSummary,

    status: "finalized",
    submittedAt: now,
    finalizedAt: now,

    pdf: {
      status: "queued",
      storagePath: null,
      url: null,
      updatedAt: now,
    },

    createdAt: now,
    updatedAt: now,
    createdByUid: uid,
    updatedByUid: uid,
  });

  await writeAuditEvent(db, clinicId, {
    type: "assessment.submitted",
    actorUid: uid,
    patientId: patientId ?? undefined,
    metadata: {
      packId,
      regionKey,
      appointmentId,
      assessmentId: ref.id,
      triageStatus,
    },
  });

  return { success: true, assessmentId: ref.id };
}
