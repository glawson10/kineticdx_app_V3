import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { hasPerm } from "../authz";
import { episodeRef, noteDraftRef, noteRef } from "../paths";

type FinalizeNoteDraftInput = {
  clinicId: string;
  patientId: string;
  episodeId: string;
  draftId: string;

  // Optional: reason shown in audit/amendment log
  reason?: string;
};

export async function finalizeNoteDraft(req: CallableRequest<FinalizeNoteDraftInput>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = (req.data?.clinicId ?? "").trim();
  const patientId = (req.data?.patientId ?? "").trim();
  const episodeId = (req.data?.episodeId ?? "").trim();
  const draftId = (req.data?.draftId ?? "").trim();
  const reason = (req.data?.reason ?? "").trim();

  if (!clinicId || !patientId || !episodeId || !draftId) {
    throw new HttpsError("invalid-argument", "clinicId, patientId, episodeId, draftId required.");
  }

  const db = admin.firestore();
  const uid = req.auth.uid;

  const canWriteOwn = await hasPerm(db, clinicId, uid, "notes.write.own");
  const canWriteAny = await hasPerm(db, clinicId, uid, "notes.write.any");
  if (!canWriteOwn && !canWriteAny) {
    throw new HttpsError("permission-denied", "Missing permission: notes.write.own or notes.write.any");
  }

  const epRef = episodeRef(db, clinicId, patientId, episodeId);
  const drRef = noteDraftRef(db, clinicId, patientId, episodeId, draftId);

  await db.runTransaction(async (tx) => {
    const epSnap = await tx.get(epRef);
    if (!epSnap.exists) throw new HttpsError("not-found", "Episode not found.");

    const drSnap = await tx.get(drRef);
    if (!drSnap.exists) throw new HttpsError("not-found", "Draft not found.");

    const draft = drSnap.data() as any;
    if (draft.status !== "draft") {
      throw new HttpsError("failed-precondition", "Draft already finalized or not editable.");
    }

    const authorUid = (draft.authorUid ?? "").toString();
    const isAuthor = authorUid === uid;

    // ✅ Correct override rule:
    // - author can finalize if notes.write.own OR notes.write.any
    // - non-author can finalize ONLY if notes.write.any
    if (!isAuthor && !canWriteAny) {
      throw new HttpsError("permission-denied", "You can only finalize your own draft.");
    }

    const now = admin.firestore.FieldValue.serverTimestamp();

    // If draft already linked to a note, finalize becomes an amendment.
    const existingNoteId = (draft.noteId as string | null) ?? null;

    let canonicalNoteId: string;

    if (!existingNoteId) {
      const newNoteDoc = epRef.collection("notes").doc();
      canonicalNoteId = newNoteDoc.id;

      tx.set(newNoteDoc, {
        schemaVersion: 1,

        clinicId,
        patientId,
        episodeId,

        noteType: draft.noteType ?? "custom",
        appointmentId: draft.appointmentId ?? null,
        assessmentId: draft.assessmentId ?? null,
        previousNoteId: draft.previousNoteId ?? null,

        authorUid: authorUid,
        status: "final", // final | voided | archived
        version: 1,
        current: draft.current ?? {},

        createdAt: now,
        updatedAt: now,
        lastAmendedAt: null,
        lastAmendedByUid: null,
        amendmentCount: 0,
      });

      tx.update(epRef, {
        lastNoteId: canonicalNoteId,
        lastNoteAt: now,
        noteCount: admin.firestore.FieldValue.increment(1),
      });
    } else {
      canonicalNoteId = existingNoteId;

      const nRef = noteRef(db, clinicId, patientId, episodeId, canonicalNoteId);
      const nSnap = await tx.get(nRef);
      if (!nSnap.exists) throw new HttpsError("not-found", "Linked note not found.");

      const noteData = nSnap.data() as any;
      const nextVersion = (typeof noteData.version === "number" ? noteData.version : 1) + 1;

      const amendRef = nRef.collection("amendments").doc();
      tx.set(amendRef, {
        schemaVersion: 1,
        noteId: canonicalNoteId,
        actorUid: uid,
        reason: reason || null,
        patch: draft.current ?? {},
        createdAt: now,
        newVersion: nextVersion,
        source: "draftFinalize",
      });

      tx.update(nRef, {
        current: draft.current ?? {},
        version: nextVersion,
        updatedAt: now,
        lastAmendedAt: now,
        lastAmendedByUid: uid,
        amendmentCount: admin.firestore.FieldValue.increment(1),
      });
    }

    tx.update(drRef, {
      status: "finalized",
      finalizedAt: now,
      finalizedByUid: uid,
      noteId: canonicalNoteId,
      updatedAt: now,
    });
  });

  const drSnap = await drRef.get();
  const noteId = (drSnap.data() as any)?.noteId;

  return { success: true, draftId, noteId };
}
