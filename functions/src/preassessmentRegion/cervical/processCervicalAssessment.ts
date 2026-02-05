// functions/src/cervical/processCervicalAssessment.ts

/* Cervical Spine Region – callable scoring + summary (europe-west1, v1 API) */
import * as functions from "firebase-functions/v1";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

const db = getFirestore();

type Triage = "green" | "amber" | "red";
type Answer =
  | { id: string; kind: "single"; value: string }
  | { id: string; kind: "multi"; values: string[] }
  | { id: string; kind: "slider"; value: number };

type Differential =
  | "mechanical_neck_pain"
  | "facet_cervical"
  | "cervical_radiculopathy"
  | "cervical_myelopathy"
  | "whiplash_wad"
  | "cervicogenic_headache"
  | "primary_headache"
  | "myofascial_trigger_points"
  | "shoulder_referred"
  | "systemic_inflammatory"
  | "acute_red_pathway";

interface DiffInfo {
  key: Differential;
  name: string;
  base: number;
  tests: string[];
}

const diffs: Record<Differential, DiffInfo> = {
  mechanical_neck_pain: {
    key: "mechanical_neck_pain",
    name: "Mechanical neck pain (non-specific / movement-related)",
    base: 0.18,
    tests: [
      "Cervical AROM/PROM (note directional preference; pain vs stiffness)",
      "Posture + movement control screen (deep neck flexor endurance/CCFT if appropriate)",
      "Palpation of cervical paraspinals/upper trap/levator; reproduce familiar pain",
      "NDI baseline (Neck Disability Index) to track change",
    ],
  },

  facet_cervical: {
    key: "facet_cervical",
    name: "Cervical facet / zygapophyseal joint pain (capsular pattern)",
    base: 0.14,
    tests: [
      "Extension-rotation / quadrant position reproduces local neck pain",
      "Facet palpation tenderness; segmental PA’s for symptom reproduction",
      "ROM bias: pain provoked with extension/rotation (often unilateral)",
    ],
  },

  cervical_radiculopathy: {
    key: "cervical_radiculopathy",
    name: "Cervical radiculopathy (nerve-root irritation/compression)",
    base: 0.10,
    tests: [
      "Wainner cluster: Spurling + ULTT1 (median) + distraction relief + ipsi rotation <60°",
      "Neuro screen: dermatomes / myotomes / reflexes; compare sides",
      "Differentiate shoulder vs cervical (arm elevation provocation vs neck provocation)",
    ],
  },

  cervical_myelopathy: {
    key: "cervical_myelopathy",
    name: "Cervical myelopathy (cord compression pattern) – urgent work-up if suspected",
    base: 0.10,
    tests: [
      "UMN signs: Hoffman, Babinski, clonus, hyperreflexia",
      "Gait assessment: broad-based/unsteady; tandem walk",
      "Hand dexterity: clumsiness, grip-release, buttoning",
      "If suspected → urgent medical review / imaging pathway",
    ],
  },

  whiplash_wad: {
    key: "whiplash_wad",
    name: "Whiplash-associated disorder (WAD) / post-trauma neck pain",
    base: 0.12,
    tests: [
      "ROM + tenderness + neuro screen (WAD grading concept)",
      "Cervical proprioception / joint position error if persistent symptoms",
      "Oculomotor/vestibular screen if dizziness/visual symptoms reported",
      "Psychosocial screen (fear avoidance / catastrophising) if persistent",
    ],
  },

  cervicogenic_headache: {
    key: "cervicogenic_headache",
    name: "Cervicogenic headache (upper cervical source C0–C3)",
    base: 0.10,
    tests: [
      "Flexion-Rotation Test (FRT): symptom reproduction + restricted C1–C2 rotation",
      "Upper cervical segmental assessment (C1–C3) reproduces headache",
      "Headache changes with neck posture/movement and manual techniques",
    ],
  },

  primary_headache: {
    key: "primary_headache",
    name: "Primary headache pattern (migraine / tension-type) – consider non-neck origin",
    base: 0.06,
    tests: [
      "Headache feature screen (aura/photophobia/nausea; pulsating vs band-like)",
      "Neck exam: if neck movement does NOT modulate headache → consider primary",
      "Escalate if atypical/new severe headache or neuro/vascular red flags",
    ],
  },

  myofascial_trigger_points: {
    key: "myofascial_trigger_points",
    name: "Myofascial neck pain / trigger point referral (upper trap/levator/suboccipital)",
    base: 0.10,
    tests: [
      "Palpation reproduces familiar referred pain pattern",
      "ROM: pain-limited without dermatomal/neuro pattern",
      "Exclude radiculopathy/myelopathy if neuro signs are present",
    ],
  },

  shoulder_referred: {
    key: "shoulder_referred",
    name: "Shoulder-driven pain masquerading as neck pain (rotator cuff/AC/capsule)",
    base: 0.06,
    tests: [
      "Shoulder AROM/PROM + resisted testing; symptom reproduction with arm elevation",
      "C-spine tests: if neck does not modulate symptoms → consider shoulder source",
      "Compare shoulder provocation vs Spurling/distraction response",
    ],
  },

  systemic_inflammatory: {
    key: "systemic_inflammatory",
    name: "Systemic / inflammatory / serious non-MSK suspicion (screen & refer as needed)",
    base: 0.06,
    tests: [
      "Screen: night pain, fever/unwell, weight loss, cancer history, infection risk",
      "Inflammatory screen: morning stiffness >30 min, multi-joint pattern",
      "If suspicious → medical review ± labs/imaging",
    ],
  },

  // Base = 0 and only ranks if triage === 'red'
  acute_red_pathway: {
    key: "acute_red_pathway",
    name: "Urgent pathway (fracture/instability, vascular/CAD, cord signs, severe neuro)",
    base: 0.0,
    tests: [
      "Canadian C-Spine Rule / trauma imaging pathway if indicated",
      "Neuro exam incl. UMN signs; gait; progressive weakness",
      "If CAD/vascular symptoms suspected → urgent ED pathway",
    ],
  },
};

/* ----------------- helpers ----------------- */

const getOne = (answers: Answer[], id: string): string | undefined => {
  const a = answers.find(
    (x) => x.id === id && x.kind === "single"
  ) as Extract<Answer, { kind: "single" }> | undefined;
  return a?.value;
};

const getSlider = (answers: Answer[], id: string): number | undefined => {
  const a = answers.find(
    (x) => x.id === id && x.kind === "slider"
  ) as Extract<Answer, { kind: "slider" }> | undefined;
  return typeof a?.value === "number" ? a.value : undefined;
};

const yn = (v?: string) => (v ?? "").toLowerCase() === "yes";

/* ----------------- triage ----------------- */

function computeTriage(answers: Answer[]) {
  const notes: string[] = [];
  let triage: Triage = "green";

  // Canadian C-Spine quick checks (your Dart IDs)
  const age65 = yn(getOne(answers, "C_rf_age65plus"));
  const highSpeed = yn(getOne(answers, "C_rf_high_speed_crash"));
  const paresthesiaPost = yn(getOne(answers, "C_rf_paresthesia_post_incident"));
  const unableWalk = yn(getOne(answers, "C_rf_unable_walk_immediately"));
  const immediateNeckPain = yn(getOne(answers, "C_rf_immediate_neck_pain"));
  const rotLT45 = yn(getOne(answers, "C_rf_rotation_lt45_both"));

  // Other serious symptoms
  const majorTrauma = yn(getOne(answers, "C_rf_major_trauma"));
  const neuroDeficit = yn(getOne(answers, "C_rf_neuro_deficit"));
  const bladderBowel = yn(getOne(answers, "C_rf_bladder_bowel"));
  const cadCluster = yn(getOne(answers, "C_rf_cad_cluster"));

  // Systemic-ish screens (from questions UI)
  const nightPain = yn(getOne(answers, "C_night_pain"));
  const morningStiff30 = yn(getOne(answers, "C_morning_stiff_30"));
  const visualDisturbance = yn(getOne(answers, "C_visual_disturbance"));

  // ✅ NEW: gait/balance question
  const gaitUnsteady = yn(getOne(answers, "C_gait_unsteady"));

  // Force RED
  if (cadCluster) {
    notes.push("CAD/vascular symptom cluster reported");
    triage = "red";
  }
  if (bladderBowel) {
    notes.push("New bladder/bowel control issues");
    triage = "red";
  }
  if (neuroDeficit) {
    notes.push("Widespread neuro deficit / gait or hand clumsiness concern");
    triage = "red";
  }

  // ✅ NEW: conservative myelopathy-style escalation
  // (If they’ve endorsed hand clumsiness AND unsteady gait → treat as urgent screen)
  const handClumsy = yn(getOne(answers, "C_hand_clumsiness"));
  if (gaitUnsteady && handClumsy) {
    notes.push("Hand clumsiness + unsteady gait (possible cord involvement)");
    triage = "red";
  }

  // Trauma high-risk signals (kept conservative)
  if (age65 || highSpeed || paresthesiaPost) {
    notes.push("High-risk trauma factor (age≥65 / high-speed / paresthesias)");
    triage = "red";
  }

  // AMBER fallback (only if still green)
  if (
    triage === "green" &&
    (majorTrauma || unableWalk || immediateNeckPain || rotLT45)
  ) {
    notes.push("Trauma/ROM concern present (monitor; consider imaging rules)");
    triage = "amber";
  }

  // AMBER systemic/inflammatory signal (only if still green)
  if (triage === "green" && (nightPain || morningStiff30 || visualDisturbance)) {
    notes.push(
      nightPain
        ? "Night pain/waking"
        : morningStiff30
        ? "Morning stiffness >30 minutes"
        : "Visual disturbance reported"
    );
    triage = "amber";
  }

  // AMBER: gait unsteadiness alone (without the clumsy + gait combo) still deserves caution
  if (triage === "green" && gaitUnsteady) {
    notes.push("Unsteady gait/balance change (confirm neuro/UMN signs)");
    triage = "amber";
  }

  return { triage, notes };
}

/* ----------------- scoring ----------------- */

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

  // If RED → short-circuit acute pathway
  if (triage === "red") {
    S.acute_red_pathway.score = 999;
    S.acute_red_pathway.why.push("Red-flag criteria met");
    return S;
  }

  // Otherwise exclude acute pathway entirely
  S.acute_red_pathway.score = -Infinity;

  // Pull fields (your Dart IDs)
  const painLocation = (getOne(answers, "C_pain_location") ?? "central") as string; // central|one_side|both_sides
  const intoShoulder = yn(getOne(answers, "C_pain_into_shoulder"));
  const belowElbow = yn(getOne(answers, "C_pain_below_elbow"));
  const vasWorst = getSlider(answers, "C_vas_worst") ?? 0;
  const nightPain = yn(getOne(answers, "C_night_pain"));
  const morningStiff30 = yn(getOne(answers, "C_morning_stiff_30"));

  const armTingling = yn(getOne(answers, "C_arm_tingling"));
  const armWeakness = yn(getOne(answers, "C_arm_weakness"));
  const coughSneezeWorse = yn(getOne(answers, "C_cough_sneeze_worse"));
  const neckMovtWorse = yn(getOne(answers, "C_neck_movt_worse"));
  const handClumsy = yn(getOne(answers, "C_hand_clumsiness"));

  const headache = yn(getOne(answers, "C_headache_present"));
  const headacheOneSide = yn(getOne(answers, "C_headache_one_side"));
  const headacheWorseNeck = yn(getOne(answers, "C_headache_worse_with_neck"));
  const headacheBetterNeckCare = yn(
    getOne(answers, "C_headache_better_with_neck_care")
  );
  const visualDisturbance = yn(getOne(answers, "C_visual_disturbance"));

  // ✅ NEW
  const gaitUnsteady = yn(getOne(answers, "C_gait_unsteady"));

  const highPain = vasWorst >= 7;

  /* -------- Radiculopathy -------- */
  if (belowElbow) {
    S.cervical_radiculopathy.score += 0.28;
    S.cervical_radiculopathy.why.push("Symptoms radiate below the elbow");
  }
  if (armTingling) {
    S.cervical_radiculopathy.score += 0.18;
    S.cervical_radiculopathy.why.push("Tingling/numbness into arm/hand");
  }
  if (armWeakness) {
    S.cervical_radiculopathy.score += 0.18;
    S.cervical_radiculopathy.why.push("Arm/hand weakness reported");
  }
  if (coughSneezeWorse) {
    S.cervical_radiculopathy.score += 0.10;
    S.cervical_radiculopathy.why.push("Cough/sneeze aggravation (neural sensitivity)");
  }
  if (neckMovtWorse && (belowElbow || armTingling || armWeakness)) {
    S.cervical_radiculopathy.score += 0.10;
    S.cervical_radiculopathy.why.push("Neck movement modulates arm symptoms");
  }

  /* -------- Myelopathy (non-red cases) -------- */
  if (handClumsy) {
    S.cervical_myelopathy.score += 0.18;
    S.cervical_myelopathy.why.push("Hand clumsiness/dropping things");
  }
  if (handClumsy && (armWeakness || painLocation === "both_sides")) {
    S.cervical_myelopathy.score += 0.10;
    S.cervical_myelopathy.why.push("Bilateral/weakness context increases concern");
  }

  // ✅ NEW: gait/balance is a strong discriminator
  if (gaitUnsteady) {
    S.cervical_myelopathy.score += 0.26;
    S.cervical_myelopathy.why.push("Unsteady gait/balance change (cord screen priority)");
    // De-weight radic slightly if gait is positive but classic radic pattern isn't strong
    if (!belowElbow && !armTingling && !armWeakness) {
      S.cervical_radiculopathy.score -= 0.08;
    }
  }

  if (belowElbow && armTingling && !handClumsy && !gaitUnsteady) {
    S.cervical_myelopathy.score -= 0.06;
  }

  /* -------- Facet / capsular -------- */
  if (neckMovtWorse && !belowElbow && !armTingling && !armWeakness) {
    S.facet_cervical.score += 0.18;
    S.facet_cervical.why.push("Neck movement-provoked pain without neuro features");
  }
  if (painLocation === "one_side") {
    S.facet_cervical.score += 0.10;
    S.facet_cervical.why.push("Unilateral pain pattern (facet/capsular bias)");
  }

  /* -------- Mechanical non-specific -------- */
  if (neckMovtWorse) {
    S.mechanical_neck_pain.score += 0.16;
    S.mechanical_neck_pain.why.push("Movement-related neck pain");
  }
  if (!belowElbow && !armTingling && !armWeakness && !headache) {
    S.mechanical_neck_pain.score += 0.10;
    S.mechanical_neck_pain.why.push("No dominant neuro/headache pattern detected");
  }
  if (highPain) {
    S.mechanical_neck_pain.score += 0.06;
    S.mechanical_neck_pain.why.push("High pain intensity (track irritability/disability)");
  }

  /* -------- WAD / post-trauma (only if not triage red) -------- */
  const anyTraumaSignal =
    yn(getOne(answers, "C_rf_high_speed_crash")) ||
    yn(getOne(answers, "C_rf_major_trauma")) ||
    yn(getOne(answers, "C_rf_immediate_neck_pain")) ||
    yn(getOne(answers, "C_rf_unable_walk_immediately"));

  if (anyTraumaSignal) {
    S.whiplash_wad.score += 0.22;
    S.whiplash_wad.why.push("Trauma-related onset signals present");
    if (headache) {
      S.whiplash_wad.score += 0.08;
      S.whiplash_wad.why.push("Headache in a post-trauma context");
    }
    if (visualDisturbance) {
      S.whiplash_wad.score += 0.06;
      S.whiplash_wad.why.push("Visual symptoms (screen vestibular/oculomotor)");
    }
  }

  /* -------- Headache buckets -------- */
  if (headache) {
    if (headacheOneSide) {
      S.cervicogenic_headache.score += 0.10;
      S.cervicogenic_headache.why.push("Unilateral headache");
    }
    if (headacheWorseNeck) {
      S.cervicogenic_headache.score += 0.20;
      S.cervicogenic_headache.why.push("Headache worsens with neck movement/posture");
    }
    if (headacheBetterNeckCare) {
      S.cervicogenic_headache.score += 0.18;
      S.cervicogenic_headache.why.push("Headache improves with neck positions/treatment");
    }
    if (!headacheWorseNeck && !headacheBetterNeckCare) {
      S.primary_headache.score += 0.14;
      S.primary_headache.why.push("Headache not clearly modulated by the neck");
    }
  }

  if (headache && !headacheWorseNeck && !headacheBetterNeckCare) {
    S.primary_headache.score += 0.12;
  }
  if (visualDisturbance && headache && !headacheWorseNeck) {
    S.primary_headache.score += 0.06;
    S.primary_headache.why.push("Visual disturbance with headache (non-neck pattern possible)");
  }

  /* -------- Myofascial trigger points -------- */
  if (intoShoulder && !belowElbow && !armTingling && !armWeakness) {
    S.myofascial_trigger_points.score += 0.14;
    S.myofascial_trigger_points.why.push("Shoulder/upper arm referral without neuro distribution");
  }
  if (neckMovtWorse && headache) {
    S.myofascial_trigger_points.score += 0.06;
    S.myofascial_trigger_points.why.push(
      "Neck pain + headache (suboccipital/upper trap referral possible)"
    );
  }

  /* -------- Shoulder masquerader (tuned) -------- */
  if (
    intoShoulder &&
    !neckMovtWorse &&
    !armTingling &&
    !armWeakness &&
    !belowElbow
  ) {
    S.shoulder_referred.score += 0.26;
    S.shoulder_referred.why.push(
      "Shoulder/upper arm pain without neck modulation or neuro signs"
    );
  }

  if (intoShoulder && neckMovtWorse) {
    S.shoulder_referred.score -= 0.02;
  }

  /* -------- Systemic / inflammatory -------- */
  if (nightPain) {
    S.systemic_inflammatory.score += 0.14;
    S.systemic_inflammatory.why.push("Night pain/waking (screen systemic causes)");
  }
  if (morningStiff30) {
    S.systemic_inflammatory.score += 0.16;
    S.systemic_inflammatory.why.push("Morning stiffness >30 min (inflammatory screen)");
  }
  if (nightPain && morningStiff30) {
    S.systemic_inflammatory.score += 0.06;
    S.systemic_inflammatory.why.push("Combined night pain + prolonged morning stiffness");
  }

  /* -------- Guards -------- */
  if (belowElbow || armTingling || armWeakness) {
    S.facet_cervical.score -= 0.06;
  }
  if (headacheWorseNeck || headacheBetterNeckCare) {
    S.primary_headache.score -= 0.06;
  }

  return S;
}

/* ----------------- summary builder ----------------- */

function buildSummary(answers: Answer[]) {
  const { triage, notes } = computeTriage(answers);
  const scored = score(answers, triage);

  const ranked = (Object.keys(scored) as Differential[])
    .filter((k) => (triage === "red" ? true : k !== "acute_red_pathway"))
    .map((k) => ({ key: k, ...scored[k] }))
    .sort(
      (a, b) => b.score - a.score || diffs[b.key].base - diffs[a.key].base
    );

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
          "Urgent pathway per red flags (imaging / ED / specialist as appropriate)",
          "Neuro exam incl UMN signs; gait assessment; progressive weakness screen",
          "Consider Canadian C-Spine Rule / trauma imaging if applicable",
        ]
      : [
          "Cervical AROM/PROM + symptom modulation check",
          "Brief neuro screen if any arm symptoms (myotomes/reflexes/dermatomes)",
          "Screen shoulder if pain localises to shoulder/arm without neck modulation",
        ];

  const clinicalToDo = Array.from(
    new Set([...globalTests, ...top.flatMap((t) => t.objectiveTests)])
  );

  return {
    region: "Cervical spine",
    triage,
    redFlagNotes: triage === "green" ? [] : notes,
    topDifferentials: top.map((t) => ({ name: t.name, score: t.score })),
    clinicalToDo,
    detailedTop: top,
  };
}

/* ----------------- callable ----------------- */

  export async function processCervicalAssessmentCore(
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
          triageRegion: "cervical",
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
export const processCervicalAssessment = functions
  .region("europe-west1")
  .https.onCall(async (data, ctx) => {
    return processCervicalAssessmentCore(data, ctx);
  });