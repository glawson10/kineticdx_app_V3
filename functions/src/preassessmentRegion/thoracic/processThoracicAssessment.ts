/* Thoracic Spine Region – callable scoring + summary (europe-west1, v1 API) */
import * as functions from "firebase-functions/v1";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

const db = getFirestore();

type Triage = "green" | "amber" | "red";
type Answer =
  | { id: string; kind: "single"; value: string }
  | { id: string; kind: "multi"; values: string[] };

type Differential =
  | "facet"
  | "rib_joint"
  | "postural"
  | "disc_radic"
  | "costochondritis"
  | "cervical_referral"
  | "serious_non_msk";

const diffs: Record<
  Differential,
  { key: Differential; name: string; base: number; tests: string[] }
> = {
  facet: {
    key: "facet",
    name: "Thoracic facet joint dysfunction",
    base: 0.22,
    tests: [
      "Thoracic AROM with overpressure (rotation/extension)",
      "Unilateral PA/PPIVMs for concordant pain",
      "Symptom modification with repeated thoracic movement",
    ],
  },
  rib_joint: {
    key: "rib_joint",
    name: "Costovertebral / costotransverse (rib) joint sprain",
    base: 0.25,
    tests: [
      "Rib springing at rib angle",
      "Breath / cough provocation with palpation",
      "Thoracic rotation + rib palpation for concordant pain",
    ],
  },
  postural: {
    key: "postural",
    name: "Postural / myofascial thoracic pain",
    base: 0.18,
    tests: [
      "Postural correction symptom response",
      "Repeated thoracic extension/rotation symptom response",
      "Scapular control screen",
    ],
  },
  disc_radic: {
    key: "disc_radic",
    name: "Thoracic disc / radicular irritation (possible)",
    base: 0.12,
    tests: [
      "Neuro screen (myotomes/dermatomes/reflexes)",
      "Thoracic flexion/extension repeated movement response",
      "Valsalva provocation (if appropriate)",
    ],
  },
  costochondritis: {
    key: "costochondritis",
    name: "Costochondritis / anterior chest wall pain",
    base: 0.16,
    tests: [
      "Anterior chest wall palpation (costochondral junctions)",
      "Cross-body / horizontal adduction provocation",
      "Breathing provocation + palpation",
    ],
  },
  cervical_referral: {
    key: "cervical_referral",
    name: "Cervical referral pattern (cervicothoracic)",
    base: 0.10,
    tests: [
      "Cervical AROM with overpressure",
      "Spurling / distraction",
      "Upper limb neurodynamic test (ULNT)",
    ],
  },
  serious_non_msk: {
    key: "serious_non_msk",
    name: "Serious / non-MSK concern",
    base: 0.0,
    tests: ["Urgent medical referral", "Do not continue MSK testing"],
  },
};

/* ---------------- helpers ---------------- */

const getOne = (answers: Answer[], id: string) =>
  (answers.find((a) => a.id === id && a.kind === "single") as any)?.value ?? "";

const getMany = (answers: Answer[], id: string) =>
  (answers.find((a) => a.id === id && a.kind === "multi") as any)?.values ?? [];

/* ---------------- triage ---------------- */

function computeTriage(answers: Answer[]) {
  const notes: string[] = [];
  let triage: Triage = "green";

  const trauma = getOne(answers, "Q1_trauma");
  const redcluster = getMany(answers, "Q2_redcluster").filter((x: string) => x !== "none");
  const neuro = getMany(answers, "Q3_neuro").filter((x: string) => x !== "none");
  const rest = getOne(answers, "Q4_rest");
  const breath = getOne(answers, "Q10_breathprov");
  const painNow = Number(getOne(answers, "Q13_pain_now") || 0);

  if (trauma === "major") {
    triage = "red";
    notes.push("Major trauma");
  }

  if (redcluster.includes("chest_pressure") || redcluster.includes("sob")) {
    triage = "red";
    notes.push("Cardiorespiratory red flag");
  }

  if (redcluster.includes("fever_ache") || redcluster.includes("wtloss")) {
    triage = "red";
    notes.push("Systemic red flag");
  }

  if (neuro.length > 0) {
    triage = "red";
    notes.push("Bilateral neuro or gait/bowel/bladder change");
  }

  if (breath === "sob") {
    triage = "red";
    notes.push("Shortness of breath");
  }

  if (triage === "green" && trauma === "minor") {
    triage = "amber";
    notes.push("Minor trauma");
  }

  if (triage === "green" && rest === "all_positions" && painNow >= 7) {
    triage = "amber";
    notes.push("Severe constant pain");
  }

  return { triage, notes };
}

/* ---------------- scoring ---------------- */

function score(answers: Answer[], triage: Triage) {
  const S: Record<Differential, { score: number; why: string[] }> =
    Object.keys(diffs).reduce((acc: any, k) => {
      acc[k] = { score: diffs[k as Differential].base, why: [] };
      return acc;
    }, {});

  if (triage === "red") {
    S.serious_non_msk.score = 999;
    S.serious_non_msk.why.push("Red flag triage");
    return S;
  }

  const onset = getOne(answers, "Q5_onset");
  const loc = getOne(answers, "Q6_location");
  const worse = getMany(answers, "Q7_worse");
  const better = getMany(answers, "Q8_better");
  const irrit = getOne(answers, "Q9_irritability");
  const breath = getOne(answers, "Q10_breathprov");
  const sleep = getOne(answers, "Q11_sleep");
  const band = getOne(answers, "Q12_band");
  const painNow = Number(getOne(answers, "Q13_pain_now") || 0);

  /* Facet */
  if (worse.includes("sitting") || better.includes("move")) {
    S.facet.score += 0.18;
    S.facet.why.push("Mechanical pattern (movement improves)");
  }

  /* Postural */
  if (onset === "gradual" && better.includes("posture")) {
    S.postural.score += 0.25;
    S.postural.why.push("Gradual onset with postural relief");
  }

  /* Rib joint – gated */
  if (
    breath === "local_sharp" &&
    loc !== "front_chest" &&
    (worse.includes("bed") || worse.includes("breath"))
  ) {
    S.rib_joint.score += 0.45;
    S.rib_joint.why.push("Posterior rib pain with breath provocation");
  }

  /* Costochondritis – promoted */
  if (loc === "front_chest") {
    S.costochondritis.score += 0.45;
    S.costochondritis.why.push("Anterior chest wall pain");
    if (breath === "local_sharp") {
      S.costochondritis.score += 0.1;
    }
  }

  /* Disc / radicular */
  if (loc === "band_one_side" || band === "one_side") {
    S.disc_radic.score += 0.45;
  }
  if (irrit === "gt30" || sleep === "hard") {
    S.disc_radic.score += 0.2;
  }

  /* Cervical referral – stronger heuristic */
  if (loc === "between_blades" && worse.includes("overhead")) {
    S.cervical_referral.score += 0.25;
    S.cervical_referral.why.push("Between shoulder blades + overhead provocation");
  }

  /* Amber triage */
  if (triage === "amber") {
    S.serious_non_msk.score += 0.2;
    if (painNow >= 7) {
      S.serious_non_msk.score += 0.1;
      S.serious_non_msk.why.push("High pain intensity with amber triage");
    }
  }

  return S;
}

/* ---------------- summary ---------------- */

function buildSummary(answers: Answer[]) {
  const { triage, notes } = computeTriage(answers);
  const scored = score(answers, triage);

  const ranked = (Object.keys(scored) as Differential[])
    .map((k) => ({ key: k, ...scored[k] }))
    .sort((a, b) => b.score - a.score);

  const top = ranked.slice(0, triage === "red" ? 1 : 3).map((r) => ({
    name: diffs[r.key].name,
    score: Number(Math.max(0, r.score).toFixed(2)),
    rationale: r.why,
    objectiveTests: diffs[r.key].tests,
  }));

  return {
    region: "Thoracic spine",
    triage,
    redFlagNotes: triage === "green" ? [] : notes,
    topDifferentials: top.map((t) => ({ name: t.name, score: t.score })),
    clinicalToDo: Array.from(new Set(top.flatMap((t) => t.objectiveTests))),
    detailedTop: top,
  };
}

/**
 * ✅ Pure helper (answers-only) for Phase-3 intake session summary generation.
 * Uses the exact same buildSummary/scoring.
 */
export function buildThoracicSummaryFromAnswers(answers: Answer[]) {
  return buildSummary(answers);
}

/**
 * ✅ Callable-core export (data/ctx) used by other Cloud Functions (decision support, summaries, etc).
 * This is the one your intake code should import.
 */
export async function processThoracicAssessmentCore(
  data: any,
  _ctx?: functions.https.CallableContext
) {
  const assessmentId: string | undefined = data?.assessmentId;
  const answers: Answer[] = Array.isArray(data?.answers) ? data.answers : [];

  const summary = buildSummary(answers);

  if (assessmentId) {
    await db
      .collection("assessments")
      .doc(assessmentId)
      .set(
        {
          triageRegion: "thoracic",
          triageStatus: summary.triage,
          topDifferentials: summary.topDifferentials,
          clinicalToDo: summary.clinicalToDo,
          summary: { thoracic: summary },
          processedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
  }

  return { ok: true, summary };
}

/* ---------------- callable ---------------- */

export const processThoracicAssessment = functions
  .region("europe-west1")
  .https.onCall(async (data, ctx) => {
    return processThoracicAssessmentCore(data, ctx);
  });
