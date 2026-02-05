export interface LumbarSummary {
  region: "lumbar";
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
 * Minimal label map for Lumbar v1.
 * Keep this in sync with lumbar_labels_v1.dart (patient-facing strings).
 */
const lumbarLabelsV1: Record<string, string> = {
  // Red flags
  "lumbar.redflags.bladderBowelChange":
    "Have you noticed any new problems controlling your bladder or bowels?",
  "lumbar.redflags.saddleAnaesthesia":
    "Do you have any numbness around the groin/saddle area?",
  "lumbar.redflags.progressiveWeakness":
    "Is weakness in your leg/foot getting worse quickly?",
  "lumbar.redflags.feverUnwell":
    "Have you had fever or chills, or felt unusually unwell with this pain?",
  "lumbar.redflags.historyOfCancer": "Have you ever been treated for cancer?",
  "lumbar.redflags.recentTrauma":
    "Did this start after a significant fall, accident, or injury?",
  "lumbar.redflags.constantNightPain":
    "Is your pain constant and not eased by rest (including at night)?",

  // Pain
  "lumbar.pain.now": "Pain right now (0–10)",
  "lumbar.pain.worst24h": "Worst pain in the last 24 hours (0–10)",

  // Context
  "lumbar.context.ageBand": "What is your age group?",
  "age.18_35": "18–35",
  "age.36_50": "36–50",
  "age.51_65": "51–65",
  "age.65plus": "65+",

  // History
  "lumbar.history.timeSinceStart": "How long have you had this problem?",
  "time.lt48h": "Less than 48 hours",
  "time.2_14d": "2–14 days",
  "time.2_6wk": "2–6 weeks",
  "time.gt6wk": "More than 6 weeks",

  "lumbar.history.onset": "How did it start?",
  "onset.sudden": "Suddenly",
  "onset.gradual": "Gradually",
  "onset.recurrent": "It comes and goes / recurring",

  // Symptoms
  "lumbar.symptoms.painPattern": "Where is the pain mainly felt?",
  "pattern.central": "Mainly central lower back",
  "pattern.oneSide": "Mostly one side",
  "pattern.bothSides": "Both sides",

  "lumbar.symptoms.whereLeg": "If you have leg symptoms, where do you feel them?",
  "where.none": "No leg symptoms",
  "where.buttock": "Buttock",
  "where.thigh": "Thigh",
  "where.belowKnee": "Below the knee",
  "where.foot": "Foot",

  "lumbar.symptoms.pinsNeedles": "Do you have pins and needles/tingling?",
  "lumbar.symptoms.numbness": "Do you have numbness?",

  "lumbar.symptoms.aggravators": "What tends to make it worse?",
  "aggs.none": "None of these",
  "aggs.bendLift": "Bending forward or lifting",
  "aggs.coughSneeze": "Coughing or sneezing",
  "aggs.walk": "Walking",
  "aggs.extend": "Arching backwards / extending",
  "aggs.sitProlonged": "Sitting for a long time",
  "aggs.stand": "Standing",

  "lumbar.symptoms.easers": "What tends to make it feel better?",
  "eases.none": "Nothing in particular",
  "eases.backArched": "Standing/arching backwards (if it helps)",
  "eases.lieKneesBent": "Lying on your back with knees bent",
  "eases.shortWalk": "A short gentle walk",

  // Function
  "lumbar.function.gaitAbility": "How is your walking right now?",
  "gait.normal": "Normal",
  "gait.limp": "I’m limping",
  "gait.support": "I need support (stick/rail/person)",
  "gait.cannot": "I can’t walk",

  "lumbar.function.dayImpact": "How much does this affect your day-to-day? (0–10)",

  // Narrative / other
  "lumbar.history.additionalInfo":
    "Anything else you want your clinician to know (cause, progression, treatments so far)?",
};

// -------------------------
// helpers
// -------------------------
const label = (k: string) => lumbarLabelsV1[k] ?? k;

function unwrapAnswerValue(x: any): any {
  // Supports both raw values and {t, v} shapes
  if (x && typeof x === "object" && "v" in x) return (x as any).v;
  return x;
}

function formatAnswerValue(v: any): string {
  const val = unwrapAnswerValue(v);

  if (val === true) return "Yes";
  if (val === false) return "No";
  if (val == null) return "";

  if (Array.isArray(val)) {
    if (val.length === 0) return "";
    // map option ids to labels if possible
    return val.map((x) => (typeof x === "string" ? label(x) : String(x))).join(", ");
  }

  if (typeof val === "number") return String(val);

  if (typeof val === "string") {
    // map single-choice option ids to labels if possible
    return lumbarLabelsV1[val] ? label(val) : val;
  }

  return String(val);
}

function row(qid: string, answers: Record<string, any>) {
  return {
    question: label(qid),
    answer: formatAnswerValue(answers[qid]),
  };
}

function buildNarrative(answers: Record<string, any>) {
  const now = unwrapAnswerValue(answers["lumbar.pain.now"]);
  const worst = unwrapAnswerValue(answers["lumbar.pain.worst24h"]);
  const onset = formatAnswerValue(answers["lumbar.history.onset"]);
  const duration = formatAnswerValue(answers["lumbar.history.timeSinceStart"]);
  const pattern = formatAnswerValue(answers["lumbar.symptoms.painPattern"]);
  const leg = formatAnswerValue(answers["lumbar.symptoms.whereLeg"]);
  const pins = unwrapAnswerValue(answers["lumbar.symptoms.pinsNeedles"]) === true;
  const numb = unwrapAnswerValue(answers["lumbar.symptoms.numbness"]) === true;

  const neuroBits: string[] = [];
  if (pins) neuroBits.push("pins/needles");
  if (numb) neuroBits.push("numbness");

  const neuro = neuroBits.length ? ` Neuro symptoms reported: ${neuroBits.join(" and ")}.` : "";

  return `Lower back symptoms (${pattern}). Onset: ${onset}. Duration: ${duration}. Pain: ${now}/10 now, worst ${worst}/10 in last 24h. Leg distribution: ${leg || "not specified."}.${neuro}`;
}

// -------------------------
// main builder
// -------------------------
export function buildLumbarSummary(
  raw: any, // output of processLumbarAssessmentCore/processLumbarAssessment.ts
  answers: Record<string, any>
): LumbarSummary {
  const triageLevel: "red" | "amber" | "green" =
    raw?.triage ?? raw?.triageLevel ?? "green";

  const triageReasons: string[] =
    raw?.redFlagNotes ?? raw?.notes ?? raw?.triageReasons ?? [];

  // Prefer detailedTop (it contains rationale + objectiveTests)
  const detailed = Array.isArray(raw?.detailedTop) ? raw.detailedTop : null;

  const topDifferentials = (detailed ?? [])
    .slice(0, 3)
    .map((d: any) => ({
      code: d.key ?? d.code ?? "unknown",
      label: d.name ?? d.label ?? "Unknown",
      score: Number(d.score ?? 0),
      rationale: Array.isArray(d.rationale) ? d.rationale : [],
    }));

  // Objective tests: clinicalToDo is already deduped in scorer
  const objectiveTests: string[] = Array.isArray(raw?.clinicalToDo)
    ? raw.clinicalToDo
    : [];

  // TABLES from answers (NOT from raw)
  const safetyQ = [
    "lumbar.redflags.bladderBowelChange",
    "lumbar.redflags.saddleAnaesthesia",
    "lumbar.redflags.progressiveWeakness",
    "lumbar.redflags.feverUnwell",
    "lumbar.redflags.historyOfCancer",
    "lumbar.redflags.recentTrauma",
    "lumbar.redflags.constantNightPain",
  ];

  const contextQ = ["lumbar.context.ageBand", "lumbar.history.timeSinceStart", "lumbar.history.onset"];

  const symptomsQ = [
    "lumbar.pain.now",
    "lumbar.pain.worst24h",
    "lumbar.symptoms.painPattern",
    "lumbar.symptoms.whereLeg",
    "lumbar.symptoms.pinsNeedles",
    "lumbar.symptoms.numbness",
    "lumbar.symptoms.aggravators",
    "lumbar.symptoms.easers",
  ];

  const functionQ = ["lumbar.function.gaitAbility", "lumbar.function.dayImpact"];

  const otherQ = ["lumbar.history.additionalInfo"];

  const makeTable = (qids: string[]) =>
    qids
      .map((qid) => row(qid, answers))
      .filter((r) => r.answer.trim().length > 0);

  return {
    region: "lumbar",
    triage: {
      level: triageLevel,
      reasons: triageReasons,
    },
    topDifferentials,
    objectiveTests,
    narrative: buildNarrative(answers),
    tables: {
      safety: makeTable(safetyQ),
      context: makeTable(contextQ),
      symptoms: makeTable(symptomsQ),
      function: makeTable(functionQ),
      other: makeTable(otherQ),
    },
  };
}
