"use strict";
// functions/src/ankle/processAnkleAssessment.ts
//
// Legacy callable retained, but now uses the pure scorer for a single source of truth.
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.processAnkleAssessment = void 0;
exports.processAnkleAssessmentCore = processAnkleAssessmentCore;
const functions = __importStar(require("firebase-functions/v1"));
const firestore_1 = require("firebase-admin/firestore");
const db = (0, firestore_1.getFirestore)();
const diffs = {
    lateral_sprain: {
        key: "lateral_sprain",
        name: "Lateral ankle ligament sprain (ATFL/CFL)",
        base: 0.4,
        tests: [
            "Palpation ATFL/CFL",
            "Anterior drawer (ATFL)",
            "Talar tilt – inversion (CFL)",
            "Single-leg balance baseline (30s target)",
        ],
    },
    syndesmosis: {
        key: "syndesmosis",
        name: "High ankle (syndesmosis) injury",
        base: 0.35,
        tests: [
            "Squeeze test",
            "External rotation test",
            "Pain with dorsiflexion",
            "Consider WB X-rays for tib-fib diastasis",
        ],
    },
    acute_fracture: {
        key: "acute_fracture",
        name: "Acute ankle/foot fracture (Ottawa positive)",
        base: 0.0,
        tests: [
            "Ottawa Ankle/Foot Rules (palpation zones)",
            "4-step test in clinic",
            "Imaging (incl. base 5th MT / navicular views)",
        ],
    },
    achilles_injury: {
        key: "achilles_injury",
        name: "Achilles tendon injury (reactive ↔ partial tear)",
        base: 0.25,
        tests: [
            "Thompson-style plantarflexion check (if safe)",
            "Palpation for gap/tenderness",
            "Single-leg heel raise tolerance",
        ],
    },
    plantar_fascia: {
        key: "plantar_fascia",
        name: "Plantar heel pain (plantar fascia)",
        base: 0.2,
        tests: [
            "Palpation medial calcaneal tubercle",
            "Windlass test (hallux extension)",
            "Footwear / arch mechanics review",
        ],
    },
    midfoot_lisfranc: {
        key: "midfoot_lisfranc",
        name: "Midfoot (Lisfranc/navicular) injury",
        base: 0.2,
        tests: [
            "Midfoot stress/squeeze, piano-key",
            "Palpate navicular “N-spot”",
            "WB X-ray for 1st–2nd met base widening",
        ],
    },
    chronic_instability: {
        key: "chronic_instability",
        name: "Chronic ankle instability",
        base: 0.18,
        tests: [
            "Anterior drawer / Talar tilt laxity",
            "Single-leg balance time vs contralateral",
            "LEFS + evertor/PF strength for RTP",
        ],
    },
    inflammatory_infection: {
        key: "inflammatory_infection",
        name: "Inflammatory / infective ankle-foot (urgent)",
        base: 0.0,
        tests: [
            "Temperature / vitals",
            "Urgent medical review ± aspiration",
            "Bloods per pathway",
        ],
    },
    achilles_rupture_urgent: {
        key: "achilles_rupture_urgent",
        name: "Achilles tendon rupture (urgent)",
        base: 0.0,
        tests: [
            "Thompson test",
            "Palpable gap",
            "Early immobilisation and ortho pathway per protocol",
        ],
    },
};
// ---------- helpers ----------
function getSingle(answers, id) {
    const a = answers.find((x) => x.id === id && x.kind === "single");
    return a === null || a === void 0 ? void 0 : a.value;
}
function getMulti(answers, id) {
    const a = answers.find((x) => x.id === id && x.kind === "multi");
    return Array.isArray(a === null || a === void 0 ? void 0 : a.values) ? a.values : [];
}
function getSlider(answers, id) {
    const a = answers.find((x) => x.id === id && x.kind === "slider");
    return typeof (a === null || a === void 0 ? void 0 : a.value) === "number" ? a.value : undefined;
}
const yes = (v) => (v !== null && v !== void 0 ? v : "").toLowerCase() === "yes";
// ---------- triage ----------
function computeTriage(answers) {
    const notes = [];
    // Red-flag inputs
    const fromMech = getSingle(answers, "A_rf_fromFallTwistLanding"); // yes/no
    const followUps = getMulti(answers, "A_rf_followUps"); // fourStepsImmediate, popHeard, deformity, numbPins
    const walk4Now = (getSingle(answers, "A_rf_walk4Now") || "").toLowerCase(); // yes/barely/no
    const highSwelling = yes(getSingle(answers, "A_rf_highSwelling")); // towards shin
    const hotRedFever = yes(getSingle(answers, "A_rf_hotRedFever")); // infective
    const calfHotTight = yes(getSingle(answers, "A_rf_calfHotTight")); // DVT-type flag
    const tiptoes = (getSingle(answers, "A_rf_tiptoes") || "").toLowerCase(); // yes/partial/notatall
    // Urgent infectious
    if (hotRedFever) {
        notes.push("Red-hot swollen ankle/foot with systemic symptoms");
        return {
            triage: "red",
            notes,
            force: "inflammatory_infection",
        };
    }
    // Achilles rupture pattern: “not at all” tiptoe + pop or deformity
    if (tiptoes === "notatall" &&
        (followUps.includes("popHeard") || followUps.includes("deformity"))) {
        notes.push("Tiptoe impossible with pop/deformity → Achilles rupture concern");
        return {
            triage: "red",
            notes,
            force: "achilles_rupture_urgent",
        };
    }
    const trauma = yes(fromMech);
    const fourStepImmediateFail = followUps.includes("fourStepsImmediate");
    // Acute fracture pattern: 4-step immediate fail or can’t walk now, with trauma
    if ((fourStepImmediateFail || walk4Now === "no") && trauma) {
        notes.push("Unable to take 4 steps after injury / now with trauma (Ottawa positive likely)");
        // Red vs Amber: escalate RED if deformity or neuro symptoms
        if (followUps.includes("deformity") || followUps.includes("numbPins")) {
            notes.push("Deformity or neuro symptoms present");
            return { triage: "red", notes, force: "acute_fracture" };
        }
        return { triage: "amber", notes, force: undefined };
    }
    // Syndesmosis red flag: high swelling/tenderness + walk fail
    if (highSwelling && (walk4Now === "no" || walk4Now === "barely") && trauma) {
        notes.push("High ankle tenderness/swelling with 4-step difficulty");
        return { triage: "amber", notes, force: undefined };
    }
    // DVT-type caution
    if (calfHotTight) {
        notes.push("Calf hot/tight after immobilisation/surgery – medical review advised");
        return { triage: "amber", notes, force: undefined };
    }
    return { triage: "green", notes, force: undefined };
}
// ---------- scoring ----------
function score(answers, triage) {
    var _a;
    const S = Object.keys(diffs).reduce((acc, k) => {
        acc[k] = { score: diffs[k].base, why: [] };
        return acc;
    }, {});
    // Pull main fields
    const mech = getSingle(answers, "A_mech"); // inversionRoll/footFixedTwist/hardLanding/gradual
    const painSite = getMulti(answers, "A_painSite"); // lateralATFL/syndesmosisHigh/achilles/plantar/midfoot
    const loadAggs = getMulti(answers, "A_loadAggs"); // walkFlat/stairsHillsTiptoe/cuttingLanding/firstStepsWorse/throbsAtRest
    const onsetStyle = getSingle(answers, "A_onsetStyle"); // explosive/creeping/recurrent
    const timeSince = getSingle(answers, "A_timeSince"); // <48h/2–14d/2–6wk/>6wk
    const instability = getSingle(answers, "A_instability"); // never/sometimes/often
    const impact = (_a = getSlider(answers, "A_impactScore")) !== null && _a !== void 0 ? _a : 0;
    const walk4Now = (getSingle(answers, "A_rf_walk4Now") || "").toLowerCase();
    const followUps = getMulti(answers, "A_rf_followUps");
    const tiptoes = (getSingle(answers, "A_rf_tiptoes") || "").toLowerCase();
    const highSwelling = yes(getSingle(answers, "A_rf_highSwelling"));
    // Lateral sprain
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
    // Syndesmosis
    if (mech === "footFixedTwist") {
        S.syndesmosis.score += 0.6;
        S.syndesmosis.why.push("Foot fixed/twist or forced DF/ER");
    }
    if (painSite.includes("syndesmosisHigh") || highSwelling) {
        S.syndesmosis.score += 0.6;
        S.syndesmosis.why.push("High ankle tenderness/swelling");
    }
    if (walk4Now === "no" || walk4Now === "barely") {
        S.syndesmosis.score += 0.2;
        S.syndesmosis.why.push("4-step difficulty");
    }
    // Acute fracture
    if (mech === "hardLanding" || walk4Now === "no" || followUps.includes("fourStepsImmediate")) {
        S.acute_fracture.score += 0.8;
        S.acute_fracture.why.push("High-energy/landing or 4-step fail");
    }
    if (followUps.includes("deformity") || followUps.includes("numbPins")) {
        S.acute_fracture.score += 0.6;
        S.acute_fracture.why.push("Deformity or neuro signs");
    }
    // Achilles injury (reactive ↔ partial)
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
    // Plantar fascia
    if (painSite.includes("plantar")) {
        S.plantar_fascia.score += 0.6;
        S.plantar_fascia.why.push("Inferior heel/arch site");
    }
    if (loadAggs.includes("firstStepsWorse")) {
        S.plantar_fascia.score += 0.6;
        S.plantar_fascia.why.push("First-steps worse, eases with warm-up");
    }
    // Midfoot / Lisfranc
    if (painSite.includes("midfoot")) {
        S.midfoot_lisfranc.score += 0.6;
        S.midfoot_lisfranc.why.push("Midfoot hotspot");
    }
    if (mech === "hardLanding" || mech === "footFixedTwist") {
        S.midfoot_lisfranc.score += 0.3;
        S.midfoot_lisfranc.why.push("Axial/twist mechanism");
    }
    // Chronic instability
    if (onsetStyle === "recurrent") {
        S.chronic_instability.score += 0.7;
        S.chronic_instability.why.push("Recurrent giving-way");
    }
    if (timeSince === ">6wk") {
        S.chronic_instability.score += 0.2;
        S.chronic_instability.why.push(">6 weeks duration");
    }
    // Urgent buckets (will dominate when triage=red)
    if (triage === "red") {
        S.inflammatory_infection.score += 5;
        S.achilles_rupture_urgent.score += 5;
    }
    // Impact bumps overall acute seriousness (without changing rank order too much)
    if (impact >= 7) {
        S.acute_fracture.score += 0.1;
        S.syndesmosis.score += 0.1;
    }
    return S;
}
function buildSummary(answers) {
    const { triage, notes, force } = computeTriage(answers);
    const scored = score(answers, triage);
    // Rank
    const ranked = Object.keys(scored)
        .map((k) => ({ key: k, ...scored[k] }))
        .sort((a, b) => b.score - a.score);
    // If triage RED with a forced urgent bucket, pin it top and truncate to 1
    if (triage === "red" && force) {
        const urgent = {
            key: force,
            name: diffs[force].name,
            score: 999,
            rationale: ["Red-flag criteria met"],
            objectiveTests: diffs[force].tests,
        };
        const globalTests = [
            "Ottawa Ankle/Foot Rules",
            "4-step test (if safe)",
            "Neurovascular screen",
            ...diffs[force].tests,
        ];
        return {
            region: "Ankle",
            triage,
            redFlagNotes: notes,
            topDifferentials: [{ name: urgent.name, score: 1.0 }],
            clinicalToDo: Array.from(new Set(globalTests)),
            detailedTop: [urgent],
        };
    }
    // Otherwise, pick top 3 non-urgent
    const top = ranked.slice(0, 3).map((item) => ({
        key: item.key,
        name: diffs[item.key].name,
        score: Number(item.score.toFixed(2)),
        rationale: item.why,
        objectiveTests: diffs[item.key].tests,
    }));
    const globalTests = [
        "Ottawa Ankle/Foot Rules",
        "4-step test in clinic",
        "Observation: swelling height/pattern, bruising",
        "Neurovascular screen",
        "ROM DF/PF, inversion/eversion; accessory glides as needed",
    ];
    return {
        region: "Ankle",
        triage,
        redFlagNotes: triage === "green" ? [] : notes,
        topDifferentials: top.map((t) => ({ name: t.name, score: t.score })),
        clinicalToDo: Array.from(new Set([...globalTests, ...top.flatMap((t) => t.objectiveTests)])),
        detailedTop: top,
    };
}
function processAnkleAssessmentCore(answers) {
    return buildSummary(Array.isArray(answers) ? answers : []);
}
/* ----------------- callable ----------------- */
exports.processAnkleAssessment = functions
    .region("europe-west1")
    .https.onCall(async (data, _ctx) => {
    const assessmentId = data === null || data === void 0 ? void 0 : data.assessmentId;
    const answers = Array.isArray(data === null || data === void 0 ? void 0 : data.answers) ? data.answers : [];
    if (!assessmentId) {
        throw new functions.https.HttpsError("invalid-argument", "assessmentId is required");
    }
    const summary = buildSummary(answers);
    await db
        .collection("assessments")
        .doc(assessmentId)
        .set({
        triageStatus: summary.triage,
        topDifferentials: summary.topDifferentials,
        clinicianSummary: summary,
        triageRegion: "ankle",
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    }, { merge: true });
    return {
        triageStatus: summary.triage,
        topDifferentials: summary.topDifferentials,
        clinicianSummary: summary,
    };
});
//# sourceMappingURL=processAnkleAssessment.js.map