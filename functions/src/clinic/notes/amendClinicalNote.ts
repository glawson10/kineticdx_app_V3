import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { requireCanAmendNote } from "../authz";
import { noteRef } from "../paths";

type AmendClinicalNoteInput = {
  clinicId: string;
  patientId: string;
  episodeId: string;
  noteId: string;
  soap: Record<string, any>;
  reason?: string;
};

export async function amendClinicalNote(
  req: CallableRequest<AmendClinicalNoteInput>
) {
  if (!req.auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }

  const { clinicId, patientId, episodeId, noteId, soap, reason } = req.data ?? {};

  if (!clinicId || !patientId || !episodeId || !noteId) {
    throw new HttpsError("invalid-argument", "Missing required identifiers.");
  }
  if (!soap || typeof soap !== "object" || Array.isArray(soap)) {
    throw new HttpsError("invalid-argument", "soap object is required.");
  }

  const db = admin.firestore();
  const uid = req.auth.uid;

  const ref = noteRef(db, clinicId, patientId, episodeId, noteId);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      throw new HttpsError("not-found", "Note not found.");
    }

    const data = snap.data() as any;
    const authorUid = data.authorUid ?? data.clinicianId;

    const scope = await requireCanAmendNote(
      db,
      clinicId,
      uid,
      authorUid
    );

    const now = admin.firestore.FieldValue.serverTimestamp();
    const nextVersion = (data.version ?? 1) + 1;

    tx.set(ref.collection("amendments").doc(), {
      schemaVersion: 1,
      noteId,
      actorUid: uid,
      scope,
      reason: reason ?? null,
      patch: soap,
      createdAt: now,
      newVersion: nextVersion,
    });

    tx.update(ref, {
      current: soap,
      version: nextVersion,
      updatedAt: now,
      lastAmendedAt: now,
      lastAmendedByUid: uid,
      amendmentCount: admin.firestore.FieldValue.increment(1),
    });
  });

  return { success: true, noteId };
}
