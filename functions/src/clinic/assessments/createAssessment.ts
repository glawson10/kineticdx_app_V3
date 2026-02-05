import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { requireActiveMemberWithPerm } from "../authz";
import { schemaVersion } from "../../schema/schemaVersions";
import { writeAuditEvent } from "../audit/audit";
import { assessmentPackRef, assessmentRef } from "../paths";
import { AssessmentDoc } from "./types";

type Input = {
  clinicId: string;
  packId: string;

  region: string;

  patientId?: string;
  episodeId?: string;
  appointmentId?: string;

  consentGiven?: boolean;
  answers?: Record<string, any>;
};

export async function createAssessment(req: CallableRequest<Input>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = (req.data?.clinicId ?? "").trim();
  const packId = (req.data?.packId ?? "").trim();
  const region = (req.data?.region ?? "").trim();

  const patientId = (req.data?.patientId ?? "").trim() || null;
  const episodeId = (req.data?.episodeId ?? "").trim() || null;
  const appointmentId = (req.data?.appointmentId ?? "").trim() || null;

  const consentGiven = req.data?.consentGiven === true;
  const answers = req.data?.answers ?? {};

  if (!clinicId || !packId || !region) {
    throw new HttpsError("invalid-argument", "clinicId, packId, region required.");
  }
  if (typeof answers !== "object" || answers == null || Array.isArray(answers)) {
    throw new HttpsError("invalid-argument", "answers must be an object.");
  }

  const db = admin.firestore();
  const uid = req.auth.uid;

  await requireActiveMemberWithPerm(db, clinicId, uid, "clinical.write");

  const packSnap = await assessmentPackRef(db, clinicId, packId).get();
  if (!packSnap.exists) throw new HttpsError("not-found", "Assessment pack not found.");

  const now = admin.firestore.FieldValue.serverTimestamp();
  const id = db.collection("_").doc().id;
  const ref = assessmentRef(db, clinicId, id);

  const doc: AssessmentDoc = {
    schemaVersion: schemaVersion("assessment"),

    clinicId,
    packId,

    patientId,
    episodeId,
    appointmentId,

    region,
    consentGiven,

    answers,

    triageStatus: null,

    pdf: {
      status: "none",
      storagePath: null,
      url: null,
      updatedAt: now,
    },

    status: "draft",

    createdAt: now,
    updatedAt: now,

    createdByUid: uid,
    updatedByUid: uid,

    submittedAt: null,
    finalizedAt: null,
  };

  await ref.set(doc);

  await writeAuditEvent(db, clinicId, {
    type: "assessment.created",
    actorUid: uid,
    patientId: patientId ?? undefined,
    episodeId: episodeId ?? undefined,
    metadata: { assessmentId: id, packId, region, appointmentId },
  });

  return { success: true, assessmentId: id };
}
