"use strict";
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
exports.processThoracicAssessment = void 0;
exports.buildSummary = buildSummary;
const functions = __importStar(require("firebase-functions/v1"));
const firestore_1 = require("firebase-admin/firestore");
const db = (0, firestore_1.getFirestore)();
const diffs = {
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
const getOne = (answers, id) => { var _a, _b; return (_b = (_a = answers.find((a) => a.id === id && a.kind === "single")) === null || _a === void 0 ? void 0 : _a.value) !== null && _b !== void 0 ? _b : ""; };
const getMany = (answers, id) => { var _a, _b; return (_b = (_a = answers.find((a) => a.id === id && a.kind === "multi")) === null || _a === void 0 ? void 0 : _a.values) !== null && _b !== void 0 ? _b : []; };
/* ---------------- triage ---------------- */
function computeTriage(answers) {
    const notes = [];
    let triage = "green";
    const trauma = getOne(answers, "Q1_trauma");
    const redcluster = getMany(answers, "Q2_redcluster").filter((x) => x !== "none");
    const neuro = getMany(answers, "Q3_neuro").filter((x) => x !== "none");
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
function score(answers, triage) {
    const S = Object.keys(diffs).reduce((acc, k) => {
        acc[k] = { score: diffs[k].base, why: [] };
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
    if (worse.some((w) => ["twist", "overhead", "lift"].includes(w))) {
        S.facet.score += 0.3;
    }
    /* Rib joint – gated */
    if (breath === "local_sharp" &&
        loc !== "front_chest" &&
        (worse.includes("bed") || worse.includes("breath"))) {
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
    if (trauma === "minor" &&
        painNow >= 7 &&
        better.includes("nothing")) {
        S.compression_fracture.score += 0.45;
        S.compression_fracture.why.push("Minor trauma + severe constant pain");
    }
    /* Visceral / serious awareness */
    const redcluster = getMany(answers, "Q2_redcluster").filter((x) => x !== "none");
    if (redcluster.length > 0) {
        S.serious_non_msk.score += 0.1;
    }
    return S;
}
/* ---------------- summary ---------------- */
function buildSummary(answers) {
    const { triage, notes } = computeTriage(answers);
    const scored = score(answers, triage);
    const ranked = Object.keys(scored)
        .map((k) => ({ key: k, ...scored[k] }))
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
exports.processThoracicAssessment = functions
    .region("europe-west1")
    .https.onCall(async (data, _ctx) => {
    const assessmentId = data === null || data === void 0 ? void 0 : data.assessmentId;
    const answers = Array.isArray(data === null || data === void 0 ? void 0 : data.answers) ? data.answers : [];
    const summary = buildSummary(answers);
    if (assessmentId) {
        await db
            .collection("assessments")
            .doc(assessmentId)
            .set({
            triageRegion: "thoracic",
            triageStatus: summary.triage,
            topDifferentials: summary.topDifferentials,
            clinicianSummary: summary,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        }, { merge: true });
    }
    return summary;
});
//# sourceMappingURL=buildThoracicSummary.js.map