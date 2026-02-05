export interface WristSummary {
  region: "wrist";
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

export function buildWristSummary(raw: any, _answers: Record<string, any>): WristSummary {
  const triage = (raw?.triage ?? "green") as "red" | "amber" | "green";
  const reasons: string[] = Array.isArray(raw?.redFlagNotes) ? raw.redFlagNotes : [];

  const top = Array.isArray(raw?.topDifferentials) ? raw.topDifferentials : [];
  const top3 = top.slice(0, 3).map((d: any) => ({
    code: d?.key ?? d?.name ?? "unknown",
    label: d?.name ?? "Unknown",
    score: Number(d?.score ?? 0),
    rationale: Array.isArray(d?.rationale) ? d.rationale : [],
  }));

  const tests = top
    .flatMap((d: any) => (Array.isArray(d?.objectiveTests) ? d.objectiveTests : []))
    .filter((x: any) => typeof x === "string" && x.trim().length > 0);

  return {
    region: "wrist",
    triage: { level: triage, reasons },
    topDifferentials: top3,
    objectiveTests: Array.from(new Set(tests)),
    narrative:
      "Wrist presentation scored using region-specific rules. Review top differentials, triage, and suggested objective tests.",
    tables: { safety: [], context: [], symptoms: [], function: [], other: [] },
  };
}
