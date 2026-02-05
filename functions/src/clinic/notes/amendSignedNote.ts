import * as admin from "firebase-admin";
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import { writeAuditEvent } from "../audit/audit";
import { requireNotesWriteContext, requireNoteExists } from "./_helpers";

type Input = {
  clinicId: string;
  patientId: string;
  episodeId: string;
  noteId: string;

  soap: Record<string, any>;
  reason: string;

  summary?: string | null;
  fieldPaths?: string[];
};

export async function amendSignedNote(req: CallableRequest<Input>) {
  const { db, clinicId, uid, canWriteAny } = await requireNotesWriteContext(req);

  const patientId = (req.data?.patientId ?? "").trim();
  const episodeId = (req.data?.episodeId ?? "").trim();
  const noteId = (req.data?.noteId ?? "").trim();

  const soap = req.data?.soap ?? null;
  const reason = (req.data?.reason ?? "").trim();
  const summary = req.data?.summary ?? null;
  const fieldPaths = Array.isArray(req.data?.fieldPaths) ? req.data!.fieldPaths! : [];

  if (!patientId || !episodeId || !noteId) {
    throw new HttpsError("invalid-argument", "patientId, episodeId, noteId required.");
  }
  if (!soap || typeof soap !== "object" || Array.isArray(soap)) {
    throw new HttpsError("invalid-argument", "soap object is required.");
  }
  if (!reason) {
    throw new HttpsError("invalid-argument", "reason is required.");
  }

  const { noteRef, note } = await requireNoteExists({ db, clinicId, patientId, episodeId, noteId });

  if (note.status !== "signed") {
    throw new HttpsError("failed-precondition", "Only signed notes can be amended.");
  }

  const isAuthor = note.authorUid === uid;
  if (!isAuthor && !canWriteAny) {
    throw new HttpsError("permission-denied", "Only the author or a manager can amend this note.");
  }

  const now = admin.firestore.FieldValue.serverTimestamp();

  await db.runTransaction(async (tx) => {
    const fresh = await tx.get(noteRef);
    if (!fresh.exists) throw new HttpsError("not-found", "Note not found.");

    const data = fresh.data() as any;
    const nextVersion = (typeof data.version === "number" ? data.version : 1) + 1;

    // Append-only amendment record
    const amendRef = noteRef.collection("amendments").doc();
    tx.set(amendRef, {
      schemaVersion: 1,
      noteId,
      actorUid: uid,
      actorRole: canWriteAny && !isAuthor ? "manager" : "clinician",
      reason,
      summary,
      fieldPaths,
      patch: soap,
      createdAt: now,
      newVersion: nextVersion,
    });

    // Update current snapshot
    tx.update(noteRef, {
      current: soap,
      version: nextVersion,
      lastAmendedAt: now,
      lastAmendedByUid: uid,
      amendmentCount: admin.firestore.FieldValue.increment(1),
      updatedAt: now,
    });

    // touch episode activity
    const epRef = noteRef.parent.parent;
    if (epRef) {
      tx.set(
        epRef,
        { lastActivityAt: now, updatedAt: now },
        { merge: true }
      );
    }
  });

  await writeAuditEvent(db, clinicId, {
    type: "note.amended",
    actorUid: uid,
    patientId,
    episodeId,
    noteId,
    metadata: {
      amendedBy: isAuthor ? "author" : "managerOverride",
      summary,
      fieldPaths,
    },
  });

  return { success: true };
}
