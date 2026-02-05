"use strict";
// functions/src/shoulder/processShoulderAssessment.ts
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
const functions = __importStar(require("firebase-functions/v1"));
const firestore_1 = require("firebase-admin/firestore");
const db = (0, firestore_1.getFirestore)();
const yn = (v) => v === true || v === "yes" || v === "Yes" ? "yes" : "no";
/* ----------------- normalize ----------------- */
/**
 * IMPORTANT:
 * - Your Dart now saves answers.tenderSpot (mapped to: ac_point | bicipital_groove | none_unsure)
 * - This TS reads from Firestore: doc.answers.region.shoulder.answers
 * - So we just need to include tenderSpot here and score it.
 */
function normalizeShoulderAnswers(raw) {
    var _a, _b, _c, _d, _e, _f, _g, _h;
    const answers = (_b = (_a = raw === null || raw === void 0 ? void 0 : raw.answers) !== null && _a !== void 0 ? _a : raw) !== null && _b !== void 0 ? _b : {};
    const rf = (_d = (_c = raw === null || raw === void 0 ? void 0 : raw.redFlags) !== null && _c !== void 0 ? _c : answers === null || answers === void 0 ? void 0 : answers.redFlags) !== null && _d !== void 0 ? _d : {};
    return {
        side: (_e = answers.side) !== null && _e !== void 0 ? _e : "",
        dominant: yn(answers.dominant), // legacy (kept; not used for scoring)
        onset: (_f = answers.onset) !== null && _f !== void 0 ? _f : "", // gradual | afterOverhead | afterLiftPull | minorFallJar | appeared (if you add later)
        painArea: (_g = answers.painArea) !== null && _g !== void 0 ? _g : "", // top_front | outer_side | back | diffuse
        nightPain: yn(answers.nightPain),
        overhead_aggravates: yn(answers.overheadAggravates),
        weakness: yn(answers.weakness),
        stiffness: yn(answers.stiffness),
        clicking: yn(answers.clicking),
        neckInvolved: yn(answers.neckInvolved),
        handNumbness: yn(answers.handNumbness),
        // ✅ discriminator question from Dart
        // expected: "ac_point" | "bicipital_groove" | "none_unsure" | ""
        tenderSpot: (_h = answers.tenderSpot) !== null && _h !== void 0 ? _h : "",
        functionLimits: Array.isArray(answers.functionLimits)
            ? answers.functionLimits
            : Array.isArray(answers.functionLimits)
                ? answers.functionLimits
                : Array.isArray(answers.functionLimits)
                    ? answers.functionLimits
                    : Array.isArray(answers.functionLimits)
                        ? answers.functionLimits
                        : Array.isArray(answers.functionLimits)
                            ? answers.functionLimits
                            : Array.isArray(answers.functionLimits)
                                ? answers.functionLimits
                                : Array.isArray(answers.functionLimits)
                                    ? answers.functionLimits
                                    : Array.isArray(answers.functionLimits)
                                        ? answers.functionLimits
                                        : Array.isArray(answers.functionLimits)
                                            ? answers.functionLimits
                                            : Array.isArray(answers.functionLimits)
                                                ? answers.functionLimits
                                                : Array.isArray(answers.functionLimits)
                                                    ? answers.functionLimits
                                                    : Array.isArray(answers.functionLimits)
                                                        ? answers.functionLimits
                                                        : Array.isArray(answers.functionLimits)
                                                            ? answers.functionLimits
                                                            : Array.isArray(answers.functionLimits)
                                                                ? answers.functionLimits
                                                                : Array.isArray(answers.functionLimits)
                                                                    ? answers.functionLimits
                                                                    : Array.isArray(answers.functionLimits)
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
/**
 * Differential meta (scores + tests)
 * NOTE: this stays exactly as you wrote it.
 */
const diffs = {
    acute_red_pathway: {
        name: "Red flag pathway (urgent)",
        base: 100,
        tests: [],
    },
    subacromial_pain: {
        name: "Subacromial pain / rotator cuff related pain",
        base: 10,
        tests: ["Painful arc", "Resisted ER", "Empty can / Jobe"],
    },
    adhesive_capsulitis: {
        name: "Adhesive capsulitis",
        base: 9,
        tests: ["ER ROM loss", "Capsular pattern assessment"],
    },
    biceps_tendinopathy: {
        name: "Biceps tendon / long head biceps pain",
        base: 8,
        tests: ["Speed’s", "Yergason’s", "Bicipital groove palpation"],
    },
    ac_joint_pain: {
        name: "AC joint pain",
        base: 8,
        tests: ["AC palpation", "Cross-body adduction"],
    },
    cervical_referral: {
        name: "Cervical referral / radiculopathy features",
        base: 7,
        tests: ["Spurling", "Distraction", "ULNT"],
    },
    rotator_cuff_tear: {
        name: "Rotator cuff tear (possible)",
        base: 7,
        tests: ["Drop arm", "ER lag sign", "External rotation strength"],
    },
};
/* ----------------- triage ----------------- */
function computeTriage(a) {
    const rf = a.redFlags;
    const notes = [];
    // RED if infection / deformity / neuro / constant unrelenting / cancer / high-energy trauma
    if (rf.fever_or_hot_red_joint === "yes")
        notes.push("Hot/red joint with fever");
    if (rf.deformity_after_injury === "yes")
        notes.push("Deformity after injury");
    if (rf.new_neuro_symptoms === "yes")
        notes.push("New neurological symptoms");
    if (rf.constant_unrelenting_pain === "yes")
        notes.push("Constant unrelenting pain");
    if (rf.cancer_history_or_weight_loss === "yes")
        notes.push("Cancer history/weight loss");
    if (rf.trauma_high_energy === "yes")
        notes.push("High-energy trauma");
    if (notes.length > 0)
        return { triage: "red", notes };
    // AMBER if cannot actively elevate
    if (rf.can_active_elevate === "no") {
        return { triage: "amber", notes: ["Cannot actively elevate to shoulder height"] };
    }
    return { triage: "green", notes: [] };
}
/* ----------------- scoring ----------------- */
function score(a, triage) {
    const s = {
        acute_red_pathway: { score: 0, why: [] },
        subacromial_pain: { score: diffs.subacromial_pain.base, why: [] },
        adhesive_capsulitis: { score: diffs.adhesive_capsulitis.base, why: [] },
        biceps_tendinopathy: { score: diffs.biceps_tendinopathy.base, why: [] },
        ac_joint_pain: { score: diffs.ac_joint_pain.base, why: [] },
        cervical_referral: { score: diffs.cervical_referral.base, why: [] },
        rotator_cuff_tear: { score: diffs.rotator_cuff_tear.base, why: [] },
    };
    // Red pathway
    if (triage === "red") {
        s.acute_red_pathway.score = 999;
        s.acute_red_pathway.why.push("Red flag triggers present");
        return s;
    }
    // Pain area + overhead
    if (a.overhead_aggravates === "yes") {
        s.subacromial_pain.score += 5;
        s.subacromial_pain.why.push("Overhead aggravation");
    }
    // Weakness -> cuff tear or cuff-related
    if (a.weakness === "yes") {
        s.rotator_cuff_tear.score += 6;
        s.rotator_cuff_tear.why.push("Weakness reported");
        s.subacromial_pain.score += 2;
    }
    // Stiffness + night pain -> adhesive
    if (a.stiffness === "yes") {
        s.adhesive_capsulitis.score += 5;
        s.adhesive_capsulitis.why.push("Stiffness reported");
    }
    if (a.nightPain === "yes") {
        s.adhesive_capsulitis.score += 2;
        s.adhesive_capsulitis.why.push("Night pain");
    }
    // Neck + hand numbness -> cervical referral
    if (a.neckInvolved === "yes" || a.handNumbness === "yes") {
        s.cervical_referral.score += 5;
        s.cervical_referral.why.push("Neck involvement or hand numbness");
    }
    // Tender spot discriminator
    if (a.tenderSpot === "bicipital_groove") {
        s.biceps_tendinopathy.score += 6;
        s.biceps_tendinopathy.why.push("Tender at bicipital groove");
    }
    else if (a.tenderSpot === "ac_point") {
        s.ac_joint_pain.score += 6;
        s.ac_joint_pain.why.push("Tender at AC joint");
    }
    // Clicking -> biceps/cuff related
    if (a.clicking === "yes") {
        s.biceps_tendinopathy.score += 2;
        s.biceps_tendinopathy.why.push("Clicking");
        s.subacromial_pain.score += 1;
    }
    // Amber: cannot elevate suggests tear
    if (triage === "amber") {
        s.rotator_cuff_tear.score += 4;
        s.rotator_cuff_tear.why.push("Cannot actively elevate to shoulder height");
    }
    return s;
}
/* ----------------- summary ----------------- */
function buildSummary(raw) {
    const a = normalizeShoulderAnswers(raw);
    const { triage, notes } = computeTriage(a);
    const scored = score(a, triage);
    const ranked = Object.keys(scored)
        .filter((k) => (triage === "red" ? true : k !== "acute_red_pathway"))
        .map((k) => ({ key: k, ...scored[k] }))
        .sort((x, y) => y.score - x.score || diffs[y.key].base - diffs[x.key].base);
    const top = ranked.slice(0, triage === "red" ? 1 : 3).map((r) => ({
        name: diffs[r.key].name,
        score: Number(Math.max(0, r.score).toFixed(2)),
        rationale: r.why,
        objectiveTests: diffs[r.key].tests,
    }));
    const clinicalToDo = triage === "red"
        ? {
            primary: "Urgent medical review indicated due to red flag triggers.",
            secondary: "Do not delay; consider ED/urgent referral depending on severity.",
        }
        : triage === "amber"
            ? {
                primary: "Consider urgent assessment for possible significant tissue injury.",
                secondary: "Objective testing + clinician review recommended.",
            }
            : {
                primary: "Proceed with standard MSK assessment and objective testing.",
                secondary: "Likely non-urgent shoulder presentation.",
            };
    return {
        region: "Shoulder",
        triage,
        redFlagNotes: triage === "green" ? [] : notes,
        topDifferentials: top.map((t) => ({ name: t.name, score: t.score })),
        clinicalToDo,
        detailedTop: top,
    };
}
/**
 * ✅ NEW: Pure core export used by Phase-3 intake summary generation.
 * This keeps the scoring EXACT (same buildSummary function).
 */
function processShoulderAssessmentCore(raw) {
    return buildSummary(raw);
}
/* ----------------- callable ----------------- */
exports.processShoulderAssessment = functions
    .region("europe-west1")
    .https.onCall(async (data) => {
    var _a, _b;
    const assessmentId = data === null || data === void 0 ? void 0 : data.assessmentId;
    if (!assessmentId) {
        throw new functions.https.HttpsError("invalid-argument", "Missing assessmentId");
    }
    const docRef = db.collection("assessments").doc(assessmentId);
    const snap = await docRef.get();
    const doc = snap.data() || {};
    // Matches your current pattern: shoulder answers live in doc.answers.region.shoulder
    const shoulder = ((_b = (_a = doc === null || doc === void 0 ? void 0 : doc.answers) === null || _a === void 0 ? void 0 : _a.region) === null || _b === void 0 ? void 0 : _b.shoulder) || {};
    const summary = buildSummary(shoulder);
    await docRef.set({
        summary: {
            shoulder: summary,
        },
        processedAt: firestore_1.FieldValue.serverTimestamp(),
    }, { merge: true });
    return { ok: true, summary };
});
//# sourceMappingURL=processShoulderAssessment.js.map