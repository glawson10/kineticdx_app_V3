import * as functions from "firebase-functions/v1";
import { getFirestore } from "firebase-admin/firestore";

const db = getFirestore();

type Triage = "green" | "amber" | "red";
type Answer =
  | { id: string; kind: "single"; value: string }
  | { id: string; kind: "multi"; values: string[] }
  | { id: string; kind: "slider"; value: number };

type DifferentialKey =
  | "scaphoid_fracture"
  | "tfcc_druj"
  | "de_quervain"
  | "carpal_tunnel"
  | "scapholunate_instability"
  | "distal_radius_fracture"
  | "crps"
  | "serious_non_msk";

interface DifferentialInfo {
  key: DifferentialKey;
  name: string;
  baseWeight: number;
  objectiveTests: string[];
}

interface WristSummary {
  region: "Wrist";
  side?: "Left" | "Right" | "Both" | "Not sure";
  triage: Triage;
  redFlagNotes: string[];
  topDifferentials: Array<{
    key: DifferentialKey;
    name: string;
    score: number;
    rationale: string[];
    objectiveTests: string[];
  }>;
}

const diffs: Record<DifferentialKey, DifferentialInfo> = {
  scaphoid_fracture: {
    key: "scaphoid_fracture",
    name: "Scaphoid fracture",
    baseWeight: 0.2,
    objectiveTests: [
      "Palpate anatomical snuff box & scaphoid tubercle",
      "Longitudinal thumb compression test",
      "Resisted thumb extension",
      "Grip strength comparison",
      "X-ray (scaphoid views) ± MRI if x-ray negative",
    ],
  },
  tfcc_druj: {
    key: "tfcc_druj",
    name: "TFCC / DRUJ injury",
    baseWeight: 0.18,
    objectiveTests: [
      "TFCC compression (ulnar dev + axial load)",
      "Piano key sign (DRUJ)",
      "Supination lift test",
      "Press test (push-up from chair)",
      "Grip dynamometry",
    ],
  },
  de_quervain: {
    key: "de_quervain",
    name: "De Quervain's tenosynovitis",
    baseWeight: 0.18,
    objectiveTests: [
      "Palpate APL/EPB over radial styloid",
      "Resisted thumb abduction/extension",
      "Finkelstein / Eichhoff",
    ],
  },
  carpal_tunnel: {
    key: "carpal_tunnel",
    name: "Carpal tunnel syndrome",
    baseWeight: 0.14,
    objectiveTests: [
      "Phalen's / reverse Phalen's",
      "Tinel's at carpal tunnel",
      "Pinch & grip strength",
      "Two-point discrimination",
    ],
  },
  scapholunate_instability: {
    key: "scapholunate_instability",
    name: "Scapholunate ligament injury / carpal instability",
    baseWeight: 0.14,
    objectiveTests: [
      "Watson scaphoid shift test",
      "Scapholunate ballottement",
      "Grip strength comparison",
    ],
  },
  distal_radius_fracture: {
    key: "distal_radius_fracture",
    name: "Distal radius (Colles’) fracture",
    baseWeight: 0.05,
    objectiveTests: [
      "Observation for deformity/swelling",
      "Neurovascular screen",
      "X-ray",
    ],
  },
  crps: {
    key: "crps",
    name: "Complex Regional Pain Syndrome",
    baseWeight: 0.02,
    objectiveTests: [
      "Allodynia, colour/temperature change, swelling",
      "Budapest criteria",
    ],
  },
  serious_non_msk: {
    key: "serious_non_msk",
    name: "Serious / non-MSK concern (infection/tumour/systemic)",
    baseWeight: 0.0,
    objectiveTests: [
      "Vitals/temperature",
      "Inflammatory markers",
      "Medical referral",
    ],
  },
};

function computeTriage(answers: Answer[]) {
  const get = (id: string) =>
    answers.find((a) => a.id === id) as any;
  const notes: string[] = [];
  let triage: Triage = "green";

  const sys: string[] = get("Q1_system")?.values ?? [];
  const sysHas = (k: string) => sys.includes(k);
  const systemicRed =
    sysHas("fever") ||
    sysHas("wtloss") ||
    sysHas("both_hands_tingles") ||
    sysHas("extreme_colour_temp") ||
    sysHas("constant_night");

  if (systemicRed) {
    notes.push("Systemic or widespread neurological symptoms");
    triage = "red";
  }

  let injuryRed = false;
  let injuryFlags: string[] = [];
  if (get("Q2_injury")?.value === "yes") {
    const inj: string[] = get("Q3_injury_cluster")?.values ?? [];
    const ih = (k: string) => inj.includes(k);
    if (
      ih("no_weight_bear") ||
      ih("pop_crack") ||
      ih("deformity") ||
      ih("severe_pain") ||
      ih("immediate_numb")
    ) {
      notes.push(
        "Acute injury red flags (possible fracture/dislocation/neuro)"
      );
      triage = "red";
      injuryRed = true;
      injuryFlags = inj.slice();
    }
  }

  return { triage, notes, systemicRed, injuryRed, injuryFlags, sysFlags: sys };
}

function score(
  answers: Answer[],
  triageInfo: ReturnType<typeof computeTriage>
) {
  const { triage, systemicRed, injuryRed, injuryFlags } =
    triageInfo;

  const get = (id: string) =>
    answers.find((a) => a.id === id) as any;

  const S: Record<
    DifferentialKey,
    { score: number; rationale: string[] }
  > = {
    scaphoid_fracture: {
      score: diffs.scaphoid_fracture.baseWeight,
      rationale: [],
    },
    tfcc_druj: {
      score: diffs.tfcc_druj.baseWeight,
      rationale: [],
    },
    de_quervain: {
      score: diffs.de_quervain.baseWeight,
      rationale: [],
    },
    carpal_tunnel: {
      score: diffs.carpal_tunnel.baseWeight,
      rationale: [],
    },
    scapholunate_instability: {
      score: diffs.scapholunate_instability.baseWeight,
      rationale: [],
    },
    distal_radius_fracture: {
      score: diffs.distal_radius_fracture.baseWeight,
      rationale: [],
    },
    crps: { score: diffs.crps.baseWeight, rationale: [] },
    serious_non_msk: {
      score: diffs.serious_non_msk.baseWeight,
      rationale: [],
    },
  };

  const zone = get("Q4_zone")?.value as
    | "radial"
    | "ulnar"
    | "dorsal"
    | "volar"
    | "diffuse"
    | undefined;
  const onset = get("Q5_onset")?.value as
    | "sudden"
    | "gradual"
    | "unsure"
    | undefined;
  const injList: string[] = get("Q6a_mech")?.values ?? [];
  const aggs: string[] = get("Q6b_aggs")?.values ?? [];
  const features: string[] = get("Q7_features")?.values ?? [];
  const wb = get("Q8_weightbear")?.value as
    | "yes_ok"
    | "yes_pain"
    | "no"
    | undefined;
  const risks: string[] = get("Q10_risks")?.values ?? [];

  // Scaphoid fracture
  if (
    zone === "radial" &&
    (injList.includes("foosh") || onset === "sudden")
  ) {
    S.scaphoid_fracture.score += 0.45;
    S.scaphoid_fracture.rationale.push(
      "Radial pain with FOOSH/sudden onset"
    );
  }
  if (features.includes("weak_grip")) {
    S.scaphoid_fracture.score += 0.1;
    S.scaphoid_fracture.rationale.push("Grip painful/weak");
  }

  // TFCC/DRUJ
  if (zone === "ulnar") {
    S.tfcc_druj.score += 0.25;
    S.tfcc_druj.rationale.push("Ulnar-sided pain");
  }
  if (aggs.includes("twist") || aggs.includes("weight_bear")) {
    S.tfcc_druj.score += 0.2;
    S.tfcc_druj.rationale.push(
      "Worse with rotation/weightbearing"
    );
  }
  if (features.includes("clicking")) {
    S.tfcc_druj.score += 0.15;
    S.tfcc_druj.rationale.push("Clicking/instability symptoms");
  }

  // De Quervain
  if (zone === "radial" && onset === "gradual") {
    S.de_quervain.score += 0.3;
    S.de_quervain.rationale.push("Gradual radial wrist pain");
  }
  if (aggs.includes("grip_lift")) {
    S.de_quervain.score += 0.15;
    S.de_quervain.rationale.push(
      "Worse with gripping/lifting"
    );
  }
  if (
    risks.includes("preg_postpartum") ||
    risks.includes("post_meno")
  ) {
    S.de_quervain.score += 0.1;
    S.de_quervain.rationale.push(
      "Postpartum or perimenopausal risk"
    );
  }

  // Carpal tunnel
  if (zone === "volar") {
    S.carpal_tunnel.score += 0.12;
    S.carpal_tunnel.rationale.push("Volar/palmar symptoms");
  }
  if (features.includes("tingle_thumb_index")) {
    S.carpal_tunnel.score += 0.25;
    S.carpal_tunnel.rationale.push(
      "Median-nerve pattern paraesthesia"
    );
  }
  if (aggs.includes("typing")) {
    S.carpal_tunnel.score += 0.1;
    S.carpal_tunnel.rationale.push("Desk/typing provocation");
  }
  if (
    aggs.includes("typing") &&
    zone !== "volar" &&
    !features.includes("tingle_thumb_index")
  ) {
    S.carpal_tunnel.score = Math.max(
      0,
      S.carpal_tunnel.score - 0.05
    );
    S.carpal_tunnel.rationale.push(
      "Typing provocation without volar distribution/median pattern (guardrail -0.05)"
    );
  }

  // Scapholunate instability
  if (zone === "dorsal") {
    S.scapholunate_instability.score += 0.15;
    S.scapholunate_instability.rationale.push(
      "Dorsal central ache"
    );
  }
  if (
    features.includes("clicking") ||
    features.includes("weak_grip")
  ) {
    S.scapholunate_instability.score += 0.2;
    S.scapholunate_instability.rationale.push(
      "Click/clunk or weak grip"
    );
  }
  if (
    injList.includes("foosh") ||
    onset === "sudden"
  ) {
    S.scapholunate_instability.score += 0.15;
    S.scapholunate_instability.rationale.push(
      "FOOSH/sudden mechanism"
    );
  }

  // Distal radius fracture
  if (
    injList.length > 0 &&
    (features.includes("swelling") ||
      features.includes("bump_shape"))
  ) {
    S.distal_radius_fracture.score += 0.2;
    S.distal_radius_fracture.rationale.push(
      "Swelling/deformity after injury"
    );
  }
  if (wb === "no") {
    S.distal_radius_fracture.score += 0.2;
    S.distal_radius_fracture.rationale.push(
      "Unable to weight-bear"
    );
  }
  if (wb === "yes_pain" && injList.length > 0) {
    S.distal_radius_fracture.score += 0.1;
    S.distal_radius_fracture.rationale.push(
      "Painful weight-bearing post-injury"
    );
  }

  // CRPS
  if (features.includes("extreme_colour_temp")) {
    S.crps.score += 0.25;
    S.crps.rationale.push(
      "Colour/temperature change and sensitivity"
    );
  }
  if (
    zone === "diffuse" &&
    features.includes("extreme_colour_temp")
  ) {
    S.crps.score += 0.08;
    S.crps.rationale.push(
      "Diffuse distribution with vasomotor change (+0.08)"
    );
  }

  if (triage === "red") {
    if (systemicRed) {
      S.serious_non_msk.score = 999;
      S.serious_non_msk.rationale.push(
        "Systemic/widespread red flags present – prioritize medical causes"
      );
    } else if (injuryRed) {
      if (
        injuryFlags.includes("deformity") ||
        injuryFlags.includes("no_weight_bear")
      ) {
        S.distal_radius_fracture.score += 0.4;
        S.distal_radius_fracture.rationale.push(
          "Injury red flags (deformity/no weight-bear) – strong suspicion of distal radius fracture (+0.40)"
        );
      }
      if (
        zone === "radial" &&
        (injList.includes("foosh") ||
          onset === "sudden")
      ) {
        S.scaphoid_fracture.score += 0.25;
        S.scaphoid_fracture.rationale.push(
          "Injury red flags with radial FOOSH/sudden – scaphoid risk (+0.25)"
        );
      }
    }
  }

  return S;
}

function buildSummary(answers: Answer[]): WristSummary {
  const get = (id: string) =>
    answers.find((a) => a.id === id) as any;
  const sidePref = (get("Q_side")?.value ??
    undefined) as WristSummary["side"];

  const triageInfo = computeTriage(answers);
  const scored = score(answers, triageInfo);

  const ranked = (Object.keys(scored) as DifferentialKey[])
    .map((k) => ({ key: k, ...scored[k] }))
    .sort((a, b) => b.score - a.score);

  const top = ranked.slice(0, 3).map((item) => {
    const meta = diffs[item.key];
    return {
      key: item.key,
      name: meta.name,
      score: Number(item.score.toFixed(2)),
      rationale: item.rationale,
      objectiveTests: meta.objectiveTests,
    };
  });

  return {
    region: "Wrist",
    side: sidePref,
    triage: triageInfo.triage,
    redFlagNotes: triageInfo.notes,
    topDifferentials: top,
  };
}

export const processWristAssessment = functions
  .region("europe-west1")
  .https.onCall(async (data, _ctx) => {
    const assessmentId: string | undefined = data?.assessmentId;

    let answers: Answer[] = [];
    if (assessmentId) {
      const snap = await db.collection("assessments").doc(assessmentId).get();
      const doc = snap.data() ?? {};
      answers =
        doc?.answers?.region?.wrist?.answers ??
        doc?.answers?.region?.wrist_right?.answers ??
        doc?.answers?.region?.wrist_left?.answers ??
        [];
    } else {
      answers = (data?.answers as Answer[]) ?? [];
    }

    const summary = buildSummary(answers);

    const globalObjectiveRecommendations = [
      "Grip/pinch dynamometry (compare sides)",
      "Palpation: snuff box, scaphoid tubercle, TFCC, APL/EPB sheath",
      "Provocation: Finkelstein/Eichhoff, TFCC compression, Press test, Watson test as indicated",
      "Neuro screen (median/ulnar/radial) if paraesthesia or weakness",
      "Consider imaging if acute FOOSH with radial pain or weight-bearing inability",
    ];

    return {
      triageStatus: summary.triage,
      topDifferentials: summary.topDifferentials,
      clinicianSummary: {
        region: "Wrist",
        side: summary.side ?? null,
        triage: summary.triage,
        redFlagNotes: summary.redFlagNotes,
        topDifferentials: summary.topDifferentials,
        globalObjectiveRecommendations,
      },
    };
  });
export { buildSummary };