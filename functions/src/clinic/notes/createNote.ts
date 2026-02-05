// functions/src/clinic/notes/createNote.ts
import * as admin from "firebase-admin";
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";

import { requireAuth } from "../utils";
import { requireClinicPermission } from "../../clinic/permissions";
import { CreateNoteInput } from "./types";

export async function createNote(req: CallableRequest<CreateNoteInput>) {
  const uid = requireAuth(req.auth);

  const {
    clinicId,
    patientId,
    episodeId,
    noteType,
    appointmentId,
    assessmentId,
    previousNoteId,
  } = req.data;

  if (!clinicId || !patientId || !episodeId || !noteType) {
    throw new HttpsError("invalid-argument", "Missing required fields");
  }

  const db = admin.firestore();

  // ✅ Permission: your permissions.ts defines notes.read / notes.write (NOT notes.create)
  await requireClinicPermission(db, clinicId, uid, "notes.write");

  const episodeRef = db
    .collection("clinics")
    .doc(clinicId)
    .collection("patients")
    .doc(patientId)
    .collection("episodes")
    .doc(episodeId);

  const episodeSnap = await episodeRef.get();
  if (!episodeSnap.exists) {
    throw new HttpsError("not-found", "Episode not found");
  }

  // Follow-up requires previous note
  if (noteType === "followup" && !previousNoteId) {
    throw new HttpsError(
      "failed-precondition",
      "Follow-up notes require previousNoteId"
    );
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  const noteRef = episodeRef.collection("notes").doc();

  const batch = db.batch();

  batch.set(noteRef, {
    schemaVersion: 1,
    noteType,
    patientId,
    episodeId,
    appointmentId: appointmentId ?? null,
    assessmentId: assessmentId ?? null,
    previousNoteId: previousNoteId ?? null,
    clinicianId: uid,
    soap: {},
    amendmentCount: 0,
    lastAmendedAt: null,
    lastAmendedByUid: null,
    createdAt: now,
    updatedAt: now,
  });

  batch.update(episodeRef, {
    lastNoteId: noteRef.id,
    lastNoteAt: now,
    noteCount: admin.firestore.FieldValue.increment(1),
  });

  await batch.commit();

  return { noteId: noteRef.id };
}
