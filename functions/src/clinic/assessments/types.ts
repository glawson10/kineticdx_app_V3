export type AssessmentPackDoc = {
  schemaVersion: number;

  name: string;
  description?: string | null;

  // region -> question defs (you already have this concept)
  // Keep it flexible (the UI registry can evolve)
  regions: Record<
    string,
    {
      label?: string;
      questions: Array<{
        id: string;
        label: string;
        section: string;
        kind: string; // yesno | single | multi | slider | text etc
        options?: string[];
      }>;
    }
  >;

  active: boolean;

  createdAt: any;
  updatedAt: any;
  createdByUid: string;
  updatedByUid: string;
};

export type AssessmentStatus = "draft" | "submitted" | "finalized";

export type AssessmentDoc = {
  schemaVersion: number;

  clinicId: string;
  packId: string;

  patientId?: string | null;     // optional link (if you attach later)
  episodeId?: string | null;     // optional link (handoff later)
  appointmentId?: string | null; // optional link

  region: string;
  consentGiven: boolean;

  answers: Record<string, any>;

  // Keep Phase 3 output minimal for now (no differentials in note per your choice)
  triageStatus?: "green" | "amber" | "red" | null;

  // PDF output (generated later)
  pdf: {
    status: "none" | "queued" | "ready" | "error";
    storagePath?: string | null;
    url?: string | null; // if you store signed URL later
    updatedAt?: any;
  };

  status: AssessmentStatus;

  createdAt: any;
  updatedAt: any;

  createdByUid: string;
  updatedByUid: string;

  submittedAt?: any | null;
  finalizedAt?: any | null;
};
