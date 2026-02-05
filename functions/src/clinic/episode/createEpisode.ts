import * as admin from "firebase-admin";
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import { requireActiveMemberWithPerm } from "../authz";
import { writeAuditEvent } from "../audit/audit";

type Input = {
  clinicId: string;
  patientId: string;
  title: string;
  primaryComplaint?: string;
  onsetDate?: string;
  referralSource?: string;
  assignedPractitionerId?: string;
  tags?: string[];
};

export async function createEpisode(req: CallableRequest<Input>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const uid = req.auth.uid;

  const clinicId = (req.data?.clinicId ?? "").trim();
  const patientId = (req.data?.patientId ?? "").trim();
  const title = (req.data?.title ?? "").trim();

  if (!clinicId || !patientId || !title) {
    throw new HttpsError("invalid-argument", "clinicId, patientId, and title are required.");
  }

  const db = admin.firestore();

  // ✅ Canonical permission check
  await requireActiveMemberWithPerm(db, clinicId, uid, "clinical.write");

  const patientRef = db.doc(`clinics/${clinicId}/patients/${patientId}`);
  const patientSnap = await patientRef.get();
  if (!patientSnap.exists) throw new HttpsError("not-found", "Patient not found.");

  const now = admin.firestore.FieldValue.serverTimestamp();

  const episodeRef = patientRef.collection("episodes").doc();
  const episodeId = episodeRef.id;

  const tags = Array.isArray(req.data?.tags) ? req.data!.tags!.filter(Boolean) : [];

  await episodeRef.set({
    status: "open",
    title,
    primaryComplaint: req.data?.primaryComplaint ?? null,
    onsetDate: req.data?.onsetDate ?? null,
    referralSource: req.data?.referralSource ?? null,
    assignedPractitionerId: req.data?.assignedPractitionerId ?? null,
    tags,

    openedAt: now,
    closedAt: null,
    closedReason: null,
    lastActivityAt: now,

    createdByUid: uid,
    createdAt: now,
    updatedAt: now,
  });

  await writeAuditEvent(db, clinicId, {
    type: "episode.created",
    actorUid: uid,
    metadata: { patientId, episodeId, title },
  });

  return { ok: true, episodeId };
}
