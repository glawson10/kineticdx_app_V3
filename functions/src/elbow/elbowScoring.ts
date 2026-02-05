// functions/src/elbow/elbowScoring.ts
// Pure scoring module extracted from legacy processElbowAssessment.ts
// ✅ No Firebase, no Firestore writes
// ✅ Keeps scoring + triage EXACT (copy/paste logic)

export type Triage = "green" | "amber" | "red";

export type Answer =
  | { id: string; kind: "single"; value: string }
  | { id: string; kind: "multi"; values: string[] }
  | { id: string; kind: "slider"; value: number };

export type Differential =
  | "lat_epi"
  | "med_epi"
  | "olecranon_bursitis"
  | "distal_biceps"
  | "ulnar_neuritis"
  | "radial_tunnel"
  | "chondral_oa"
  | "referred_cervical"
  | "acute_red_pathway"
  | "ucl_sprain"
  | "plri_lucl"
  | "triceps_tendinopathy"
  | "valgus_extension_overload"
  | "capitellar_ocd"
  | "synovial_plica"
  | "crystal_arthritis"
  | "median_neuropathy_pronator";

export interface DiffInfo {
  key: Differential;
  name: string;
  base: number;
  tests: string[];
}

export interface DetailedDx {
  key: Differential;
  name: string;
  score: number;
  rationale: string[];
  objectiveTests: string[];
}

export interface ElbowSummary {
  region: "Elbow";
  triage: Triage;
  redFlagNotes: string[];
  topDifferentials: { name: string; score: number }[];
  clinicalToDo: string[];
  detailedTop: DetailedDx[];
}

type Scored = Record<Differential, { score: number; why: string[] }>;

const diffs: Record<Differential, DiffInfo> = {
  lat_epi: {
    key: "lat_epi",
    name: "Lateral epicondylalgia (common extensor)",
    base: 0.18,
    tests: [
      "Cozen’s / Chair test / Resisted wrist extension",
      "Palpate CET 2–3 cm distal to lateral epicondyle",
      "Grip dynamometry vs other side",
    ],
  },
  med_epi: {
    key: "med_epi",
    name: "Medial epicondylalgia (flexor–pronator)",
    base: 0.16,
    tests: [
      "Resisted wrist flexion / resisted pronation",
      "Palpate common flexor origin at medial epicondyle",
    ],
  },
  olecranon_bursitis: {
    key: "olecranon_bursitis",
    name: "Olecranon bursitis",
    base: 0.1,
    tests: [
      "Inspect/palpate posterior swelling",
      "Assess warmth/redness; consider aspiration pathway if infected features",
    ],
  },
  distal_biceps: {
    key: "distal_biceps",
    name: "Distal biceps pathology/tear",
    base: 0.1,
    tests: ["Hook test", "Resisted supination strength vs other side"],
  },
  ulnar_neuritis: {
    key: "ulnar_neuritis",
    name: "Ulnar neuritis / cubital tunnel",
    base: 0.12,
    tests: [
      "Tinel’s at cubital tunnel",
      "Elbow flexion test",
      "Ulnar nerve palpation/subluxation check",
    ],
  },
  radial_tunnel: {
    key: "radial_tunnel",
    name: "Radial tunnel / PIN entrapment",
    base: 0.1,
    tests: [
      "Resisted middle finger extension (Maudsley)",
      "Tinel’s over radial tunnel",
      "Resisted supination test",
    ],
  },
  chondral_oa: {
    key: "chondral_oa",
    name: "Chondral/OA or loose body",
    base: 0.08,
    tests: [
      "End-range flex/extension pain",
      "Crepitus; consider imaging if persistent mechanical block",
    ],
  },
  referred_cervical: {
    key: "referred_cervical",
    name: "Referred cervical/radicular pain",
    base: 0.06,
    tests: ["C-spine screen: ROM, Spurling’s, neuro, ULNTs"],
  },
  acute_red_pathway: {
    key: "acute_red_pathway",
    name: "Suspected fracture / dislocation / septic joint",
    base: 0.0,
    tests: [
      "Immobilize; urgent elbow X-ray",
      "Neurovascular exam (pulses, cap refill, motor/sensory)",
      "Same-day medical review if fever or hot, red joint",
    ],
  },

  ucl_sprain: {
    key: "ucl_sprain",
    name: "UCL sprain/tear (throwing valgus overload)",
    base: 0.08,
    tests: [
      "Valgus stress test (at ~20–30° flexion)",
      "Moving valgus stress test (throwing athletes)",
      "Milking maneuver",
      "Assess medial joint line tenderness; consider US/MRI if severe",
    ],
  },
  plri_lucl: {
    key: "plri_lucl",
    name: "Posterolateral rotatory instability (LUCL/PLRI)",
    base: 0.06,
    tests: [
      "Posterolateral rotatory drawer test",
      "Chair push-up test / tabletop relocation test",
      "Pivot-shift (specialist setting)",
      "Assess apprehension with supination + axial load",
    ],
  },
  triceps_tendinopathy: {
    key: "triceps_tendinopathy",
    name: "Triceps tendinopathy / partial tear",
    base: 0.06,
    tests: [
      "Resisted elbow extension (pain/weakness)",
      "Palpate triceps insertion at olecranon",
      "Pain with press-ups/dips; compare strength bilaterally",
    ],
  },
  valgus_extension_overload: {
    key: "valgus_extension_overload",
    name: "Valgus extension overload / posteromedial impingement",
    base: 0.06,
    tests: [
      "Posteromedial tenderness; pain with forced extension",
      "Valgus-extension overload test",
      "Assess throwing mechanics history; imaging if persistent catching/locking",
    ],
  },
  capitellar_ocd: {
    key: "capitellar_ocd",
    name: "Capitellar OCD / radiocapitellar chondral injury",
    base: 0.05,
    tests: [
      "Radiocapitellar compression test",
      "Pain with valgus load + extension in athletes",
      "Mechanical symptoms; consider X-ray/MRI if suspected",
    ],
  },
  synovial_plica: {
    key: "synovial_plica",
    name: "Synovial plica / lateral snapping elbow",
    base: 0.05,
    tests: [
      "Reproduce snapping with flex–extend + pronation/supination",
      "Posterolateral tenderness; rule out instability",
      "Ultrasound can visualize plica in some cases",
    ],
  },
  crystal_arthritis: {
    key: "crystal_arthritis",
    name: "Crystal/inflammatory arthritis flare (e.g., gout/pseudogout)",
    base: 0.05,
    tests: [
      "Check warmth/redness/effusion; ROM limited by pain",
      "Screen systemic features; consider urgent aspiration if uncertain vs infection",
      "Assess other joints; medical review for flare management",
    ],
  },
  median_neuropathy_pronator: {
    key: "median_neuropathy_pronator",
    name: "Median neuropathy (pronator syndrome)",
    base: 0.05,
    tests: [
      "Resisted pronation with elbow flexed (symptom reproduction)",
      "Tinel’s over pronator teres / proximal forearm",
      "Median nerve neuro screen; differentiate from cervical radic/CTS",
    ],
  },
};

// ---------- helpers ----------
function firstSingle(answers: Answer[], id: string): string {
  const a = answers.find((x) => x.id === id && x.kind === "single") as
    | Extract<Answer, { kind: "single" }>
    | undefined;
  return a?.value ?? "";
}

function firstSlider(answers: Answer[], id: string): number {
  const a = answers.find((x) => x.id === id && x.kind === "slider") as
    | Extract<Answer, { kind: "slider" }>
    | undefined;
  return typeof a?.value === "number" ? a!.value : 0;
}

function multiVals(answers: Answer[], id: string): string[] {
  const a = answers.find((x) => x.id === id && x.kind === "multi") as
    | Extract<Answer, { kind: "multi" }>
    | undefined;
  return Array.isArray(a?.values) ? a!.values : [];
}

// ---------- triage ----------
export function computeElbowTriage(answers: Answer[]): { triage: Triage; notes: string[] } {
  const notes: string[] = [];
  let triage: Triage = "green";

  const injuryHigh = firstSingle(answers, "E_rf_injury_force") === "yes";
  const deformity = firstSingle(answers, "E_rf_deformity") === "yes";
  const rapidSwelling = firstSingle(answers, "E_rf_swelling") === "yes";
  const numbAfter = firstSingle(answers, "E_rf_numb") === "yes";
  const feverHot = firstSingle(answers, "E_rf_fever") === "yes";

  const canStraightenRF = firstSingle(answers, "E_can_straighten") === "yes";
  const cantFullyStraighten = !canStraightenRF;

  if (feverHot) {
    notes.push("Fever / hot, red joint");
    triage = "red";
  }

  if (injuryHigh || deformity || rapidSwelling || numbAfter || cantFullyStraighten) {
    if (injuryHigh) notes.push("High-force injury");
    if (deformity) notes.push("Visible deformity");
    if (rapidSwelling) notes.push("Rapid swelling after injury");
    if (numbAfter) notes.push("Numbness/tingling after injury");
    if (cantFullyStraighten) notes.push("Cannot fully straighten elbow");
    triage = "red";
  }

  // Amber-only flagging (legacy logic)
  const nightPain = firstSingle(answers, "E_night_pain") === "yes";
  const constantPain = firstSingle(answers, "E_constant_pain") === "yes";
  const swellingNow = firstSingle(answers, "E_swelling_now") === "yes";

  if (triage !== "red" && (nightPain || constantPain || swellingNow)) {
    if (nightPain) notes.push("Night pain");
    if (constantPain) notes.push("Constant pain");
    if (swellingNow) notes.push("Swelling present");
    triage = "amber";
  }

  return { triage, notes };
}

// ---------- scoring ----------
function initScores(): Scored {
  const S = {} as Scored;
  (Object.keys(diffs) as Differential[]).forEach((k) => {
    S[k] = { score: diffs[k].base, why: [] };
  });
  return S;
}

function score(answers: Answer[], triage: Triage): Scored {
  const S = initScores();

  // When red triage, force red pathway dominant
  if (triage === "red") {
    S.acute_red_pathway.score = 1.0;
    S.acute_red_pathway.why.push("Red flag features present");
    return S;
  }

  const painSite = firstSingle(answers, "E_pain_site"); // lateral/medial/posterior/anterior/diffuse (legacy)
  const gripPain = firstSingle(answers, "E_grip_pain") === "yes";
  const twistPain = firstSingle(answers, "E_twist_pain") === "yes";
  const liftPain = firstSingle(answers, "E_lift_pain") === "yes";
  const restOnElbow = firstSingle(answers, "E_rest_on_elbow") === "yes";
  const clicksLocks = firstSingle(answers, "E_click_lock") === "yes";
  const neckRad = firstSingle(answers, "E_neck_radiation") === "yes";
  const numbPins = firstSingle(answers, "E_numb_pins") === "yes";
  const ulnarDigits = firstSingle(answers, "E_ulnar_digits") === "yes";
  const medianDigits = firstSingle(answers, "E_median_digits") === "yes";

  const onset = firstSingle(answers, "E_onset"); // gradual/afterLoad/afterTrauma etc
  const timeSince = firstSingle(answers, "E_time_since"); // time buckets if used
  const impact = firstSlider(answers, "E_impact_score"); // 0-10 if provided

  // --- lateral epicondylalgia ---
  if (painSite === "lateral") {
    S.lat_epi.score += 0.18;
    S.lat_epi.why.push("Pain is mainly on the outside (lateral) of the elbow");
  }
  if (gripPain || liftPain) {
    S.lat_epi.score += 0.12;
    S.lat_epi.why.push("Worse with gripping or lifting");
  }
  if (onset === "afterLoad" || onset === "gradual") {
    S.lat_epi.score += 0.06;
    S.lat_epi.why.push("Developed gradually or after repeated loading");
  }

  // --- medial epicondylalgia ---
  if (painSite === "medial") {
    S.med_epi.score += 0.18;
    S.med_epi.why.push("Pain is mainly on the inside (medial) of the elbow");
  }
  if (twistPain || liftPain) {
    S.med_epi.score += 0.10;
    S.med_epi.why.push("Worse with twisting or lifting");
  }

  // --- olecranon bursitis ---
  if (painSite === "posterior") {
    S.olecranon_bursitis.score += 0.14;
    S.olecranon_bursitis.why.push("Pain is mainly at the back (posterior) of the elbow");
  }
  if (restOnElbow) {
    S.olecranon_bursitis.score += 0.12;
    S.olecranon_bursitis.why.push("Worse when leaning/resting on the elbow");
  }

  // --- distal biceps ---
  if (painSite === "anterior") {
    S.distal_biceps.score += 0.12;
    S.distal_biceps.why.push("Pain is mainly at the front (anterior) of the elbow");
  }
  if (liftPain && onset === "afterTrauma") {
    S.distal_biceps.score += 0.10;
    S.distal_biceps.why.push("Pain began after an injury and is worse with lifting");
  }

  // --- ulnar neuritis ---
  if (numbPins && ulnarDigits) {
    S.ulnar_neuritis.score += 0.18;
    S.ulnar_neuritis.why.push("Pins/needles or numbness in ring/little finger (ulnar distribution)");
  }

  // --- radial tunnel ---
  if (painSite === "lateral" && twistPain && !gripPain) {
    S.radial_tunnel.score += 0.10;
    S.radial_tunnel.why.push("Lateral pain worse with twisting (possible radial tunnel pattern)");
  }

  // --- chondral/OA ---
  if (clicksLocks) {
    S.chondral_oa.score += 0.14;
    S.chondral_oa.why.push("Clicking/locking suggests mechanical/chondral involvement");
  }
  if (timeSince === "gt6wk" || impact >= 6) {
    S.chondral_oa.score += 0.06;
    S.chondral_oa.why.push("Longer duration or higher day impact");
  }

  // --- referred cervical ---
  if (neckRad) {
    S.referred_cervical.score += 0.18;
    S.referred_cervical.why.push("Neck symptoms or radiation suggests cervical contribution");
  }
  if (neckRad && numbPins) {
    S.referred_cervical.score += 0.08;
    S.referred_cervical.why.push("Radiation + neuro symptoms increases likelihood of cervical involvement");
  }

  // --- median neuropathy (pronator) ---
  if (numbPins && medianDigits) {
    S.median_neuropathy_pronator.score += 0.14;
    S.median_neuropathy_pronator.why.push("Median nerve distribution symptoms");
  }
  if (neckRad) {
    S.median_neuropathy_pronator.score -= 0.05;
    S.median_neuropathy_pronator.why.push("Neck radiation suggests cervical contribution instead");
  }

  return S;
}

// ---------- build summary ----------
export function buildElbowSummaryFromLegacyAnswers(answers: Answer[]): ElbowSummary {
  const { triage, notes } = computeElbowTriage(answers);
  const scored = score(answers, triage);

  const ranked = (Object.keys(scored) as Differential[])
    .filter((k) => (triage === "red" ? true : k !== "acute_red_pathway"))
    .map((k) => ({ key: k, ...scored[k] }))
    .sort((a, b) => b.score - a.score);

  const topCount = triage === "red" ? 1 : 3;

  const top = ranked.slice(0, topCount).map((item) => ({
    key: item.key,
    name: diffs[item.key].name,
    score: Number(item.score.toFixed(2)),
    rationale: item.why,
    objectiveTests: diffs[item.key].tests,
  }));

  const globalTests =
    triage === "red"
      ? [
          "Immobilize and arrange urgent elbow X-ray",
          "Neurovascular exam (pulses, capillary refill, motor/sensory)",
          "Same-day medical review if fever or hot, red joint",
        ]
      : [
          "Elbow AROM/PROM and end-range pain",
          "Grip dynamometry vs other side",
          "C-spine screen if neck/radicular features",
        ];

  return {
    region: "Elbow",
    triage,
    redFlagNotes: triage === "green" ? [] : notes,
    topDifferentials: top.map((t) => ({ name: t.name, score: t.score })),
    clinicalToDo: Array.from(new Set([...globalTests, ...top.flatMap((t) => t.objectiveTests)])),
    detailedTop: top,
  };
}
