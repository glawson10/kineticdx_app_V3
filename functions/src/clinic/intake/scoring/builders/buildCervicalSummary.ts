export interface CervicalSummary {
  region: "cervical";
  triage: {
    level: "red" | "amber" | "green";
    reasons: string[];
  };
  topDifferentials: {
    code: string;
    label: string;
    score: number;
    rationale: string[];
  }[];
  objectiveTests: string[];
  narrative: string;
  tables: {
    safety: { question: string; answer: string }[];
    context: { question: string; answer: string }[];
    symptoms: { question: string; answer: string }[];
    function: { question: string; answer: string }[];
    other: { question: string; answer: string }[];
  };
}

export function buildCervicalSummary(
  raw: any,
  answers: Record<string, any>
): CervicalSummary {
  return {
    region: "cervical",

    triage: {
      level: raw.triageLevel,
      reasons: raw.triageReasons ?? [],
    },

    topDifferentials: (raw.differentials ?? [])
      .sort((a: any, b: any) => b.score - a.score)
      .slice(0, 3)
      .map((d: any) => ({
        code: d.code,
        label: d.label,
        score: d.score,
        rationale: d.triggers ?? [],
      })),

    objectiveTests: raw.recommendedTests ?? [],

    narrative:
      raw.summaryNarrative ??
      "Patient reports neck symptoms consistent with the above findings.",

    tables: {
      safety: raw.tables?.safety ?? [],
      context: raw.tables?.context ?? [],
      symptoms: raw.tables?.symptoms ?? [],
      function: raw.tables?.function ?? [],
      other: raw.tables?.other ?? [],
    },
  };
}
