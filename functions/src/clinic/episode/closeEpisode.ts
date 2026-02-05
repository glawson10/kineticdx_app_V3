import * as admin from "firebase-admin";
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import { requireActiveMemberWithPerm } from "../authz";
import { writeAuditEvent } from "../audit/audit";

type Input = {
  clinicId: string;
  patientId: string;
  episodeId: string;
  closedReason?: string;
};

export async function closeEpisode(req: CallableRequest<Input>) {
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
    throw new HttpsError("failed-precondition", "Episode already closed.");
  }

  const now = admin.firestore.FieldValue.serverTimestamp();

  await episodeRef.update({
    status: "closed",
    closedAt: now,
    closedReason: (req.data?.closedReason ?? null) as any,
    updatedAt: now,
    lastActivityAt: now,
  });

  await writeAuditEvent(db, clinicId, {
    type: "episode.closed",
    actorUid: uid,
    metadata: { patientId, episodeId, closedReason: req.data?.closedReason ?? null },
  });

  return { ok: true };
}
