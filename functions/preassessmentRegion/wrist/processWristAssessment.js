"use strict";
// functions/src/wrist/processWristAssessment.ts
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
exports.processWristAssessment = void 0;
exports.processWristAssessmentCore = processWristAssessmentCore;
/* Wrist Region – callable scoring + summary (europe-west1, v1 API) */
const functions = __importStar(require("firebase-functions/v1"));
const firestore_1 = require("firebase-admin/firestore");
const db = (0, firestore_1.getFirestore)();
const diffs = {
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
function computeTriage(answers) {
    var _a, _b, _c, _d, _e;
    const get = (id) => answers.find((a) => a.id === id);
    const notes = [];
    let triage = "green";
    const sys = (_b = (_a = get("Q1_system")) === null || _a === void 0 ? void 0 : _a.values) !== null && _b !== void 0 ? _b : [];
    const sysHas = (k) => sys.includes(k);
    const systemicRed = sysHas("fever") ||
        sysHas("wtloss") ||
        sysHas("both_hands_tingles") ||
        sysHas("extreme_colour_temp") ||
        sysHas("constant_night");
    if (systemicRed) {
        notes.push("Systemic or widespread neurological symptoms");
        triage = "red";
    }
    let injuryRed = false;
    let injuryFlags = [];
    if (((_c = get("Q2_injury")) === null || _c === void 0 ? void 0 : _c.value) === "yes") {
        const inj = (_e = (_d = get("Q3_injury_cluster")) === null || _d === void 0 ? void 0 : _d.values) !== null && _e !== void 0 ? _e : [];
        const ih = (k) => inj.includes(k);
        if (ih("no_weight_bear") ||
            ih("pop_crack") ||
            ih("deformity") ||
            ih("severe_pain") ||
            ih("immediate_numb")) {
            notes.push("Acute injury red flags (possible fracture/dislocation/neuro)");
            triage = "red";
            injuryRed = true;
            injuryFlags = inj.slice();
        }
    }
    return { triage, notes, systemicRed, injuryRed, injuryFlags, sysFlags: sys };
}
function score(answers, triageInfo) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l;
    const { triage, systemicRed, injuryRed, injuryFlags } = triageInfo;
    const get = (id) => answers.find((a) => a.id === id);
    const S = {
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
    const zone = (_a = get("Q4_zone")) === null || _a === void 0 ? void 0 : _a.value;
    const onset = (_b = get("Q5_onset")) === null || _b === void 0 ? void 0 : _b.value;
    const injList = (_d = (_c = get("Q6a_mech")) === null || _c === void 0 ? void 0 : _c.values) !== null && _d !== void 0 ? _d : [];
    const aggs = (_f = (_e = get("Q6b_aggs")) === null || _e === void 0 ? void 0 : _e.values) !== null && _f !== void 0 ? _f : [];
    const features = (_h = (_g = get("Q7_features")) === null || _g === void 0 ? void 0 : _g.values) !== null && _h !== void 0 ? _h : [];
    const wb = (_j = get("Q8_weightbear")) === null || _j === void 0 ? void 0 : _j.value;
    const risks = (_l = (_k = get("Q10_risks")) === null || _k === void 0 ? void 0 : _k.values) !== null && _l !== void 0 ? _l : [];
    // Scaphoid fracture
    if (zone === "radial" &&
        (injList.includes("foosh") || onset === "sudden")) {
        S.scaphoid_fracture.score += 0.45;
        S.scaphoid_fracture.rationale.push("Radial pain with FOOSH/sudden onset");
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
        S.tfcc_druj.rationale.push("Worse with rotation/weightbearing");
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
        S.de_quervain.rationale.push("Worse with gripping/lifting");
    }
    if (risks.includes("preg_postpartum") ||
        risks.includes("post_meno")) {
        S.de_quervain.score += 0.1;
        S.de_quervain.rationale.push("Postpartum or perimenopausal risk");
    }
    // Carpal tunnel
    if (zone === "volar") {
        S.carpal_tunnel.score += 0.12;
        S.carpal_tunnel.rationale.push("Volar/palmar symptoms");
    }
    if (features.includes("tingle_thumb_index")) {
        S.carpal_tunnel.score += 0.25;
        S.carpal_tunnel.rationale.push("Median-nerve pattern paraesthesia");
    }
    if (aggs.includes("typing")) {
        S.carpal_tunnel.score += 0.1;
        S.carpal_tunnel.rationale.push("Desk/typing provocation");
    }
    if (aggs.includes("typing") &&
        zone !== "volar" &&
        !features.includes("tingle_thumb_index")) {
        S.carpal_tunnel.score = Math.max(0, S.carpal_tunnel.score - 0.05);
        S.carpal_tunnel.rationale.push("Typing provocation without volar distribution/median pattern (guardrail -0.05)");
    }
    // Scapholunate instability
    if (zone === "dorsal") {
        S.scapholunate_instability.score += 0.15;
        S.scapholunate_instability.rationale.push("Dorsal central ache");
    }
    if (features.includes("clicking") ||
        features.includes("weak_grip")) {
        S.scapholunate_instability.score += 0.2;
        S.scapholunate_instability.rationale.push("Click/clunk or weak grip");
    }
    if (injList.includes("foosh") ||
        onset === "sudden") {
        S.scapholunate_instability.score += 0.15;
        S.scapholunate_instability.rationale.push("FOOSH/sudden mechanism");
    }
    // Distal radius fracture
    if (injList.length > 0 &&
        (features.includes("swelling") ||
            features.includes("bump_shape"))) {
        S.distal_radius_fracture.score += 0.2;
        S.distal_radius_fracture.rationale.push("Swelling/deformity after injury");
    }
    if (wb === "no") {
        S.distal_radius_fracture.score += 0.2;
        S.distal_radius_fracture.rationale.push("Unable to weight-bear");
    }
    if (wb === "yes_pain" && injList.length > 0) {
        S.distal_radius_fracture.score += 0.1;
        S.distal_radius_fracture.rationale.push("Painful weight-bearing post-injury");
    }
    // CRPS
    if (features.includes("extreme_colour_temp")) {
        S.crps.score += 0.25;
        S.crps.rationale.push("Colour/temperature change and sensitivity");
    }
    if (zone === "diffuse" &&
        features.includes("extreme_colour_temp")) {
        S.crps.score += 0.08;
        S.crps.rationale.push("Diffuse distribution with vasomotor change (+0.08)");
    }
    if (triage === "red") {
        if (systemicRed) {
            S.serious_non_msk.score = 999;
            S.serious_non_msk.rationale.push("Systemic/widespread red flags present – prioritize medical causes");
        }
        else if (injuryRed) {
            if (injuryFlags.includes("deformity") ||
                injuryFlags.includes("no_weight_bear")) {
                S.distal_radius_fracture.score += 0.4;
                S.distal_radius_fracture.rationale.push("Injury red flags (deformity/no weight-bear) – strong suspicion of distal radius fracture (+0.40)");
            }
            if (zone === "radial" &&
                (injList.includes("foosh") ||
                    onset === "sudden")) {
                S.scaphoid_fracture.score += 0.25;
                S.scaphoid_fracture.rationale.push("Injury red flags with radial FOOSH/sudden – scaphoid risk (+0.25)");
            }
        }
    }
    return S;
}
function buildSummary(answers) {
    var _a, _b;
    const get = (id) => answers.find((a) => a.id === id);
    const sidePref = ((_b = (_a = get("Q_side")) === null || _a === void 0 ? void 0 : _a.value) !== null && _b !== void 0 ? _b : undefined);
    const triageInfo = computeTriage(answers);
    const scored = score(answers, triageInfo);
    const ranked = Object.keys(scored)
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
function processWristAssessmentCore(answers) {
    return buildSummary(Array.isArray(answers) ? answers : []);
}
/* ----------------- callable ----------------- */
exports.processWristAssessment = functions
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
        triageRegion: "wrist",
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    }, { merge: true });
    return {
        triageStatus: summary.triage,
        topDifferentials: summary.topDifferentials,
        clinicianSummary: summary,
    };
});
//# sourceMappingURL=processWristAssessment.js.map