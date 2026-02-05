import * as admin from "firebase-admin";
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import { requireActiveMemberWithPerm } from "../authz";
import { writeAuditEvent } from "../audit/audit";

type Input = {
  clinicId: string;
  patientId: string;
  episodeId: string;
  title?: string;
  primaryComplaint?: string | null;
  onsetDate?: string | null;
  referralSource?: string | null;
  assignedPractitionerId?: string | null;
  tags?: string[];
};

export async function updateEpisode(req: CallableRequest<Input>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = (req.data?.clinicId ?? "").trim();
  const patientId = (req.data?.patientId ?? "").trim();
  const episodeId = (req.data?.episodeId ?? "").trim();

  if (!clinicId || !patientId || !episodeId) {
    throw new HttpsError("invalid-argument", "clinicId, patientId, episodeId required.");
  }

  const db = admin.firestore();
  const uid = req.auth.uid;

  await requireActiveMemberWithPerm(db, clinicId, uid, "clinical.write");

  const episodeRef = db.doc(
    `clinics/${clinicId}/patients/${patientId}/episodes/${episodeId}`
  );

  const snap = await episodeRef.get();
  if (!snap.exists) throw new HttpsError("not-found", "Episode not found.");

  const existing = snap.data() as any;
  if (existing?.status !== "open") {
    throw new HttpsError("failed-precondition", "Cannot edit a closed episode.");
  }

  const now = admin.firestore.FieldValue.serverTimestamp();

  const update: Record<string, any> = {
    updatedAt: now,
    lastActivityAt: now,
  };

  if (req.data?.title !== undefined) update.title = req.data.title;
  if (req.data?.primaryComplaint !== undefined)
    update.primaryComplaint = req.data.primaryComplaint;
  if (req.data?.onsetDate !== undefined) update.onsetDate = req.data.onsetDate;
  if (req.data?.referralSource !== undefined)
    update.referralSource = req.data.referralSource;
  if (req.data?.assignedPractitionerId !== undefined)
    update.assignedPractitionerId = req.data.assignedPractitionerId;
  if (req.data?.tags !== undefined)
    update.tags = Array.isArray(req.data.tags) ? req.data.tags : [];

  await episodeRef.update(update);

  await writeAuditEvent(db, clinicId, {
    type: "episode.updated",
    actorUid: uid,
    metadata: { patientId, episodeId, fields: Object.keys(update) },
  });

  return { ok: true };
}
