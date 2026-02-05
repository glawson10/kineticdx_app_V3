export type NoteType = "initial" | "followup" | "custom";

export interface CreateNoteInput {
  clinicId: string;
  patientId: string;
  episodeId: string;
  noteType: NoteType;

  appointmentId?: string;
  assessmentId?: string;
  previousNoteId?: string;
}

export interface UpdateNoteInput {
  clinicId: string;
  patientId: string;
  episodeId: string;
  noteId: string;

  soap: Record<string, any>;
  reason?: string;
}
