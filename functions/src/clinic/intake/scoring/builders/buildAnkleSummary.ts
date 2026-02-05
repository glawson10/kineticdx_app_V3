import { AnswerValue } from "../types";

/**
 * Raw output shape from processAnkleAssessmentCore / buildSummary() in:
 * functions/src/ankle/processAnkleAssessment.ts
 *
 * We keep this typed loosely so you can evolve scorer output without breaking
 * the intake pipeline.
 */
type RawAnkleResult = {
  region?: string;
  triage: "green" | "amber" | "red";
  redFlagNotes?: string[];
  topDifferentials?: { name: string; score: number }[];
  clinicalToDo?: string[];
  detailedTop?: Array<{
    key: string; // DifferentialKey (e.g. lateral_sprain)
    name: string;
    score: number;
    rationale?: string[];
    objectiveTests?: string[];
  }>;
};

export type TableRow = {
  questionId: string;
  answer: string;
};

export type IntakeSummary = {
  region: string;

  triage: {
    level: "green" | "amber" | "red";
    reasons: string[];
  };

  topDifferentials: Array<{
    code: string;
    label: string;
    score: number;
    rationale: string[];
    objectiveTests: string[];
  }>;

  objectiveTests: string[];

  narrative: string;

  tables: {
    safety: TableRow[];
    context: TableRow[];
    symptoms: TableRow[];
    function: TableRow[];
    other: TableRow[];
  };

  triggeredAnswers: TableRow[];
};

/* ------------------------------- helpers -------------------------------- */

function answerToString(v: unknown): string {
  if (v == null) return "";
  if (typeof v === "string") return v;
  if (typeof v === "number") return String(v);
  if (typeof v === "boolean") return v ? "yes" : "no";
  if (Array.isArray(v)) return v.map(String).join(", ");
  try {
    return JSON.stringify(v);
  } catch {
    return String(v);
  }
}

function isTriggered(val: unknown): boolean {
  if (val == null) return false;
  if (typeof val === "string") return val.trim().length > 0;
  if (typeof val === "number") return true; // sliders always meaningful
  if (typeof val === "boolean") return val === true;
  if (Array.isArray(val)) return val.length > 0;
  return true;
}

function uniq(arr: string[]): string[] {
  return Array.from(
    new Set(arr.filter((x) => typeof x === "string" && x.trim().length > 0))
  );
}

function isMultiAnswer(
  av: AnswerValue | undefined
): av is { t: "multi"; v: string[] } {
  return !!av && av.t === "multi" && Array.isArray(av.v);
}

/**
 * Sanitise multi-select values where "none" must be mutually exclusive.
 * This is for clinician-facing tables/triggeredAnswers so they don't show
 * contradictory combos like ["follow.none","follow.deformity"].
 *
 * NOTE: Scoring integrity is enforced in the adapter. This is display-only.
 */
function sanitizeAnswersForDisplay(
  answers: Record<string, AnswerValue>
): Record<string, AnswerValue> {
  const cloned: Record<string, AnswerValue> = { ...answers };

  const cleanNoneMulti = (qid: string, noneOptionId: string) => {
    const av = cloned[qid];
    if (!isMultiAnswer(av)) return;

    const arr = av.v.map(String);

    if (arr.length === 0) return;

    // If only "none" selected => treat as no positives
    if (arr.length === 1) {
      if (arr[0] === noneOptionId) {
        cloned[qid] = { ...av, v: [] as string[] };
      }
      return;
    }

    // If "none" + others => drop "none"
    if (arr.includes(noneOptionId)) {
      cloned[qid] = {
        ...av,
        v: arr.filter((x) => x !== noneOptionId),
      };
    }
  };

  cleanNoneMulti("ankle.redflags.followUps", "follow.none");
  cleanNoneMulti("ankle.function.loadAggravators", "load.none");

  return cloned;
}

/* ------------------------- question bucketing ---------------------------- */

function buildTables(answers: Record<string, AnswerValue>) {
  const safety: TableRow[] = [];
  const context: TableRow[] = [];
  const symptoms: TableRow[] = [];
  const func: TableRow[] = [];
  const other: TableRow[] = [];

  for (const qid of Object.keys(answers)) {
    const val = answers[qid]?.v;
    const r = { questionId: qid, answer: answerToString(val) };

    if (qid.startsWith("ankle.redflags.")) safety.push(r);
    else if (qid.startsWith("ankle.history.")) context.push(r);
    else if (qid.startsWith("ankle.symptoms.")) symptoms.push(r);
    else if (qid.startsWith("ankle.function.")) func.push(r);
    else other.push(r);
  }

  const sortById = (a: TableRow, b: TableRow) =>
    a.questionId.localeCompare(b.questionId);

  safety.sort(sortById);
  context.sort(sortById);
  symptoms.sort(sortById);
  func.sort(sortById);
  other.sort(sortById);

  return { safety, context, symptoms, function: func, other };
}

function buildTriggered(answers: Record<string, AnswerValue>): TableRow[] {
  const out: TableRow[] = [];
  for (const qid of Object.keys(answers)) {
    const val = answers[qid]?.v;
    if (!isTriggered(val)) continue;
    out.push({ questionId: qid, answer: answerToString(val) });
  }
  out.sort((a, b) => a.questionId.localeCompare(b.questionId));
  return out;
}

/* ------------------------------ builder ---------------------------------- */

export function buildAnkleSummary(
  raw: RawAnkleResult,
  answers: Record<string, AnswerValue>
): IntakeSummary {
  const region = raw?.region || "Ankle";

  const triageLevel = (raw?.triage || "green") as "green" | "amber" | "red";
  const triageReasons = Array.isArray(raw?.redFlagNotes) ? raw.redFlagNotes : [];

  const detailedTop = Array.isArray(raw?.detailedTop) ? raw.detailedTop : [];
  const top3 = detailedTop.slice(0, 3).map((d) => ({
    code: d.key,
    label: d.name,
    score: typeof d.score === "number" ? d.score : Number(d.score ?? 0),
    rationale: Array.isArray(d.rationale) ? d.rationale : [],
    objectiveTests: Array.isArray(d.objectiveTests) ? d.objectiveTests : [],
  }));

  const fromRawClinical = Array.isArray(raw?.clinicalToDo)
    ? raw.clinicalToDo
    : [];
  const fromTopTests = detailedTop.flatMap((d) =>
    Array.isArray(d.objectiveTests) ? d.objectiveTests : []
  );
  const objectiveTests = uniq([...fromRawClinical, ...fromTopTests]);

  const displayAnswers = sanitizeAnswersForDisplay(answers);

  const tables = buildTables(displayAnswers);
  const triggeredAnswers = buildTriggered(displayAnswers);

  const narrative =
    triageLevel === "red"
      ? "Red-flag features were identified. Urgent clinical review is recommended."
      : triageLevel === "amber"
      ? "Some caution features were identified. Review triage notes and consider appropriate escalation."
      : "No major red-flag features identified from the provided answers. Review differentials and tests below.";

  return {
    region,
    triage: {
      level: triageLevel,
      reasons: triageReasons,
    },
    topDifferentials: top3,
    objectiveTests,
    narrative,
    tables,
    triggeredAnswers,
  };
}
