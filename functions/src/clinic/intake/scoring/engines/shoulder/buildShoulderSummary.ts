import * as functions from "firebase-functions/v1";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

const db = getFirestore();

const yn = (v: any): "yes" | "no" =>
  v === true || v === "yes" || v === "Yes" ? "yes" : "no";

/* ----------------- normalize ----------------- */
/**
 * IMPORTANT:
 * - Your Dart now saves answers.tenderSpot (mapped to: ac_point | bicipital_groove | none_unsure)
 * - This TS reads from Firestore: doc.answers.region.shoulder.answers
 * - So we just need to include tenderSpot here and score it.
 */
function normalizeShoulderAnswers(raw: any) {
  const answers = raw?.answers ?? raw ?? {};
  const rf = raw?.redFlags ?? answers?.redFlags ?? {};

  return {
    side: answers.side ?? "",
    dominant: yn(answers.dominant), // legacy (kept; not used for scoring)
    onset: answers.onset ?? "", // gradual | afterOverhead | afterLiftPull | minorFallJar | appeared (if you add later)
    painArea: answers.painArea ?? "", // top_front | outer_side | back | diffuse
    nightPain: yn(answers.nightPain),
    overhead_aggravates: yn(answers.overheadAggravates),
    weakness: yn(answers.weakness),
    stiffness: yn(answers.stiffness),
    clicking: yn(answers.clicking),
    neckInvolved: yn(answers.neckInvolved),
    handNumbness: yn(answers.handNumbness),

    // ✅ NEW: discriminator question from Dart
    // expected: "ac_point" | "bicipital_groove" | "none_unsure" | ""
    tenderSpot: answers.tenderSpot ?? "",

    functionLimits: Array.isArray(answers.functionLimits)
      ? answers.functionLimits
      : [],

    redFlags: {
      fever_or_hot_red_joint: yn(rf.feverOrHotRedJoint),
      deformity_after_injury: yn(rf.deformityAfterInjury),
      new_neuro_symptoms: yn(rf.newNeuroSymptoms),
      constant_unrelenting_pain: yn(rf.constantUnrelentingPain),
      cancer_history_or_weight_loss: yn(rf.cancerHistoryOrWeightLoss),
      trauma_high_energy: yn(rf.traumaHighEnergy),
      can_active_elevate: yn(rf.canActiveElevateToShoulderHeight), // yes means CAN elevate
    },
  };
}

/* ----------------- types ----------------- */

type Triage = "green" | "amber" | "red";

type Differential =
  | "rc_tendinopathy"
  | "full_thickness_rc_tear"
  | "adhesive_capsulitis"
  | "glenohumeral_oa"
  | "ac_joint"
  | "biceps_slap"
  | "instability_labral"
  | "calcific_bursitis"
  | "cervical_referred"
  | "acute_red_pathway";

interface DiffInfo {
  key: Differential;
  name: string;
  base: number;
  tests: string[];
}

/* ----------------- differentials ----------------- */

const diffs: Record<Differential, DiffInfo> = {
  rc_tendinopathy: {
    key: "rc_tendinopathy",
    name: "Rotator cuff–related shoulder pain (tendinopathy / SAPS)",
    base: 0.22,
    tests: [
      "Painful arc (60–120°)",
      "Resisted ER / ABD (pain > weakness)",
      "Hawkins–Kennedy / Neer (contextual)",
    ],
  },

  full_thickness_rc_tear: {
    key: "full_thickness_rc_tear",
    name: "Full-thickness rotator cuff tear",
    base: 0.14,
    tests: [
      "ER lag sign / Drop arm",
      "True weakness not pain-limited",
      "Compare resisted ER/ABD bilaterally",
    ],
  },

  adhesive_capsulitis: {
    key: "adhesive_capsulitis",
    name: "Adhesive capsulitis (frozen shoulder)",
    base: 0.18,
    tests: [
      "Global PROM restriction (ER > ABD > IR)",
      "Active ≈ passive ROM limitation",
      "Capsular end-feel",
    ],
  },

  glenohumeral_oa: {
    key: "glenohumeral_oa",
    name: "Glenohumeral osteoarthritis",
    base: 0.12,
    tests: [
      "PROM stiffness + crepitus",
      "Functional ER/IR loss",
      "Imaging if indicated",
    ],
  },

  ac_joint: {
    key: "ac_joint",
    name: "Acromioclavicular joint pain",
    base: 0.12,
    tests: ["AC joint palpation", "Cross-body adduction", "Paxinos test"],
  },

  biceps_slap: {
    key: "biceps_slap",
    name: "Long head of biceps / SLAP-related pain",
    base: 0.1,
    tests: [
      "Speed’s / Yergason’s",
      "Bicipital groove palpation",
      "O’Brien’s (contextual)",
    ],
  },

  instability_labral: {
    key: "instability_labral",
    name: "Shoulder instability / labral pathology",
    base: 0.14,
    tests: [
      "Apprehension / relocation",
      "Load-and-shift",
      "Crank / Biceps Load",
    ],
  },

  calcific_bursitis: {
    key: "calcific_bursitis",
    name: "Calcific tendinopathy / acute bursitis flare",
    base: 0.08,
    tests: [
      "Marked pain with active elevation",
      "Pain-limited strength (A >> P early)",
      "Consider X-ray/US if severe acute flare",
    ],
  },

  cervical_referred: {
    key: "cervical_referred",
    name: "Cervical referred pain / radiculopathy",
    base: 0.14,
    tests: ["Cervical ROM + Spurling’s", "Neuro screen", "Arm Squeeze Test"],
  },

  acute_red_pathway: {
    key: "acute_red_pathway",
    name: "Suspected fracture, dislocation, infection, tumour",
    base: 0,
    tests: ["Urgent imaging", "Neurovascular exam", "Immediate referral"],
  },
};

/* ----------------- triage ----------------- */

function computeTriage(a: ReturnType<typeof normalizeShoulderAnswers>) {
  const notes: string[] = [];
  let triage: Triage = "green";

  if (
    a.redFlags.fever_or_hot_red_joint === "yes" ||
    a.redFlags.deformity_after_injury === "yes" ||
    a.redFlags.new_neuro_symptoms === "yes"
  ) {
    triage = "red";
    notes.push("Red flag shoulder presentation");
  }

  if (
    triage === "green" &&
    (a.redFlags.constant_unrelenting_pain === "yes" ||
      a.redFlags.cancer_history_or_weight_loss === "yes")
  ) {
    triage = "amber";
    notes.push("Systemic or unrelenting pain features");
  }

  return { triage, notes };
}

/* ----------------- scoring ----------------- */

function score(a: ReturnType<typeof normalizeShoulderAnswers>, triage: Triage) {
  const S: Record<Differential, { score: number; why: string[] }> =
    (Object.keys(diffs) as Differential[]).reduce((acc, k) => {
      acc[k] = { score: diffs[k].base, why: [] };
      return acc;
    }, {} as any);

  if (triage === "red") {
    S.acute_red_pathway.score = 999;
    S.acute_red_pathway.why.push("Red flag criteria met");
    return S;
  }

  S.acute_red_pathway.score = -Infinity;

  const limits = a.functionLimits;
  const limitedOverhead =
    limits.includes("Reaching overhead") || limits.includes("Sports/overhead work");
  const limitedJacket = limits.includes("Putting on a jacket");
  const limitedSleepSide = limits.includes("Sleeping on that side");

  // ───────── RC tendinopathy ─────────
  // Context-aware overhead bump to prevent RC stealing AC/biceps cases when pain is top/front.
  if (a.overhead_aggravates === "yes" || limitedOverhead) {
    const overheadBump = a.painArea === "top_front" ? 0.16 : 0.24;
    S.rc_tendinopathy.score += overheadBump;
    S.rc_tendinopathy.why.push("Overhead aggravation/limitation");
  }
  if (a.painArea === "outer_side") {
    S.rc_tendinopathy.score += 0.18;
    S.rc_tendinopathy.why.push("Lateral shoulder pain");
  }
  if (a.nightPain === "yes" || limitedSleepSide) {
    S.rc_tendinopathy.score += 0.12;
    S.rc_tendinopathy.why.push("Night pain / sleep disturbance");
  }

  // ✅ TUNE #1: If stiffness/jacket limitation present, reduce isolated RC likelihood
  if (a.stiffness === "yes" || limitedJacket) {
    S.rc_tendinopathy.score -= 0.18;
    S.rc_tendinopathy.why.push(
      "Stiffness/jacket limitation reduces likelihood of isolated RC tendinopathy"
    );
  }

  // ───────── Full thickness tear ─────────
  // ✅ TUNE #2: cannot elevate is a strong tear signal and reduces simple RC
  if (a.redFlags.can_active_elevate === "no") {
    S.full_thickness_rc_tear.score += 0.22;
    S.full_thickness_rc_tear.why.push(
      "Cannot actively elevate suggests large tear/structural disruption"
    );

    S.rc_tendinopathy.score -= 0.12;
    S.rc_tendinopathy.why.push(
      "Inability to elevate reduces likelihood of simple RC tendinopathy"
    );
  }

  if (a.weakness === "yes" && a.redFlags.can_active_elevate === "no") {
    S.full_thickness_rc_tear.score += 0.45;
    S.full_thickness_rc_tear.why.push(
      "Weakness + inability to elevate supports full-thickness tear pattern"
    );
  }

  // ───────── Adhesive capsulitis ─────────
  if (a.stiffness === "yes") {
    S.adhesive_capsulitis.score += 0.35;
    S.adhesive_capsulitis.why.push("Global stiffness reported");
  }
  if (limitedJacket) {
    S.adhesive_capsulitis.score += 0.22;
    S.adhesive_capsulitis.why.push("Difficulty with jacket (ER/IR loss)");
  }

  // ───────── GH OA (kept modest without age/PMH) ─────────
  if (a.stiffness === "yes" && a.painArea === "diffuse") {
    S.glenohumeral_oa.score += 0.25;
    S.glenohumeral_oa.why.push("Diffuse pain + stiffness");
  }

  // ───────── AC joint ─────────
  if (a.painArea === "top_front") {
    S.ac_joint.score += 0.35;
    S.ac_joint.why.push("Top/front shoulder pain");
  }

  // ───────── Biceps / SLAP ─────────
  if (a.painArea === "top_front" && a.clicking === "yes") {
    S.biceps_slap.score += 0.28;
    S.biceps_slap.why.push("Anterior pain + clicking");
  }

  // ───────── Instability / labrum ─────────
  if (a.clicking === "yes" && a.onset === "minorFallJar") {
    S.instability_labral.score += 0.40;
    S.instability_labral.why.push("Mechanical symptoms after minor trauma/jar");

    // small RC de-weight when clear labral trigger exists
    S.rc_tendinopathy.score -= 0.08;
    S.rc_tendinopathy.why.push(
      "Clicking after jar-type onset reduces likelihood of isolated RC tendinopathy"
    );
  }

  // ───────── Calcific / bursitis flare ─────────
  // Requires an acute flare-style onset to avoid stealing classic RC cases.
  const flareOnset = a.onset === "afterOverhead" || a.onset === "appeared";

  if (
    flareOnset &&
    a.nightPain === "yes" &&
    a.overhead_aggravates === "yes" &&
    a.stiffness === "no" &&
    a.redFlags.can_active_elevate === "yes"
  ) {
    S.calcific_bursitis.score += 0.72;
    S.calcific_bursitis.why.push(
      "Acute flare pattern: night + overhead pain without true stiffness, still able to elevate"
    );

    // reduce RC slightly in this flare context
    S.rc_tendinopathy.score -= 0.16;
    S.rc_tendinopathy.why.push(
      "Flare pattern reduces likelihood of simple RC tendinopathy"
    );
  }

  // ───────── Cervical ─────────
  if (a.neckInvolved === "yes" || a.handNumbness === "yes") {
    S.cervical_referred.score += 0.6;
    S.cervical_referred.why.push("Neck-related or distal symptoms");
  }

  // ───────── NEW: tender spot discriminator (AC vs biceps vs RC) ─────────
  const tenderSpot = a.tenderSpot;

  if (tenderSpot === "ac_point") {
    S.ac_joint.score += 0.28;
    S.ac_joint.why.push("Point tenderness at AC joint");

    S.biceps_slap.score -= 0.10;
    S.biceps_slap.why.push(
      "AC point tenderness reduces likelihood of primary biceps source"
    );

    S.rc_tendinopathy.score -= 0.08;
    S.rc_tendinopathy.why.push(
      "AC point tenderness reduces likelihood of isolated RC tendinopathy"
    );
  }

  if (tenderSpot === "bicipital_groove") {
    S.biceps_slap.score += 0.30;
    S.biceps_slap.why.push(
      "Bicipital groove tenderness supports biceps/SLAP spectrum"
    );

    S.ac_joint.score -= 0.10;
    S.ac_joint.why.push(
      "Bicipital groove tenderness reduces likelihood of primary AC source"
    );
  }

  return S;
}

/* ----------------- summary ----------------- */

function buildSummary(raw: any) {
  const a = normalizeShoulderAnswers(raw);
  const { triage, notes } = computeTriage(a);
  const scored = score(a, triage);

  const ranked = (Object.keys(scored) as Differential[])
    .filter((k) => (triage === "red" ? true : k !== "acute_red_pathway"))
    .map((k) => ({ key: k, ...scored[k] }))
    .sort((x, y) => y.score - x.score || diffs[y.key].base - diffs[x.key].base);

  const top = ranked.slice(0, triage === "red" ? 1 : 3).map((r) => ({
    name: diffs[r.key].name,
    score: Number(Math.max(0, r.score).toFixed(2)),
    rationale: r.why,
    objectiveTests: diffs[r.key].tests,
  }));

  const globalTests =
    triage === "red"
      ? ["Urgent imaging/referral as indicated", "Neurovascular exam"]
      : [
          "AROM vs PROM comparison (pain vs stiffness dominance)",
          "Isometric ER/IR/ABD strength (pain-limited vs true weakness)",
          "Palpation: AC joint + bicipital groove (guided by tender spot response)",
          "Cervical screen if neck/hand symptoms",
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

/* ----------------- callable ----------------- */

export const processShoulderAssessment = functions
  .region("europe-west1")
  .https.onCall(async (data: { assessmentId?: string }) => {
    const assessmentId = data?.assessmentId;
    if (!assessmentId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Missing assessmentId"
      );
    }

    const docRef = db.collection("assessments").doc(assessmentId);
    const snap = await docRef.get();
    const doc = snap.data() || {};

    // Matches your current pattern: shoulder answers live in doc.answers.region.shoulder :contentReference[oaicite:1]{index=1}
    const shoulder = (doc as any)?.answers?.region?.shoulder || {};
    const summary = buildSummary(shoulder);

    await docRef.set(
      {
        triageRegion: "shoulder",
        triageStatus: summary.triage,
        topDifferentials: summary.topDifferentials,
        clinicianSummary: summary,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return {
      triageStatus: summary.triage,
      topDifferentials: summary.topDifferentials,
      clinicianSummary: summary,
    };
  });
export { buildSummary };