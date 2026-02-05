export interface HipSummary {
  region: "hip";
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

/**
 * Convert raw hip scorer output into clinician-friendly summary.
 * This does not change scoring; it just shapes data for UI.
 */
export function buildHipSummary(
  raw: any,
  answers: Record<string, any>
): HipSummary {
  return {
    region: "hip",

    triage: {
      level: raw.triage ?? raw.triageLevel ?? "green",
      reasons: raw.notes ?? raw.triageReasons ?? [],
    },

    topDifferentials: (raw.ranked ?? raw.differentials ?? [])
      .sort((a: any, b: any) => Number(b.score ?? 0) - Number(a.score ?? 0))
      .slice(0, 3)
      .map((d: any) => ({
        code: d.key ?? d.code ?? "unknown",
        label: d.name ?? d.label ?? "Unknown",
        score: Number(d.score ?? 0),
        rationale: d.why ?? d.triggers ?? [],
      })),

    objectiveTests: raw.recommendedTests ?? raw.tests ?? [],

    narrative:
      raw.summaryNarrative ??
      raw.summary ??
      "Patient reports hip symptoms consistent with the above findings.",

    tables: {
      safety: raw.tables?.safety ?? [],
      context: raw.tables?.context ?? [],
      symptoms: raw.tables?.symptoms ?? [],
      function: raw.tables?.function ?? [],
      other: raw.tables?.other ?? [],
    },
  };
}
