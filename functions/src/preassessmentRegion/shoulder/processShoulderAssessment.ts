// TypeScript logic for shoulder region — mirrored from hip-region scoring structure
import * as functions from "firebase-functions/v1";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

const db = getFirestore();

type Triage = "green" | "amber" | "red";
type Answer =
  | { id: string; kind: "single"; value: string }
  | { id: string; kind: "multi"; values: string[] }
  | { id: string; kind: "slider"; value: number };

type Differential =
  | "rc_related"
  | "adhesive_capsulitis"
  | "ac_joint"
  | "biceps_slap"
  | "cervical_referral"
  | "scap_dyskinesis"
  | "acute_red_pathway";

interface DiffInfo {
  key: Differential;
  name: string;
  base: number;
  tests: string[];
}

const diffs: Record<Differential, DiffInfo> = {
  rc_related: {
    key: "rc_related",
    name: "Rotator cuff related shoulder pain",
    base: 0.22,
    tests: [
      "Painful arc",
      "Isometric ER/IR with scapula stabilized",
      "Jobe's test (empty can)",
    ],
  },
  adhesive_capsulitis: {
    key: "adhesive_capsulitis",
    name: "Adhesive capsulitis (frozen shoulder)",
    base: 0.2,
    tests: [
      "Global passive ROM restriction (esp. ER)",
      "Capsular end-feel",
      "Painful resisted ER in neutral",
    ],
  },
  ac_joint: {
    key: "ac_joint",
    name: "Acromioclavicular joint pain",
    base: 0.16,
    tests: [
      "Localized AC point tenderness",
      "Cross-body adduction test",
      "O'Brien's test",
    ],
  },
  biceps_slap: {
    key: "biceps_slap",
    name: "Biceps tendinopathy / SLAP lesion",
    base: 0.15,
    tests: [
      "Bicipital groove tenderness",
      "Speed's test",
      "Yergason's test",
    ],
  },
  cervical_referral: {
    key: "cervical_referral",
    name: "Cervical spine referral",
    base: 0.1,
    tests: [
      "Spurling's / neck ROM provocation",
      "Neuro screen (myotomes, dermatomes)",
    ],
  },
  scap_dyskinesis: {
    key: "scap_dyskinesis",
    name: "Scapular dyskinesis / motor control impairment",
    base: 0.12,
    tests: [
      "Scapular dyskinesis test (repeated elevation)",
      "Scapular assistance test",
      "Wall push-up for winging",
    ],
  },
  acute_red_pathway: {
    key: "acute_red_pathway",
    name: "Fracture/dislocation or systemic red-flag",
    base: 0,
    tests: [
      "Urgent imaging (X-ray ± bloods)",
      "Neurovascular check; deformity observation",
    ],
  },
};

const getOne = (answers: Answer[], id: string): string | undefined => {
  const a = answers.find(
    (x) => x.id === id && x.kind === "single"
  ) as Extract<Answer, { kind: "single" }> | undefined;
  return a?.value;
};

const getMany = (answers: Answer[], id: string): string[] => {
  const a = answers.find(
    (x) => x.id === id && x.kind === "multi"
  ) as Extract<Answer, { kind: "multi" }> | undefined;
  return Array.isArray(a?.values) ? a.values : [];
};

const yn = (v?: string) => (v ?? "").toLowerCase() === "yes";

function computeTriage(answers: Answer[]) {
  const notes: string[] = [];
  let triage: Triage = "green";

  const trauma = yn(getOne(answers, "S_rf_trauma_high_energy"));
  const deformity = yn(getOne(answers, "S_rf_deformity_after_injury"));
  const unrelenting = yn(getOne(answers, "S_rf_constant_unrelenting_pain"));
  const feverHotJoint = yn(getOne(answers, "S_rf_fever_or_hot_red_joint"));
  const cancer = yn(getOne(answers, "S_rf_cancer_or_weight_loss"));
  const canElevate = yn(getOne(answers, "S_rf_can_active_elevate"));

  if (!canElevate || trauma || deformity || unrelenting || feverHotJoint) {
    triage = "red";
    if (!canElevate) notes.push("Unable to elevate arm actively");
    if (trauma) notes.push("Recent trauma or fall");
    if (deformity) notes.push("Visible deformity or dislocation suspected");
    if (unrelenting) notes.push("Constant pain, unrelenting at rest");
    if (feverHotJoint) notes.push("Possible septic joint or inflammation");
  } else if (cancer) {
    triage = "amber";
    notes.push("History of cancer or unexplained weight loss");
  }

  return { triage, notes };
}

function score(answers: Answer[], triage: Triage) {
  const S: Record<Differential, { score: number; why: string[] }> = (
    Object.keys(diffs) as Differential[]
  ).reduce(
    (acc, k) => {
      acc[k] = { score: diffs[k].base, why: [] };
      return acc;
    },
    {} as Record<Differential, { score: number; why: string[] }>
  );

  if (triage === "red") {
    S.acute_red_pathway.score = 999;
    S.acute_red_pathway.why.push("Red-flag criteria met");
    return S;
  }
  S.acute_red_pathway.score = -Infinity;

  const area = getOne(answers, "S_pain_area") ?? "";
  const overhead = yn(getOne(answers, "S_overhead_aggs"));
  const stiffness = yn(getOne(answers, "S_stiffness"));
  const weakness = yn(getOne(answers, "S_weakness"));
  const neck = yn(getOne(answers, "S_neck_involved"));
  const tender = getOne(answers, "S_tender_spot") ?? "";

  // Scoring logic
  if (area === "painArea.diffuse" && weakness && overhead) {
    S.scap_dyskinesis.score += 0.3;
    S.scap_dyskinesis.why.push("Diffuse pain with overhead + weakness");
  }
  if (stiffness && !weakness) {
    S.adhesive_capsulitis.score += 0.28;
    S.adhesive_capsulitis.why.push("Stiffness without weakness");
  }
  if (area === "painArea.ac_point" || tender === "tender.ac_point") {
    S.ac_joint.score += 0.25;
    S.ac_joint.why.push("AC point pain or tenderness");
  }
  if (tender === "tender.bicipital_groove") {
    S.biceps_slap.score += 0.26;
    S.biceps_slap.why.push("Bicipital groove tenderness");
  }
  if (overhead && weakness) {
    S.rc_related.score += 0.28;
    S.rc_related.why.push("Overhead pain and weakness");
  }
  if (neck) {
    S.cervical_referral.score += 0.24;
    S.cervical_referral.why.push("Neck involvement");
  }

  return S;
}

function buildSummary(answers: Answer[]) {
  const { triage, notes } = computeTriage(answers);
  const scored = score(answers, triage);

  const ranked = (Object.keys(scored) as Differential[])
    .filter((k) => (triage === "red" ? true : k !== "acute_red_pathway"))
    .map((k) => ({ key: k, ...scored[k] }))
    .sort((a, b) => b.score - a.score || diffs[b.key].base - diffs[a.key].base);

  const topCount = triage === "red" ? 1 : 3;
  const top = ranked.slice(0, topCount).map((item) => ({
    key: item.key,
    name: diffs[item.key].name,
    score: Number(Math.max(0, item.score).toFixed(2)),
    rationale: item.why,
    objectiveTests: diffs[item.key].tests,
  }));

  const globalTests =
    triage === "red"
      ? [
          "Urgent imaging (X-ray ± bloods)",
          "Neurovascular check; deformity observation",
        ]
      : [
          "Shoulder AROM/PROM assessment",
          "Neck screen; Spurling's + myotomes",
          "Functional scapula control (wall push-up, elevation reps)",
        ];

  const clinicalToDo = Array.from(
    new Set([...globalTests, ...top.flatMap((t) => t.objectiveTests)])
  );

  return {
    region: "Shoulder",
    triage,
    redFlagNotes: triage === "green" ? [] : notes,
    topDifferentials: top.map((t) => ({ name: t.name, score: t.score })),
    clinicalToDo,
    detailedTop: top,
  };
}

export async function processShoulderAssessmentCore(
  data: any,
  _ctx?: functions.https.CallableContext
) {
    const assessmentId: string | undefined = data?.assessmentId;
    const answers: Answer[] = Array.isArray(data?.answers) ? data.answers : [];

    if (!assessmentId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "assessmentId is required"
      );
    }

    const summary = buildSummary(answers);

    await db
      .collection("assessments")
      .doc(assessmentId)
      .set(
        {
          triageStatus: summary.triage,
          topDifferentials: summary.topDifferentials,
          clinicianSummary: summary,
          triageRegion: "shoulder",
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

    return {
      triageStatus: summary.triage,
      topDifferentials: summary.topDifferentials,
      clinicianSummary: summary,
    };
         }
       
         // -------------------------------
         // Firebase callable wrapper
         // -------------------------------
         export const processShoulderAssessment = functions
           .region("europe-west1")
           .https.onCall(async (data, ctx) => {
             return processShoulderAssessmentCore(data, ctx);
           });
       