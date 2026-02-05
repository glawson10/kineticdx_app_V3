// functions/src/clinic/notes/updateNote.ts
import * as admin from "firebase-admin";
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";

import { requireAuth } from "../utils";
import { requireClinicPermission } from "../../clinic/permissions";
import { UpdateNoteInput } from "./types";

export async function updateNote(req: CallableRequest<UpdateNoteInput>) {
  const uid = requireAuth(req.auth);

  const { clinicId, patientId, episodeId, noteId, soap, reason } = req.data;

  if (!clinicId || !patientId || !episodeId || !noteId || !soap) {
    throw new HttpsError("invalid-argument", "Missing required fields");
  }

  const db = admin.firestore();

  // ✅ Permission: keep it simple + consistent with your PermissionMap
  // If you later add notes.update.any / notes.update.own, we can tighten this.
  await requireClinicPermission(db, clinicId, uid, "notes.write");

  const noteRef = db
    .collection("clinics")
    .doc(clinicId)
    .collection("patients")
    .doc(patientId)
    .collection("episodes")
    .doc(episodeId)
    .collection("notes")
    .doc(noteId);

  const snap = await noteRef.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Note not found");
  }

  const note = snap.data() as any;
  const isAuthor = note?.clinicianId === uid;

  // ✅ Minimal safety: only author can amend (with notes.write).
  // If you want managers to amend any note, add a permission like notes.update.any
  // and we’ll expand the logic.
  if (!isAuthor) {
    throw new HttpsError(
      "permission-denied",
      "Only the note author can amend this note"
    );
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  const amendmentRef = noteRef.collection("amendments").doc();

  const batch = db.batch();

  batch.update(noteRef, {
    soap,
    amendmentCount: admin.firestore.FieldValue.increment(1),
    lastAmendedAt: now,
    lastAmendedByUid: uid,
    updatedAt: now,
  });

  batch.set(amendmentRef, {
    amendedAt: now,
    amendedByUid: uid,
    amendedByRole: "clinician",
    reason: reason ?? null,
  });

  await batch.commit();

  return { success: true };
}
