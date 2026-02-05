// functions/src/clinic/seedAssessmentPacks.ts

export type SeedDoc<T> = {
  id: string;
  data: T;
};

export function seedDefaultAssessmentPacks(): SeedDoc<Record<string, any>>[] {
  return [
    {
      id: "standard_msk_v1",
      data: {
        schemaVersion: 1,
        active: true,

        name: "Standard MSK Intake (V1)",
        description: "Default preassessment pack mapped from region_question_registry.dart",

        questionSets: {
          cervical:  { questionSetId: "cervical.v1",  enabled: true, requiresSide: false },
          thoracic:  { questionSetId: "thoracic.v1",  enabled: true, requiresSide: false },
          lumbar:    { questionSetId: "lumbar.v1",    enabled: true, requiresSide: false },

          shoulder:  { questionSetId: "shoulder.v1",  enabled: true, requiresSide: true },
          elbow:     { questionSetId: "elbow.v1",     enabled: true, requiresSide: true },
          wrist:     { questionSetId: "wrist.v1",     enabled: true, requiresSide: true },
          hip:       { questionSetId: "hip.v1",       enabled: true, requiresSide: true },
          knee:      { questionSetId: "knee.v1",      enabled: true, requiresSide: true },
          ankle:     { questionSetId: "ankle.v1",     enabled: true, requiresSide: true },
        },

        defaults: {
          requireConsent: true,
          allowAnonymousSubmission: true,
          lockOnSubmit: true,
        },

        pdf: {
          enabled: true,
          includeTop3Differentials: true,
          includeObjectiveRecommendations: true,
        },

        // replaced with serverTimestamp in createClinic
        createdAt: "SERVER_TIMESTAMP",
        updatedAt: "SERVER_TIMESTAMP",
      },
    },
  ];
}
