import * as admin from "firebase-admin";
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import { writeAuditEvent } from "../audit/audit";
import { requireNotesWriteContext, requireNoteExists } from "./_helpers";

type Input = {
  clinicId: string;
  patientId: string;
  episodeId: string;
  noteId: string;
};

export async function signNote(req: CallableRequest<Input>) {
  const { db, clinicId, uid, canWriteAny } = await requireNotesWriteContext(req);

  const patientId = (req.data?.patientId ?? "").trim();
  const episodeId = (req.data?.episodeId ?? "").trim();
  const noteId = (req.data?.noteId ?? "").trim();

  if (!patientId || !episodeId || !noteId) {
    throw new HttpsError("invalid-argument", "patientId, episodeId, noteId required.");
  }

  const { noteRef, note } = await requireNoteExists({ db, clinicId, patientId, episodeId, noteId });

  if (note.status !== "draft") {
    throw new HttpsError("failed-precondition", "Note is not a draft.");
  }

  const isAuthor = note.authorUid === uid;

  // signing: author OR manager override
  if (!isAuthor && !canWriteAny) {
    throw new HttpsError("permission-denied", "Only author or manager can sign this note.");
  }

  const now = admin.firestore.FieldValue.serverTimestamp();

  await noteRef.update({
    status: "signed",
    signedAt: now,
    signedByUid: uid,
    updatedAt: now,
  });

  // touch episode activity
  const epRef = noteRef.parent.parent; // episodes/{episodeId}
  if (epRef) {
    await epRef.update({
      lastActivityAt: now,
      updatedAt: now,
    });
  }

  await writeAuditEvent(db, clinicId, {
    type: "note.signed",
    actorUid: uid,
    patientId,
    episodeId,
    noteId,
    metadata: { signedBy: isAuthor ? "author" : "managerOverride" },
  });

  return { success: true };
}
