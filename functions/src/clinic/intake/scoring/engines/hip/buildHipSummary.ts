/* Hip Region – callable scoring + summary (europe-west1, v1 API) */
import * as functions from "firebase-functions/v1";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

const db = getFirestore();

type Triage = "green" | "amber" | "red";
type Answer =
  | { id: string; kind: "single"; value: string }
  | { id: string; kind: "multi"; values: string[] }
  | { id: string; kind: "slider"; value: number };

type Differential =
  | "intra_articular"
  | "gtps"
  | "adductor_iliopsoas"
  | "referred_lumbar_sij"
  | "hip_oa"
  | "hip_instability"
  | "ifi"
  | "dgs"
  | "snapping_hip"
  | "pubalgia"
  | "hamstring_tendinopathy"
  | "acute_red_pathway";

interface DiffInfo {
  key: Differential;
  name: string;
  base: number;
  tests: string[];
}

const diffs: Record<Differential, DiffInfo> = {
  intra_articular: {
    key: "intra_articular",
    name: "Symptomatic intra-articular hip (FAI/labrum/chondral/capsular)",
    base: 0.2,
    tests: [
      "FADDIR / flex-IR / quadrant (scour)",
      "Passive IR @90°; note crepitus/catch",
      "Q-CIGAR variables (groin pain, crepitus, stiffness)",
    ],
  },
  gtps: {
    key: "gtps",
    name: "Greater Trochanteric Pain Syndrome (gluteal tendinopathy)",
    base: 0.18,
    tests: [
      "Point tenderness at greater trochanter",
      "External derotation / resisted abduction",
      "30s single-leg stance (pain reproduction)",
    ],
  },
  adductor_iliopsoas: {
    key: "adductor_iliopsoas",
    name: "Adductor / Iliopsoas-related groin pain",
    base: 0.16,
    tests: [
      "Squeeze test (resisted adduction)",
      "Resisted hip flexion; palpation adductor/iliopsoas",
    ],
  },
  referred_lumbar_sij: {
    key: "referred_lumbar_sij",
    name: "Referred lumbar/SIJ",
    base: 0.1,
    tests: [
      "Lumbar ROM, PA’s, neuro screen",
      "SIJ provocation cluster as indicated",
    ],
  },

  // -------- new differentials (expanded hip set) --------

  hip_oa: {
    key: "hip_oa",
    name: "Hip osteoarthritis (degenerative hip joint pain)",
    base: 0.12,
    tests: [
      "Hip PROM with overpressure; note capsular pattern / end-range pain",
      "Markedly restricted IR (esp. at 90° flexion)",
      "FABER / Scour (pain/crepitus) + gait assessment",
    ],
  },
  hip_instability: {
    key: "hip_instability",
    name: "Hip instability / dysplasia (microinstability spectrum)",
    base: 0.08,
    tests: [
      "Log roll (excessive ER / apprehension)",
      "Dial test (excessive passive ER/recoil suggests laxity)",
      "Apprehension / prone extension-ER (HEER/AB-HEER style) as indicated",
    ],
  },
  ifi: {
    key: "ifi",
    name: "Ischiofemoral impingement (deep buttock/ischiofemoral space)",
    base: 0.05,
    tests: [
      "IFI provocation: hip extension + adduction (± ER/IR) reproduces deep buttock pain",
      "Palpation deep to gluteals / quadratus femoris region (as tolerated)",
      "Consider imaging if high suspicion and persistent",
    ],
  },
  dgs: {
    key: "dgs",
    name: "Deep gluteal syndrome (piriformis/deep rotator-related sciatic irritation)",
    base: 0.07,
    tests: [
      "FAIR test (flex/add/IR reproduces buttock ± leg symptoms)",
      "Pace / resisted abduction-ER (buttock pain/weakness)",
      "Palpation at sciatic notch/piriformis + neuro screen to exclude lumbar radic",
    ],
  },
  snapping_hip: {
    key: "snapping_hip",
    name: "Snapping hip syndrome (internal iliopsoas / external ITB / intra-articular)",
    base: 0.05,
    tests: [
      "Dynamic reproduction: hip flexion→extension (palpate iliopsoas or ITB over trochanter)",
      "Thomas-style movement (hip flexed/abd/ER to extension/add) to provoke internal snap",
      "If painful mechanical locking/catching → consider intra-articular source",
    ],
  },
  pubalgia: {
    key: "pubalgia",
    name: "Athletic pubalgia / core-related groin pain (inguinal/pubic plate spectrum)",
    base: 0.09,
    tests: [
      "Resisted sit-up / trunk flexion (groin/pubic pain reproduction)",
      "Palpation pubic tubercle / distal rectus-adductor aponeurosis",
      "Squeeze test may reproduce pubic/inguinal pain (overlap with adductor)",
    ],
  },
  hamstring_tendinopathy: {
    key: "hamstring_tendinopathy",
    name: "Proximal hamstring tendinopathy (ischial tuberosity pain)",
    base: 0.09,
    tests: [
      "Palpation at ischial tuberosity (prox hamstring origin)",
      "Bent-knee stretch / modified bent-knee stretch (pain reproduction)",
      "Resisted knee flexion (at hip flexion) / single-leg RDL tolerance",
    ],
  },

  // Base = 0 and only ranks if triage === 'red'
  acute_red_pathway: {
    key: "acute_red_pathway",
    name: "Suspected fracture/dislocation or septic hip/SUFE",
    base: 0.0,
    tests: [
      "Urgent imaging (X-ray ± aspiration/labs as indicated)",
      "Neurovascular status; temperature; inability to WB",
      "Urgent ortho if SUFE suspected (<16y)",
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

const getMany = (answers: Answer[], id: string): string[] => {
  const a = answers.find(
    (x) => x.id === id && x.kind === "multi"
  ) as Extract<Answer, { kind: "multi" }> | undefined;
  return Array.isArray(a?.values) ? a.values : [];
};

const yn = (v?: string) => (v ?? "").toLowerCase() === "yes";

/* ----------------- triage ----------------- */

function computeTriage(answers: Answer[]) {
  const notes: string[] = [];
  let triage: Triage = "green";

  // Red-flag cluster (IDs from transcript)
  const highEnergy = yn(getOne(answers, "H_rf_high_energy")); // Q1 high-speed
  const fallImpact = yn(getOne(answers, "H_rf_fall_impact")); // Q1 fall onto hip
  const cantWB = yn(getOne(answers, "H_rf_cant_weightbear")); // Q2 can't WB
  const fever = yn(getOne(answers, "H_rf_fever")); // Q3
  const tinyAgony = yn(getOne(answers, "H_rf_tiny_movement_agony")); // Q4
  const sufeUnder16 = yn(getOne(answers, "H_rf_under16_new_limp")); // Q5
  const caHistory = yn(getOne(answers, "H_rf_cancer_history")); // Q6
  const amberRisks = getMany(answers, "H_rf_amber_risks"); // Q7 diabetes/steroids/immuno

  // Force RED
  if (sufeUnder16) {
    notes.push("Under 16 with new limp/pain (SUFE risk)");
    triage = "red";
  }
  if (cantWB) {
    notes.push("Unable to weight-bear");
    triage = "red";
  }
  if (highEnergy) {
    notes.push("High-energy mechanism");
    triage = "red";
  }
  if (fever && tinyAgony) {
    notes.push("Fever + severe pain on tiny movement");
    triage = "red";
  }

  // AMBER fallback (only if still green)
  if (triage === "green" && (fallImpact || fever)) {
    notes.push(
      fallImpact ? "Fall/impact onto hip" : "Fever without tiny-movement agony"
    );
    triage = "amber";
  }
  if (triage === "green" && (caHistory || amberRisks.length > 0)) {
    notes.push(
      "Systemic risk factor(s) (cancer/immunosuppression/steroids/diabetes)"
    );
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

  // Pull fields (core)
  const onset = (getOne(answers, "H_onset") ?? "") as string; // acute_clear/gradual/appeared/woke
  const where = getMany(answers, "H_where"); // groin/buttock/lateral/thigh/knee/lowback/unsure
  const aggs = getMany(answers, "H_aggs"); // expanded in Dart
  const feels = getMany(answers, "H_feats"); // expanded in Dart
  const sleep = (getOne(answers, "H_sleep") ?? "") as string; // none/wakes_side/major
  const walk = (getOne(answers, "H_walk") ?? "") as string; // normal/limp/support/cant
  const irritOn = (getOne(answers, "H_irrit_on") ?? "") as string; // instant/mins/later/always
  const settle = (getOne(answers, "H_irrit_off") ?? "") as string; // secs/mins/hours/nextday

  // New single yes/no discriminators (from updated Dart)
  const hxDysplasia = yn(getOne(answers, "H_hx_dysplasia"));
  const hxHypermobility = yn(getOne(answers, "H_hx_hypermobility"));
  const neuroPinsNeedles = yn(getOne(answers, "H_neuro_pins_needles"));
  const featCoughStrain = yn(getOne(answers, "H_feat_cough_strain"));
  const featReproSnap = yn(getOne(answers, "H_feat_reproducible_snap"));
  const featSitBone = yn(getOne(answers, "H_feat_sitbone"));

  // Convenience flags (same style as existing)
  const hasLateral = where.includes("lateral");
  const hasLoadAggs = aggs.includes("stairs") || aggs.includes("stand_walk");
  const hasSideLyingAgg = aggs.includes("side-lying") || sleep === "wakes_side";

  // Intra-articular signals
  if (where.includes("groin")) {
    S.intra_articular.score += 0.3;
    S.intra_articular.why.push("Groin-dominant pain");
  }
  if (aggs.includes("sitting") || aggs.includes("deep_flex") || aggs.includes("car_chair")) {
    S.intra_articular.score += 0.2;
    S.intra_articular.why.push("Sitting/deep flexion or car/chair aggravation");
  }
  if (
    feels.some((f) =>
      ["click", "catch", "giveway", "crepitus"].includes(f)
    )
  ) {
    S.intra_articular.score += 0.22;
    S.intra_articular.why.push(
      "Mechanical symptoms (click/catch/give-way/crepitus)"
    );
  }
  if (feels.includes("stiffness")) {
    S.intra_articular.score += 0.08;
    S.intra_articular.why.push("Stiff after sitting / morning");
  }

  // GTPS signals
  if (hasLateral) {
    S.gtps.score += 0.3;
    S.gtps.why.push("Lateral hip pain over greater trochanter");
    if (hasLoadAggs || hasSideLyingAgg) {
      S.gtps.score += 0.22;
      S.gtps.why.push("Stairs/standing/side-lying pain");
    }
  } else {
    if (hasLoadAggs) {
      S.gtps.score += 0.06;
      S.gtps.why.push("Non-specific load pain (weak GTPS signal)");
    }
    if (hasSideLyingAgg) {
      S.gtps.score += 0.1;
      S.gtps.why.push("Side-lying disturbance (weak GTPS signal)");
    }
  }

  // Adductor / Iliopsoas
  if (aggs.includes("kick_sprint") || feels.includes("sport_burn")) {
    S.adductor_iliopsoas.score += 0.3;
    S.adductor_iliopsoas.why.push(
      "Kicking/sprinting/change of direction pain"
    );
  }
  if (onset === "acute_clear") {
    S.adductor_iliopsoas.score += 0.12;
    S.adductor_iliopsoas.why.push("Clear acute onset with movement");
  }

  // Referred lumbar/SIJ
  if (where.includes("lowback") || where.includes("buttock")) {
    S.referred_lumbar_sij.score += 0.18;
    S.referred_lumbar_sij.why.push("Posterior/low-back/SIJ area symptoms");
  }
  if (irritOn === "later" || settle === "nextday") {
    S.referred_lumbar_sij.score += 0.08;
    S.referred_lumbar_sij.why.push(
      "Irritability pattern consistent with referred source"
    );
  }
  if (neuroPinsNeedles) {
    S.referred_lumbar_sij.score += 0.16;
    S.referred_lumbar_sij.why.push("Pins/needles or numbness suggests neural involvement");
  }

  // -------- new scoring blocks (use new Dart inputs) --------

  // Hip OA (degenerative hip joint pain)
  if (where.includes("groin") || where.includes("knee")) {
    S.hip_oa.score += 0.22;
    S.hip_oa.why.push("Groin/knee pattern consistent with hip joint referral");
  }
  if (feels.includes("stiffness")) {
    S.hip_oa.score += 0.14;
    S.hip_oa.why.push("Stiffness feature consistent with OA/degenerative joint pain");
  }
  if (hasLoadAggs) {
    S.hip_oa.score += 0.12;
    S.hip_oa.why.push("Weight-bearing aggravation (walking/stairs)");
  }
  if (onset === "gradual" || onset === "woke" || onset === "appeared") {
    S.hip_oa.score += 0.06;
    S.hip_oa.why.push("Non-traumatic onset pattern");
  }
  if (feels.includes("crepitus")) {
    S.hip_oa.score += 0.06;
    S.hip_oa.why.push("Crepitus feature supports degenerative changes");
  }

  // Hip instability / dysplasia (microinstability)
  if (hxDysplasia) {
    S.hip_instability.score += 0.28;
    S.hip_instability.why.push("Known hip dysplasia / shallow socket history");
  }
  if (hxHypermobility) {
    S.hip_instability.score += 0.18;
    S.hip_instability.why.push("General hypermobility can increase instability risk");
  }
  if (where.includes("groin")) {
    S.hip_instability.score += 0.12;
    S.hip_instability.why.push("Anterior/groin symptoms consistent with instability spectrum");
  }
  if (feels.includes("giveway")) {
    S.hip_instability.score += 0.22;
    S.hip_instability.why.push("Giving-way sensation consistent with instability");
  }
  if (feels.includes("click") || feels.includes("catch")) {
    S.hip_instability.score += 0.08;
    S.hip_instability.why.push("Mechanical symptoms may co-exist with instability (labrum/capsule)");
  }
  if (aggs.includes("kick_sprint") || aggs.includes("hill_running")) {
    S.hip_instability.score += 0.06;
    S.hip_instability.why.push("Sport/hills may unmask instability symptoms");
  }

  // Ischiofemoral impingement (IFI)
  if (where.includes("buttock")) {
    S.ifi.score += 0.1;
    S.ifi.why.push("Deep buttock pain (consider IFI in posterior hip)");
  }
  if (aggs.includes("long_stride")) {
    S.ifi.score += 0.26;
    S.ifi.why.push("Long-stride/hip extension aggravation (IFI signal)");
  }
  if (aggs.includes("stand_walk")) {
    S.ifi.score += 0.06;
    S.ifi.why.push("Walking/standing aggravation consistent with posterior hip loading");
  }

  // Deep gluteal syndrome (DGS)
  if (where.includes("buttock") && aggs.includes("sitting")) {
    S.dgs.score += 0.24;
    S.dgs.why.push("Buttock pain + sitting aggravation (deep gluteal syndrome signal)");
  } else {
    if (where.includes("buttock")) {
      S.dgs.score += 0.08;
      S.dgs.why.push("Buttock pain (consider DGS if lumbar ruled out)");
    }
    if (aggs.includes("sitting")) {
      S.dgs.score += 0.06;
      S.dgs.why.push("Sitting aggravation (consider deep gluteal factors)");
    }
  }
  if (neuroPinsNeedles && where.includes("buttock")) {
    S.dgs.score += 0.14;
    S.dgs.why.push("Neural symptoms with buttock pain (deep gluteal syndrome possible)");
  }
  if (aggs.includes("hard_seat")) {
    S.dgs.score += 0.1;
    S.dgs.why.push("Hard seat aggravation (compression-sensitive posterior hip)");
  }

  // Snapping hip syndrome
  if (feels.includes("snap")) {
    S.snapping_hip.score += 0.26;
    S.snapping_hip.why.push("Snapping/clunk feature reported");
  }
  if (featReproSnap) {
    S.snapping_hip.score += 0.22;
    S.snapping_hip.why.push("Reproducible snap/clunk with movement");
  }
  if (feels.includes("click")) {
    S.snapping_hip.score += 0.08;
    S.snapping_hip.why.push("Clicking may represent snapping (consider dynamic reproduction)");
  }
  // If strong intra-articular “catch/lock”, keep snapping modest (often overlaps)
  if (feels.includes("catch")) {
    S.snapping_hip.score += 0.04;
    S.snapping_hip.why.push("Catching suggests possible intra-articular component");
  }

  // Athletic pubalgia / core-related groin pain
  if (where.includes("groin") && (aggs.includes("sit_up") || featCoughStrain || aggs.includes("cough_strain"))) {
    S.pubalgia.score += 0.3;
    S.pubalgia.why.push("Groin pain aggravated by core work or coughing/straining");
  } else if (where.includes("groin") && aggs.includes("kick_sprint")) {
    // If sport-related but no core/cough signal, keep smaller (overlaps with adductor)
    if (onset !== "acute_clear") {
      S.pubalgia.score += 0.14;
      S.pubalgia.why.push("Sport-related groin pain with non-acute onset (pubalgia possible)");
    } else {
      S.pubalgia.score += 0.06;
      S.pubalgia.why.push("Groin + sport load (overlap; adductor also likely)");
    }
  }

  // Proximal hamstring tendinopathy
  if (featSitBone || feels.includes("sit_bone")) {
    S.hamstring_tendinopathy.score += 0.3;
    S.hamstring_tendinopathy.why.push("Sit-bone focused pain (proximal hamstring signal)");
  }
  if ((where.includes("buttock") || where.includes("thigh")) && aggs.includes("sitting")) {
    S.hamstring_tendinopathy.score += 0.2;
    S.hamstring_tendinopathy.why.push("Posterior/buttock-thigh pain + sitting aggravation");
  }
  if (aggs.includes("hill_running") || aggs.includes("kick_sprint") || feels.includes("sport_burn")) {
    S.hamstring_tendinopathy.score += 0.1;
    S.hamstring_tendinopathy.why.push("Acceleration/hills/sprinting load can implicate hamstring origin");
  }
  if (aggs.includes("hard_seat")) {
    S.hamstring_tendinopathy.score += 0.08;
    S.hamstring_tendinopathy.why.push("Hard seat aggravation (compression at ischial tuberosity)");
  }
  if (onset === "gradual") {
    S.hamstring_tendinopathy.score += 0.06;
    S.hamstring_tendinopathy.why.push("Gradual onset supports tendinopathy pattern");
  }

  // --------- overlap guards (avoid double-counting too hard) ---------

  // If clear neural symptoms, keep DGS/referred higher than IFI by default
  if (neuroPinsNeedles) {
    S.ifi.score -= 0.04;
  }

  // If clear lateral pattern with side-lying, keep pubalgia/hamstring modest
  if (hasLateral && hasSideLyingAgg) {
    S.pubalgia.score -= 0.04;
    S.hamstring_tendinopathy.score -= 0.04;
  }

  // Disability bump (mild)
  if (walk === "support" || walk === "limp") {
    S.intra_articular.score += 0.05;
    S.referred_lumbar_sij.score += 0.05;
    S.hip_oa.score += 0.05;
  }

  return S;
}

/* ----------------- summary builder ----------------- */

function buildSummary(answers: Answer[]) {
  const { triage, notes } = computeTriage(answers);
  const scored = score(answers, triage);

  const sideValue = getOne(answers, "H_side") || "";
  const sideLabel = sideValue ? `Hip (${sideValue})` : "Hip";

  const ranked = (Object.keys(scored) as Differential[])
    .filter((k) => (triage === "red" ? true : k !== "acute_red_pathway"))
    .map((k) => ({ key: k, ...scored[k] }))
    .sort(
      (a, b) =>
        b.score - a.score || diffs[b.key].base - diffs[a.key].base
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
          "Urgent imaging (X-ray ± aspiration/labs as indicated)",
          "Neurovascular status; temperature; inability to WB",
          "Urgent ortho if SUFE suspected",
        ]
      : [
          "Hip AROM/PROM; irritability at end-range",
          "Gait assessment; single-leg stance",
          "Lumbar/SIJ screen if posterior features",
        ];

  const clinicalToDo = Array.from(
    new Set([...globalTests, ...top.flatMap((t) => t.objectiveTests)])
  );

  return {
    region: sideLabel,
    triage,
    redFlagNotes: triage === "green" ? [] : notes,
    topDifferentials: top.map((t) => ({ name: t.name, score: t.score })),
    clinicalToDo,
    detailedTop: top,
  };
}

/* ----------------- callable ----------------- */

export const processHipAssessment = functions
  .region("europe-west1")
  .https.onCall(async (data, _ctx) => {
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
          triageRegion: "hip",
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