// functions/src/clinic/intake/scoring/types.ts

export type AnswerValue =
  | { t: "bool"; v: boolean }
  | { t: "int"; v: number }
  | { t: "num"; v: number }
  | { t: "text"; v: string }
  | { t: "single"; v: string } // optionId
  | { t: "multi"; v: string[] } // optionIds
  | { t: "date"; v: string } // yyyy-mm-dd
  | { t: "map"; v: Record<string, any> }; // escape hatch (rare)
