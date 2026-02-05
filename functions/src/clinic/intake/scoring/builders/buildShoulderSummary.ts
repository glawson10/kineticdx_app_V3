export interface ShoulderSummary {
  region: "shoulder";
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
 * Your shoulder scorer currently returns:
 * {
 *   region: "Shoulder",
 *   triage,
 *   redFlagNotes,
 *   topDifferentials: [{ name, score }],
 *   clinicalToDo,
 *   detailedTop: [{ name, score, rationale, objectiveTests }]
 * }
 *
 * We normalize that into the unified structure used in clinician UI.
 */
export function buildShoulderSummary(
  raw: any,
  _answers: Record<string, any>
): ShoulderSummary {
  const triage = (raw?.triage ?? "green") as "red" | "amber" | "green";
  const reasons: string[] = Array.isArray(raw?.redFlagNotes)
    ? raw.redFlagNotes
    : [];

  const detailedTop = Array.isArray(raw?.detailedTop) ? raw.detailedTop : [];

  const top3 = detailedTop.slice(0, 3).map((d: any) => ({
    code: d?.name ?? "unknown",
    label: d?.name ?? "Unknown",
    score: Number(d?.score ?? 0),
    rationale: Array.isArray(d?.rationale) ? d.rationale : [],
  }));

  const tests = detailedTop
    .flatMap((d: any) => (Array.isArray(d?.objectiveTests) ? d.objectiveTests : []))
    .filter((x: any) => typeof x === "string" && x.trim().length > 0);

  return {
    region: "shoulder",
    triage: { level: triage, reasons },

    topDifferentials: top3,

    objectiveTests: Array.from(new Set(tests)),

    narrative:
      raw?.clinicalToDo?.primary ??
      "Patient reports shoulder symptoms consistent with the above findings.",

    // Shoulder scorer doesn’t currently output tables.
    // We keep empty groups for UI consistency.
    tables: {
      safety: [],
      context: [],
      symptoms: [],
      function: [],
      other: [],
    },
  };
}
