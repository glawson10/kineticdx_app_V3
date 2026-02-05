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
  | "compression_fracture"
  | "costochondritis"
  | "cervical_referral"
  | "visceral_referral"
  | "serious_non_msk";

interface DiffInfo {
  key: Differential;
  name: string;
  base: number;
  tests: string[];
}

const diffs: Record<Differential, DiffInfo> = {
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
      "Breath provocation (deep inhale/cough)",
      "Side-lying rib compression",
    ],
  },
  postural: {
    key: "postural",
    name: "Postural or myofascial thoracic pain",
    base: 0.2,
    tests: [
      "Sustained posture reproduction",
      "Palpation of paraspinals/rhomboids",
      "Symptom change with posture correction",
    ],
  },
  disc_radic: {
    key: "disc_radic",
    name: "Thoracic disc irritation / radicular pattern",
    base: 0.22,
    tests: [
      "Thoracic flexion/rotation reproduction of band pain",
      "Dermatomal sensory screen around trunk",
      "Neuro screen if indicated",
    ],
  },
  compression_fracture: {
    key: "compression_fracture",
    name: "Thoracic compression fracture (osteoporotic/minor trauma risk)",
    base: 0.08,
    tests: [
      "Avoid repeated end-range testing",
      "Gentle percussion tenderness (if safe)",
      "Imaging referral if suspected",
    ],
  },
  costochondritis: {
    key: "costochondritis",
    name: "Costochondritis / anterior chest wall MSK pain",
    base: 0.07,
    tests: [
      "Palpation of costochondral junctions",
      "Pain reproduction with direct pressure",
      "Exclude cardiorespiratory red flags",
    ],
  },
  cervical_referral: {
    key: "cervical_referral",
    name: "Cervicothoracic referral (lower cervical source)",
    base: 0.06,
    tests: [
      "Cervical AROM / repeated movements",
      "Symptom modification with neck unloading",
      "Upper limb neuro screen if indicated",
    ],
  },
  visceral_referral: {
    key: "visceral_referral",
    name: "Possible visceral referral / non-MSK masquerader",
    base: 0.04,
    tests: [
      "Vitals (BP, HR, RR, SpO₂, temp)",
      "Assess non-mechanical pattern",
      "Medical referral if uncertain",
    ],
  },
  serious_non_msk: {
    key: "serious_non_msk",
    name: "Serious / non-MSK concern",
    base: 0.0,
    tests: [
      "Urgent medical referral",
      "Do not continue MSK testing",
    ],
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
    notes.push("Pain with shortness of breath");
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
  const trauma = getOne(answers, "Q1_trauma");

  /* Postural */
  if (onset === "gradual" && worse.includes("sitting")) {
    S.postural.score += 0.4;
    S.postural.why.push("Gradual onset + sitting aggravation");
  }
  if (better.includes("posture") || better.includes("move")) {
    S.postural.score += 0.2;
  }

  /* Facet */
  if (["lift_twist", "woke", "sport"].includes(onset)) {
    S.facet.score += 0.3;
  }
if (
  worse.some((w: string) =>
    ["twist", "overhead", "lift"].includes(w))) {  S.facet.score += 0.3;}

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
  }
  if (loc === "between_blades" && worse.includes("sitting")) {
    S.cervical_referral.score += 0.1;
  }

  /* Compression fracture – pattern detection */
  if (
    trauma === "minor" &&
    painNow >= 7 &&
    better.includes("nothing")
  ) {
    S.compression_fracture.score += 0.45;
    S.compression_fracture.why.push("Minor trauma + severe constant pain");
  }

  /* Visceral / serious awareness */
const redcluster = getMany(answers, "Q2_redcluster").filter((x: string) => x !== "none");
  if (redcluster.length > 0) {
    S.serious_non_msk.score += 0.1;
  }

  return S;
}

/* ---------------- summary ---------------- */

function buildSummary(answers: Answer[]) {
  const { triage, notes } = computeTriage(answers);
  const scored = score(answers, triage);

  const ranked = Object.keys(scored)
    .map((k) => ({ key: k as Differential, ...scored[k as Differential] }))
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

/* ---------------- callable ---------------- */

export const processThoracicAssessment = functions
  .region("europe-west1")
  .https.onCall(async (data, _ctx) => {
    const assessmentId = data?.assessmentId;
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
            clinicianSummary: summary,
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
    }

    return summary;
  });
export { buildSummary };