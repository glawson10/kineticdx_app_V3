import { onDocumentWritten } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import { writeAuditEvent } from "../audit/audit";

if (!admin.apps.length) {
  admin.initializeApp();
}

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

export const onClinicalNoteWrite = onDocumentWritten(
  {
    region: "europe-west3",
    document: "clinics/{clinicId}/clinicalNotes/{noteId}",
  },
  async (event) => {
    const { clinicId, noteId } = event.params;
    const afterSnap = event.data?.after;
    const beforeSnap = event.data?.before;

    if (!afterSnap?.exists) return;
    const isCreate = !beforeSnap?.exists;

    const data = afterSnap.data() || {};
    const actorUid =
      safeStr(data["updatedByUid"]) || safeStr(data["createdByUid"]);
    if (!actorUid) return;

    const patientId = safeStr(data["patientId"]);
    const appointmentId = safeStr(data["appointmentId"]);
    const noteType = safeStr(data["type"]);
    const templateId = safeStr(data["templateId"]);

    await writeAuditEvent(admin.firestore(), clinicId, {
      type: isCreate ? "clinicalNote.created" : "clinicalNote.updated",
      actorUid,
      patientId: patientId || undefined,
      noteId,
      appointmentId: appointmentId || undefined,
      metadata: {
        noteType: noteType || undefined,
        templateId: templateId || undefined,
      },
    });
  }
);
