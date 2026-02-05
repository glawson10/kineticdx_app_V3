// functions/src/notes/soapContract.ts

export type NoteTemplateType = "standard" | "custom";
export type NoteEncounterType = "initial" | "followup";
export type NoteStatus = "draft" | "final";

export type SoapPayload = {
  // Required stable root keys (your Dart model can be richer, but must map to these)
  screening?: Record<string, any>;
  subjective?: Record<string, any>;
  objective?: Record<string, any>;
  analysis?: Record<string, any>;
  plan?: Record<string, any>;

  // Optional: allow structured extras without breaking schema
  extras?: Record<string, any>;
};

export type CreateNotePayload = {
  template: NoteTemplateType;      // standard/custom
  encounterType: NoteEncounterType; // initial/followup
  soap: SoapPayload;
};
