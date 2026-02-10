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
exports.processShoulderAssessment = void 0;
exports.processShoulderAssessmentCore = processShoulderAssessmentCore;
// TypeScript logic for shoulder region — mirrored from hip-region scoring structure
const functions = __importStar(require("firebase-functions/v1"));
const firestore_1 = require("firebase-admin/firestore");
const db = (0, firestore_1.getFirestore)();
const diffs = {
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
const getOne = (answers, id) => {
    const a = answers.find((x) => x.id === id && x.kind === "single");
    return a === null || a === void 0 ? void 0 : a.value;
};
const getMany = (answers, id) => {
    const a = answers.find((x) => x.id === id && x.kind === "multi");
    return Array.isArray(a === null || a === void 0 ? void 0 : a.values) ? a.values : [];
};
const yn = (v) => (v !== null && v !== void 0 ? v : "").toLowerCase() === "yes";
function computeTriage(answers) {
    const notes = [];
    let triage = "green";
    const trauma = yn(getOne(answers, "S_rf_trauma_high_energy"));
    const deformity = yn(getOne(answers, "S_rf_deformity_after_injury"));
    const unrelenting = yn(getOne(answers, "S_rf_constant_unrelenting_pain"));
    const feverHotJoint = yn(getOne(answers, "S_rf_fever_or_hot_red_joint"));
    const cancer = yn(getOne(answers, "S_rf_cancer_or_weight_loss"));
    const canElevate = yn(getOne(answers, "S_rf_can_active_elevate"));
    if (!canElevate || trauma || deformity || unrelenting || feverHotJoint) {
        triage = "red";
        if (!canElevate)
            notes.push("Unable to elevate arm actively");
        if (trauma)
            notes.push("Recent trauma or fall");
        if (deformity)
            notes.push("Visible deformity or dislocation suspected");
        if (unrelenting)
            notes.push("Constant pain, unrelenting at rest");
        if (feverHotJoint)
            notes.push("Possible septic joint or inflammation");
    }
    else if (cancer) {
        triage = "amber";
        notes.push("History of cancer or unexplained weight loss");
    }
    return { triage, notes };
}
function score(answers, triage) {
    var _a, _b;
    const S = Object.keys(diffs).reduce((acc, k) => {
        acc[k] = { score: diffs[k].base, why: [] };
        return acc;
    }, {});
    if (triage === "red") {
        S.acute_red_pathway.score = 999;
        S.acute_red_pathway.why.push("Red-flag criteria met");
        return S;
    }
    S.acute_red_pathway.score = -Infinity;
    const area = (_a = getOne(answers, "S_pain_area")) !== null && _a !== void 0 ? _a : "";
    const overhead = yn(getOne(answers, "S_overhead_aggs"));
    const stiffness = yn(getOne(answers, "S_stiffness"));
    const weakness = yn(getOne(answers, "S_weakness"));
    const neck = yn(getOne(answers, "S_neck_involved"));
    const tender = (_b = getOne(answers, "S_tender_spot")) !== null && _b !== void 0 ? _b : "";
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
function buildSummary(answers) {
    const { triage, notes } = computeTriage(answers);
    const scored = score(answers, triage);
    const ranked = Object.keys(scored)
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
    const globalTests = triage === "red"
        ? [
            "Urgent imaging (X-ray ± bloods)",
            "Neurovascular check; deformity observation",
        ]
        : [
            "Shoulder AROM/PROM assessment",
            "Neck screen; Spurling's + myotomes",
            "Functional scapula control (wall push-up, elevation reps)",
        ];
    const clinicalToDo = Array.from(new Set([...globalTests, ...top.flatMap((t) => t.objectiveTests)]));
    return {
        region: "Shoulder",
        triage,
        redFlagNotes: triage === "green" ? [] : notes,
        topDifferentials: top.map((t) => ({ name: t.name, score: t.score })),
        clinicalToDo,
        detailedTop: top,
    };
}
async function processShoulderAssessmentCore(data, _ctx) {
    const assessmentId = data === null || data === void 0 ? void 0 : data.assessmentId;
    // Support both { answers: [...] } and direct array
    const answers = Array.isArray(data === null || data === void 0 ? void 0 : data.answers)
        ? data.answers
        : Array.isArray(data)
            ? data
            : [];
    const summary = buildSummary(answers);
    // Only write to Firestore if assessmentId is provided
    if (assessmentId) {
        await db
            .collection("assessments")
            .doc(assessmentId)
            .set({
            triageStatus: summary.triage,
            topDifferentials: summary.topDifferentials,
            clinicianSummary: summary,
            triageRegion: "shoulder",
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        }, { merge: true });
        // Return wrapped shape for backward compatibility with callable
        return {
            triageStatus: summary.triage,
            topDifferentials: summary.topDifferentials,
            clinicianSummary: summary,
        };
    }
    // Return raw summary object for decision support / summary builders
    return summary;
}
// -------------------------------
// Firebase callable wrapper
// -------------------------------
exports.processShoulderAssessment = functions
    .region("europe-west1")
    .https.onCall(async (data, ctx) => {
    return processShoulderAssessmentCore(data, ctx);
});
//# sourceMappingURL=processShoulderAssessment.js.map