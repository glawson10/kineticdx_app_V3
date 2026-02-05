/* Ankle/Foot Region – callable scoring + summary (europe-west1, v1 API) */
import * as functions from "firebase-functions/v1";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

const db = getFirestore();

type Triage = "green" | "amber" | "red";
type Answer =
  | { id: string; kind: "single"; value: string }
  | { id: string; kind: "multi"; values: string[] }
  | { id: string; kind: "slider"; value: number };

type Differential =
  | "lateral_sprain"
  | "syndesmosis"
  | "acute_fracture"
  | "achilles_injury"
  | "plantar_fascia"
  | "midfoot_lisfranc"
  | "chronic_instability"
  | "peroneal_tendon"
  | "tarsal_tunnel"
  | "olt_talus"
  | "stress_fracture"
  | "posterior_tibialis"
  | "forefoot_neuroma"
  | "inflammatory_infection"
  | "achilles_rupture_urgent";

interface DiffInfo {
  key: Differential;
  name: string;
  base: number;
  tests: string[];
}

const diffs: Record<Differential, DiffInfo> = {
  lateral_sprain: {
    key: "lateral_sprain",
    name: "Lateral ankle sprain (ATFL/CFL) / lateral ligament complex",
    base: 0.4,
    tests: [
      "Palpate ATFL/CFL; assess swelling/bruising pattern",
      "Anterior drawer (ATFL) + talar tilt (CFL) (as tolerated)",
      "Single-leg balance + hop/step-down (later phase)",
    ],
  },
  syndesmosis: {
    key: "syndesmosis",
    name: "Syndesmosis (“high ankle”) sprain",
    base: 0.35,
    tests: [
      "Squeeze test (tibia/fibula compression)",
      "External rotation stress test / dorsiflexion-compression test",
      "Assess fibular tenderness + swelling; pain with WB push-off",
    ],
  },
  acute_fracture: {
    key: "acute_fracture",
    name: "Acute fracture / bony injury (Ottawa-positive pattern)",
    base: 0.0,
    tests: [
      "Ottawa Ankle/Foot Rules screening (malleoli/midfoot + 4 steps)",
      "Neurovascular screen; deformity check",
      "Urgent imaging if Ottawa-positive / deformity / neuro symptoms",
    ],
  },
  achilles_injury: {
    key: "achilles_injury",
    name: "Achilles tendinopathy / paratenon / partial tear (non-rupture)",
    base: 0.25,
    tests: [
      "Single-leg heel raise capacity (pain/strength) (as tolerated)",
      "Palpation + pain on hopping/loaded DF (if safe)",
      "Assess calf strength/endurance; ROM and tendon thickening",
    ],
  },
  plantar_fascia: {
    key: "plantar_fascia",
    name: "Plantar fasciopathy (heel pain) / plantar fascia overload",
    base: 0.2,
    tests: [
      "Windlass test (great toe extension → medial heel pain)",
      "Palpate medial calcaneal tubercle / proximal fascia",
      "Single-leg calf raise + foot intrinsic strength screen",
    ],
  },
  midfoot_lisfranc: {
    key: "midfoot_lisfranc",
    name: "Midfoot sprain / Lisfranc complex injury (rule-in/out)",
    base: 0.2,
    tests: [
      "Midfoot squeeze/compression; piano-key test (1st/2nd rays)",
      "Single-leg heel raise (avoid if severe/acute suspicion)",
      "Plantar ecchymosis + midfoot instability signs → imaging",
    ],
  },
  chronic_instability: {
    key: "chronic_instability",
    name: "Chronic ankle instability (recurrent sprains/giving-way)",
    base: 0.18,
    tests: [
      "Balance/proprioception testing (SEBT/Y-balance if available)",
      "Hop tests + landing control (later stage)",
      "Anterior drawer/talar tilt (ligament laxity context)",
    ],
  },

  // ✅ NEW DIFFERENTIALS (with embedded tests)
  peroneal_tendon: {
    key: "peroneal_tendon",
    name: "Peroneal tendon overload/tear/subluxation (lateral tendon pain)",
    base: 0.12,
    tests: [
      "Resisted eversion (pain/weakness), palpate peroneals behind fibula",
      "Single-leg heel raise + assess for painful snapping/subluxation",
      "Observe for swelling along tendon sheath; provocative cutting/landing",
    ],
  },
  tarsal_tunnel: {
    key: "tarsal_tunnel",
    name: "Tarsal tunnel / tibial nerve irritation (plantar neural symptoms)",
    base: 0.1,
    tests: [
      "Tinel’s at tarsal tunnel; provocation with prolonged WB",
      "Neuro screen: plantar sensation + symptoms reproduction",
      "Differentiate from plantar fascia (first-step pattern vs burning/rest)",
    ],
  },
  olt_talus: {
    key: "olt_talus",
    name: "Osteochondral lesion of talus (persistent deep ankle pain/catch)",
    base: 0.1,
    tests: [
      "Deep ankle joint line tenderness; catching/locking history",
      "Assess DF/plantarflexion end-range pain + swelling persistence",
      "Consider imaging if persistent post-sprain pain > 6 weeks",
    ],
  },
  stress_fracture: {
    key: "stress_fracture",
    name: "Stress fracture / bony stress injury (creeping onset, load pain)",
    base: 0.12,
    tests: [
      "Hop test / percussion (if safe) + focal bony tenderness mapping",
      "Night/rest pain and progressive load intolerance screen",
      "Consider imaging if suspected; relative rest/load modification trial",
    ],
  },
  posterior_tibialis: {
    key: "posterior_tibialis",
    name: "Posterior tibialis tendinopathy (medial arch/ankle overload)",
    base: 0.1,
    tests: [
      "Single-leg heel raise (inversion bias) pain/weakness",
      "Navicular drop / arch height + too-many-toes sign (if present)",
      "Palpate posterior tibialis tendon course behind medial malleolus",
    ],
  },
  forefoot_neuroma: {
    key: "forefoot_neuroma",
    name: "Interdigital neuroma (forefoot pain/tingling, shoe compression)",
    base: 0.1,
    tests: [
      "Mulder’s squeeze (click/paresthesia reproduction)",
      "Metatarsal squeeze test; assess footwear compression effect",
      "Differentiate from MTP synovitis/stress injury",
    ],
  },

  // Urgent-only ranking
  inflammatory_infection: {
    key: "inflammatory_infection",
    name: "Hot swollen joint / infection / inflammatory flare (urgent pathway)",
    base: 0.0,
    tests: [
      "Temperature, erythema, severe pain + fever/unwell screen",
      "Urgent medical review ± labs/imaging as indicated",
      "Do not load-test aggressively; prioritize escalation",
    ],
  },
  achilles_rupture_urgent: {
    key: "achilles_rupture_urgent",
    name: "Suspected Achilles rupture (urgent pathway)",
    base: 0.0,
    tests: [
      "Thompson test + resting angle comparison",
      "Palpable gap + inability to single-leg heel raise",
      "Urgent imaging/ortho referral pathway as per local protocol",
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
  let force: Differential | null = null;

  const fromMech = yn(getOne(answers, "A_rf_fromFallTwistLanding"));
  const followUps = getMany(answers, "A_rf_followUps");
  const walk4 = (getOne(answers, "A_rf_walk4Now") ?? "").toLowerCase(); // yes/barely/no
  const highSwelling = yn(getOne(answers, "A_rf_highSwelling"));
  const hotRedFever = yn(getOne(answers, "A_rf_hotRedFever"));
  const calfHotTight = yn(getOne(answers, "A_rf_calfHotTight"));
  const tiptoes = (getOne(answers, "A_rf_tiptoes") ?? "").toLowerCase(); // yes/partial/notatall

  const fourStepsImmediateFail = followUps.includes("fourStepsImmediate");
  const deformity = followUps.includes("deformity");
  const neuro = followUps.includes("numbPins");
  const popHeard = followUps.includes("popHeard");

  // RED 1: infection/inflammatory
  if (hotRedFever) {
    notes.push("Red-hot swollen ankle/foot with systemic symptoms");
    triage = "red";
    force = "inflammatory_infection";
    return { triage, notes, force };
  }

  // RED 2: Achilles rupture
  if (tiptoes === "notatall" && (popHeard || deformity)) {
    notes.push("Tiptoe impossible with pop/deformity → Achilles rupture concern");
    triage = "red";
    force = "achilles_rupture_urgent";
    return { triage, notes, force };
  }

  // Fracture suspicion: Ottawa-positive style
  if ((fourStepsImmediateFail || walk4 === "no") && fromMech) {
    notes.push("Unable to take 4 steps after injury / now with trauma (Ottawa-positive pattern)");
    triage = deformity || neuro ? "red" : "amber";
    if (triage === "red") force = "acute_fracture";
    return { triage, notes, force };
  }

  // High swelling + 4-step difficulty → amber
  if (highSwelling && (walk4 === "no" || walk4 === "barely") && fromMech) {
    notes.push("High swelling with 4-step difficulty after injury");
    triage = "amber";
  }

  // DVT-type screen proxy (kept amber)
  if (calfHotTight) {
    notes.push("Calf hot/tight after immobilisation/surgery – medical review advised");
    triage = "amber";
  }

  return { triage, notes, force };
}

/* ----------------- scoring ----------------- */

function score(answers: Answer[], triage: Triage) {
  const S: Record<Differential, { score: number; why: string[] }> = (
    Object.keys(diffs) as Differential[]
  ).reduce((acc, k) => {
    acc[k] = { score: diffs[k].base, why: [] };
    return acc;
  }, {} as Record<Differential, { score: number; why: string[] }>);

  // Pull fields
  const mech = getOne(answers, "A_mech") ?? ""; // inversionRoll/footFixedTwist/hardLanding/gradual
  const painSite = getMany(answers, "A_painSite"); // lateralATFL/syndesmosisHigh/achilles/plantar/midfoot/...
  const loadAggs = getMany(answers, "A_loadAggs"); // firstStepsWorse/stairsHillsTiptoe/cuttingLanding/throbsAtRest/...
  const onsetStyle = getOne(answers, "A_onsetStyle") ?? ""; // explosive/creeping/recurrent
  const timeSince = getOne(answers, "A_timeSince") ?? ""; // <48h/2–14d/2–6wk/>6wk
  const instability = getOne(answers, "A_instability") ?? ""; // never/sometimes/often
  const impact = getSlider(answers, "A_impactScore") ?? 0;

  const followUps = getMany(answers, "A_rf_followUps");
  const walk4 = (getOne(answers, "A_rf_walk4Now") ?? "").toLowerCase();
  const fromMech = yn(getOne(answers, "A_rf_fromFallTwistLanding"));
  const highSwelling = yn(getOne(answers, "A_rf_highSwelling"));
  const tiptoes = (getOne(answers, "A_rf_tiptoes") ?? "").toLowerCase();

  const fourStepFail = walk4 === "no" || followUps.includes("fourStepsImmediate");
  const deformity = followUps.includes("deformity");
  const neuro = followUps.includes("numbPins");

  // --------- LOCATION GATING (reduces irrelevant top-3 noise) ---------
  if (!painSite.includes("lateralATFL") && mech !== "inversionRoll") S.lateral_sprain.score -= 0.25;
  if (!painSite.includes("syndesmosisHigh") && !highSwelling && mech !== "footFixedTwist") S.syndesmosis.score -= 0.2;
  if (!painSite.includes("plantar")) {
    S.plantar_fascia.score -= 0.15;
    S.tarsal_tunnel.score -= 0.1;
  }
  if (!painSite.includes("achilles")) S.achilles_injury.score -= 0.15;
  if (!painSite.includes("midfoot")) {
    S.midfoot_lisfranc.score -= 0.15;
    S.stress_fracture.score -= 0.05;
  }
  if (instability !== "often" && onsetStyle !== "recurrent") S.chronic_instability.score -= 0.1;

  // --------- LATERAL SPRAIN ---------
  if (mech === "inversionRoll") {
    S.lateral_sprain.score += 0.7;
    S.lateral_sprain.why.push("Inversion roll mechanism");
  }
  if (painSite.includes("lateralATFL")) {
    S.lateral_sprain.score += 0.7;
    S.lateral_sprain.why.push("Lateral ankle pain (ATFL/CFL region)");
  }
  if (instability === "sometimes" || instability === "often") {
    S.lateral_sprain.score += 0.2;
    S.lateral_sprain.why.push("Perceived giving-way");
  }

  // --------- PERONEAL TENDON (NEW) ---------
  if (painSite.includes("peroneal") || (painSite.includes("lateralATFL") && loadAggs.includes("cuttingLanding"))) {
    S.peroneal_tendon.score += 0.55;
    S.peroneal_tendon.why.push("Lateral symptoms with cutting/landing or peroneal site");
  }
  if (followUps.includes("snapping") || followUps.includes("popHeard")) {
    S.peroneal_tendon.score += 0.15;
    S.peroneal_tendon.why.push("Pop/snapping suggests tendon sublux/tear");
  }

  // --------- SYNDESMOSIS ---------
  if (mech === "footFixedTwist") {
    S.syndesmosis.score += 0.6;
    S.syndesmosis.why.push("Foot fixed/twist or forced DF/ER");
  }
  if (painSite.includes("syndesmosisHigh") || highSwelling) {
    S.syndesmosis.score += 0.6;
    S.syndesmosis.why.push("High ankle tenderness/swelling");
  }
  if (walk4 === "no" || walk4 === "barely") {
    S.syndesmosis.score += 0.2;
    S.syndesmosis.why.push("4-step difficulty");
  }
  // Prevent high-ankle bleed into midfoot-only cases
  if (painSite.includes("midfoot") && !painSite.includes("syndesmosisHigh") && !highSwelling) {
    S.syndesmosis.score -= 0.25;
  }

  // --------- FRACTURE / BONY INJURY ---------
  if (mech === "hardLanding" || fourStepFail) {
    S.acute_fracture.score += 1.0;
    S.acute_fracture.why.push("High-energy/4-step fail");
  }
  if (deformity || neuro) {
    S.acute_fracture.score += 0.6;
    S.acute_fracture.why.push("Deformity or neuro signs");
  }
  // If Ottawa-positive pattern, down-weight sprain buckets (fixes mis-rank)
  if (fourStepFail && fromMech) {
    S.lateral_sprain.score -= 0.35;
    S.syndesmosis.score -= 0.15;
  }

  // --------- ACHILLES (NON-RUPTURE) ---------
  if (painSite.includes("achilles")) {
    S.achilles_injury.score += 0.6;
    S.achilles_injury.why.push("Posterior heel/Achilles site");
  }
  if (loadAggs.includes("stairsHillsTiptoe")) {
    S.achilles_injury.score += 0.3;
    S.achilles_injury.why.push("Tiptoe/hill load sensitivity");
  }
  if (tiptoes === "partial") {
    S.achilles_injury.score += 0.2;
    S.achilles_injury.why.push("Tiptoe limited");
  }

  // --------- OLT TALUS (NEW) ---------
  if (
    painSite.includes("deepAnkle") &&
    (timeSince === "2–6wk" || timeSince === ">6wk") &&
    (mech === "inversionRoll" || mech === "footFixedTwist")
  ) {
    S.olt_talus.score += 0.65;
    S.olt_talus.why.push("Persistent deep ankle pain post-sprain");
  }
  if (followUps.includes("catchLock")) {
    S.olt_talus.score += 0.2;
    S.olt_talus.why.push("Catching/locking suggests OLT");
  }

  // --------- PLANTAR FASCIA ---------
  if (painSite.includes("plantar")) {
    S.plantar_fascia.score += 0.6;
    S.plantar_fascia.why.push("Inferior heel/arch site");
  }
  if (loadAggs.includes("firstStepsWorse")) {
    S.plantar_fascia.score += 0.6;
    S.plantar_fascia.why.push("First-steps worse, eases with warm-up");
  }

  // --------- TARSAL TUNNEL (NEW) ---------
  if (loadAggs.includes("throbsAtRest") || neuro || followUps.includes("burning")) {
    S.tarsal_tunnel.score += 0.65;
    S.tarsal_tunnel.why.push("Rest/burning/paraesthesia pattern (neural)");
    // If neural pattern without classic first-steps, reduce plantar fascia a bit
    if (!loadAggs.includes("firstStepsWorse")) S.plantar_fascia.score -= 0.2;
  }

  // --------- MIDFOOT / LISFRANC ---------
  if (painSite.includes("midfoot")) {
    S.midfoot_lisfranc.score += 0.6;
    S.midfoot_lisfranc.why.push("Midfoot hotspot");
  }
  if (mech === "hardLanding" || mech === "footFixedTwist") {
    S.midfoot_lisfranc.score += 0.3;
    S.midfoot_lisfranc.why.push("Axial/twist mechanism");
  }
  if (followUps.includes("pianoKeyPositive")) {
    S.midfoot_lisfranc.score += 0.2;
    S.midfoot_lisfranc.why.push("Piano-key/squeeze positive");
  }

  // --------- STRESS FRACTURE (NEW) ---------
  if (
    onsetStyle === "creeping" &&
    (timeSince === "2–6wk" || timeSince === ">6wk") &&
    painSite.some((p) => ["midfoot", "forefoot", "plantar"].includes(p))
  ) {
    S.stress_fracture.score += 0.6;
    S.stress_fracture.why.push("Gradual onset + persistent loading pain");
  }
  if (followUps.includes("nightPain")) {
    S.stress_fracture.score += 0.2;
    S.stress_fracture.why.push("Night/rest pain raises stress injury suspicion");
  }

  // --------- POSTERIOR TIBIALIS (NEW) ---------
  if (painSite.includes("medialArch") || painSite.includes("medialAnkle")) {
    S.posterior_tibialis.score += 0.55;
    S.posterior_tibialis.why.push("Medial arch/ankle site");
  }
  if (followUps.includes("archCollapse")) {
    S.posterior_tibialis.score += 0.2;
    S.posterior_tibialis.why.push("Arch collapse/flatfoot progression");
  }

  // --------- NEUROMA (NEW) ---------
  if (painSite.includes("forefoot") && followUps.includes("tightShoes")) {
    S.forefoot_neuroma.score += 0.65;
    S.forefoot_neuroma.why.push("Forefoot pain with shoe compression");
  }
  if (followUps.includes("mulderClick")) {
    S.forefoot_neuroma.score += 0.2;
    S.forefoot_neuroma.why.push("Mulder click/paresthesia");
  }

  // --------- CHRONIC INSTABILITY ---------
  if (onsetStyle === "recurrent") {
    S.chronic_instability.score += 0.7;
    S.chronic_instability.why.push("Recurrent giving-way");
  }
  if (timeSince === ">6wk") {
    S.chronic_instability.score += 0.2;
    S.chronic_instability.why.push(">6 weeks duration");
  }

  // --------- Impact bump (small) ---------
  if (impact >= 7) {
    S.acute_fracture.score += 0.1;
    S.syndesmosis.score += 0.1;
  }

  // Urgent pathways should never float up unless triage forces them
  S.inflammatory_infection.score = -Infinity;
  S.achilles_rupture_urgent.score = -Infinity;

  return S;
}

/* ----------------- summary builder ----------------- */

function buildSummary(answers: Answer[]) {
  const { triage, notes, force } = computeTriage(answers);

  // Force red differentials cleanly
  if (triage === "red" && force) {
    const forced = diffs[force];
    return {
      region: "Ankle/Foot",
      triage,
      redFlagNotes: notes,
      topDifferentials: [{ name: forced.name, score: 999 }],
      clinicalToDo: forced.tests,
      detailedTop: [
        {
          key: force,
          name: forced.name,
          score: 999,
          rationale: ["Urgent pathway triggered"],
          objectiveTests: forced.tests,
        },
      ],
    };
  }

  const scored = score(answers, triage);

  const ranked = (Object.keys(scored) as Differential[])
    .filter((k) => scored[k].score !== -Infinity)
    .map((k) => ({ key: k, ...scored[k] }))
    .sort((a, b) => b.score - a.score || diffs[b.key].base - diffs[a.key].base);

  const top = ranked.slice(0, 3).map((item) => ({
    key: item.key,
    name: diffs[item.key].name,
    score: Number(Math.max(0, item.score).toFixed(2)),
    rationale: item.why,
    objectiveTests: diffs[item.key].tests,
  }));

  const globalTests =
    triage === "amber"
      ? [
          "Re-check Ottawa Ankle/Foot Rules + neurovascular screen as needed",
          "ROM/strength screen within irritability limits",
          "Consider imaging/medical review if worsening or non-progressing",
        ]
      : [
          "Ankle/foot AROM/PROM; irritability and swelling assessment",
          "Gait + single-leg stance (if safe) and functional tolerance",
          "Proximal screen (calf strength, knee/hip) as indicated",
        ];

  const clinicalToDo = Array.from(
    new Set([...globalTests, ...top.flatMap((t) => t.objectiveTests)])
  );

  return {
    region: "Ankle/Foot",
    triage,
    redFlagNotes: triage === "green" ? [] : notes,
    topDifferentials: top.map((t) => ({ name: t.name, score: t.score })),
    clinicalToDo,
    detailedTop: top,
  };
}

/* ----------------- callable ----------------- */

export async function processAnkleAssessmentCore(
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
        triageRegion: "ankle",
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
export const processAnkleAssessment = functions
  .region("europe-west1")
  .https.onCall(async (data, ctx) => {
    return processAnkleAssessmentCore(data, ctx);
  });