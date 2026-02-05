import * as admin from "firebase-admin";
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import { writeAuditEvent } from "../audit/audit";
import { requireNotesWriteContext, requireEpisodeExists } from "./_helpers";

type CreateClinicalNoteInput = {
  clinicId: string;
  patientId: string;
  episodeId: string;

  // canonical snapshot payload (SOAP object)
  soap: Record<string, any>;

  encounterType: "initial" | "followup";
  template: "standard" | "custom";

  appointmentId?: string;
  assessmentId?: string;
  previousNoteId?: string; // required for followup
};

export async function createClinicalNote(req: CallableRequest<CreateClinicalNoteInput>) {
  const { db, clinicId, uid } = await requireNotesWriteContext(req);

  const patientId = (req.data?.patientId ?? "").trim();
  const episodeId = (req.data?.episodeId ?? "").trim();

  const soap = req.data?.soap ?? null;
  const encounterType = req.data?.encounterType;
  const template = req.data?.template;

  const appointmentId = (req.data?.appointmentId ?? "").trim() || null;
  const assessmentId = (req.data?.assessmentId ?? "").trim() || null;
  const previousNoteId = (req.data?.previousNoteId ?? "").trim() || null;

  if (!patientId || !episodeId) {
    throw new HttpsError("invalid-argument", "patientId, episodeId required.");
  }
  if (!soap || typeof soap !== "object" || Array.isArray(soap)) {
    throw new HttpsError("invalid-argument", "soap object is required.");
  }
  if (encounterType !== "initial" && encounterType !== "followup") {
    throw new HttpsError("invalid-argument", "encounterType must be initial|followup.");
  }
  if (template !== "standard" && template !== "custom") {
    throw new HttpsError("invalid-argument", "template must be standard|custom.");
  }
  if (encounterType === "followup" && !previousNoteId) {
    throw new HttpsError("failed-precondition", "Follow-up requires previousNoteId.");
  }

  // ensure episode exists
  const { episodeRef } = await requireEpisodeExists({ db, clinicId, patientId, episodeId });

  const now = admin.firestore.FieldValue.serverTimestamp();
  const noteRef = episodeRef.collection("notes").doc();

  await db.runTransaction(async (tx) => {
    tx.set(noteRef, {
      schemaVersion: 1,

      clinicId,
      patientId,
      episodeId,

      authorUid: uid,

      status: "draft", // draft -> signed
      encounterType,
      template,

      appointmentId,
      assessmentId,
      previousNoteId,

      version: 1,
      current: soap,

      amendmentCount: 0,
      lastAmendedAt: null,
      lastAmendedByUid: null,

      signedAt: null,
      signedByUid: null,

      createdAt: now,
      updatedAt: now,
    });

    tx.set(
      episodeRef,
      {
        lastNoteId: noteRef.id,
        lastNoteAt: now,
        noteCount: admin.firestore.FieldValue.increment(1),
        lastActivityAt: now,
        updatedAt: now,
      },
      { merge: true }
    );
  });

  await writeAuditEvent(db, clinicId, {
    type: "note.created",
    actorUid: uid,
    patientId,
    episodeId,
    noteId: noteRef.id,
    metadata: { encounterType, template, appointmentId, assessmentId, previousNoteId },
  });

  return { success: true, noteId: noteRef.id };
}
