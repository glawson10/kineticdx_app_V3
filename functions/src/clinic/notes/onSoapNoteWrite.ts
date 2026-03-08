import { onDocumentWritten } from "firebase-functions/v2/firestore";

/** Stub: SOAP note write trigger. Replace with real implementation. */
export const onSoapNoteWrite = onDocumentWritten(
  {
    document: "clinics/{clinicId}/patients/{patientId}/episodes/{episodeId}/soapNotes/{noteId}",
    region: "europe-west3",
  },
  async () => {}
);
