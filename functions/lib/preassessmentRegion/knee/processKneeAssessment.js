"use strict";
// functions/src/lumbar/processLumbarAssessment.ts
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
exports.processKneeAssessment = void 0;
exports.processKneeAssessmentCore = processKneeAssessmentCore;
/* Lumbar Spine Region – callable scoring + summary (europe-west1, v1 API) */
const functions = __importStar(require("firebase-functions/v1"));
const firestore_1 = require("firebase-admin/firestore");
const db = (0, firestore_1.getFirestore)();
/* ----------------- differential library ----------------- */
const diffs = {
    mechanical_nslbp: {
        key: "mechanical_nslbp",
        name: "Mechanical non-specific low back pain",
        base: 0.22,
        tests: [
            "Lumbar AROM/PROM (flex/ext/side-bend/rotation) + symptom response",
            "Repeated movements (centralisation/peripheralisation screening)",
            "Functional tasks (sit–stand, lifting, gait)",
        ],
    },
    disc_radiculopathy: {
        key: "disc_radiculopathy",
        name: "Lumbar disc-related radiculopathy",
        base: 0.14,
        tests: [
            "SLR + crossed SLR (as indicated)",
            "Slump test (neural mechanosensitivity)",
            "Dermatomes, myotomes, reflexes (baseline + re-test)",
        ],
    },
    facet_joint: {
        key: "facet_joint",
        name: "Lumbar facet joint pain",
        base: 0.16,
        tests: [
            "Extension + rotation quadrant (symptom reproduction)",
            "Segmental PA springing (irritability/local tenderness)",
            "Pain with prolonged standing/extension bias",
        ],
    },
    sij_related: {
        key: "sij_related",
        name: "SIJ-related pain",
        base: 0.12,
        tests: [
            "SIJ provocation cluster (Laslett-style; ≥3/5 as higher suspicion)",
            "ASLR / load transfer tests (if pelvic girdle features)",
            "Pain response to compression/distraction (as part of cluster)",
        ],
    },
    spinal_stenosis: {
        key: "spinal_stenosis",
        name: "Lumbar spinal stenosis",
        base: 0.1,
        tests: [
            "Walking tolerance + symptom behaviour (incl. ‘shopping cart sign’)",
            "Repeated extension vs flexion bias (symptom change)",
            "Neuro screen (often bilateral / multilevel pattern)",
        ],
    },
    spondylolysis_spondylolisthesis: {
        key: "spondylolysis_spondylolisthesis",
        name: "Spondylolysis / spondylolisthesis",
        base: 0.08,
        tests: [
            "Single-leg extension test (pain provocation; interpret cautiously)",
            "Step-off palpation (if clinically indicated)",
            "Extension loading + sport-specific tolerance",
        ],
    },
    inflammatory_axial: {
        key: "inflammatory_axial",
        name: "Inflammatory axial back pain (axSpA pattern)",
        base: 0.05,
        tests: [
            "Morning stiffness duration; response to exercise vs rest",
            "Night pain pattern; alternating buttock pain history",
            "Consider rheumatology screen / inflammatory markers as indicated",
        ],
    },
    // Base = 0 and only ranks if triage === 'red'
    acute_red_pathway: {
        key: "acute_red_pathway",
        name: "Suspected fracture, malignancy, infection, CES",
        base: 0.0,
        tests: [
            "Urgent imaging and/or bloods as indicated",
            "Full neuro screen + saddle region + bladder/bowel",
            "Urgent medical/surgical referral pathway",
        ],
    },
};
/* ----------------- helpers ----------------- */
const getOne = (answers, id) => {
    const a = answers.find((x) => x.id === id && x.kind === "single");
    return a === null || a === void 0 ? void 0 : a.value;
};
const getMany = (answers, id) => {
    const a = answers.find((x) => x.id === id && x.kind === "multi");
    return Array.isArray(a === null || a === void 0 ? void 0 : a.values) ? a.values : [];
};
const yn = (v) => (v !== null && v !== void 0 ? v : "").toLowerCase() === "yes";
/* ----------------- triage ----------------- */
function computeTriage(answers) {
    var _a;
    const notes = [];
    let triage = "green";
    const trauma = yn(getOne(answers, "L_rf_trauma"));
    const cantWB = yn(getOne(answers, "L_rf_cant_weightbear"));
    const fever = yn(getOne(answers, "L_rf_fever"));
    const caHistory = yn(getOne(answers, "L_rf_cancer_history"));
    const nightPain = yn(getOne(answers, "L_rf_night_pain"));
    const weightLoss = yn(getOne(answers, "L_rf_weight_loss"));
    const saddle = yn(getOne(answers, "L_rf_saddle"));
    const bladder = yn(getOne(answers, "L_rf_bladder"));
    const progressiveWeakness = yn(getOne(answers, "L_rf_progressive_weakness"));
    // Inflammatory pattern (AMBER only)
    const morning = ((_a = getOne(answers, "L_morning")) !== null && _a !== void 0 ? _a : ""); // short/medium/long
    const inflammatoryCluster = morning === "long" && nightPain;
    // RED
    if (saddle || bladder) {
        notes.push("Possible cauda equina features (saddle/bladder)");
        triage = "red";
    }
    if (progressiveWeakness) {
        notes.push("Progressive neurological weakness");
        triage = "red";
    }
    if (trauma && cantWB) {
        notes.push("Trauma with inability to weight-bear");
        triage = "red";
    }
    if (fever && nightPain) {
        notes.push("Fever + night pain (infection concern)");
        triage = "red";
    }
    if (caHistory && (nightPain || weightLoss)) {
        notes.push("Cancer history with night pain/weight loss");
        triage = "red";
    }
    // AMBER
    if (triage === "green" && (trauma || fever || caHistory || weightLoss)) {
        notes.push("Systemic/trauma risk factor present");
        triage = "amber";
    }
    if (triage === "green" && inflammatoryCluster) {
        notes.push("Inflammatory pattern (long morning stiffness + night pain)");
        triage = "amber";
    }
    return { triage, notes };
}
/* ----------------- scoring ----------------- */
function score(answers, triage) {
    var _a;
    const S = Object.keys(diffs).reduce((acc, k) => {
        acc[k] = { score: diffs[k].base, why: [] };
        return acc;
    }, {});
    // If RED → short-circuit acute pathway
    if (triage === "red") {
        S.acute_red_pathway.score = 999;
        S.acute_red_pathway.why.push("Red-flag criteria met");
        return S;
    }
    // Otherwise exclude acute pathway entirely
    S.acute_red_pathway.score = -Infinity;
    // Pull fields
    const where = getMany(answers, "L_where"); // back/buttock/leg/below_knee
    const aggs = getMany(answers, "L_aggs"); // flexion/extension/walk/stand/sit/sit_to_stand
    const morning = ((_a = getOne(answers, "L_morning")) !== null && _a !== void 0 ? _a : "");
    const nightPain = yn(getOne(answers, "L_rf_night_pain"));
    const neuro = yn(getOne(answers, "L_neuro"));
    const ageOver50 = yn(getOne(answers, "L_age_over_50"));
    const legDominant = where.includes("below_knee") || where.includes("leg");
    const hasBack = where.includes("back");
    const hasButtock = where.includes("buttock");
    const flexionAgg = aggs.includes("flexion");
    const extensionAgg = aggs.includes("extension");
    const walkingAgg = aggs.includes("walk");
    const standingAgg = aggs.includes("stand");
    const sittingAgg = aggs.includes("sit");
    const sitToStandAgg = aggs.includes("sit_to_stand");
    /* ---- Mechanical NSLBP ---- */
    if (flexionAgg || extensionAgg) {
        S.mechanical_nslbp.score += 0.18;
        S.mechanical_nslbp.why.push("Movement-related pain (flexion/extension bias)");
    }
    if (hasBack && !neuro) {
        S.mechanical_nslbp.score += 0.1;
        S.mechanical_nslbp.why.push("Localised back pain without neurological features");
    }
    if (!legDominant && (standingAgg || sittingAgg || walkingAgg)) {
        S.mechanical_nslbp.score += 0.06;
        S.mechanical_nslbp.why.push("Activity/posture sensitivity without radicular dominance");
    }
    /* ---- Disc radiculopathy ---- */
    if (legDominant) {
        S.disc_radiculopathy.score += 0.25;
        S.disc_radiculopathy.why.push("Leg-dominant symptoms (± below knee)");
    }
    if (neuro) {
        S.disc_radiculopathy.score += 0.25;
        S.disc_radiculopathy.why.push("Neurological symptoms present");
    }
    if (flexionAgg) {
        S.disc_radiculopathy.score += 0.1;
        S.disc_radiculopathy.why.push("Flexion sensitivity fits disc/neural pattern");
    }
    if (nightPain && legDominant) {
        S.disc_radiculopathy.score += 0.04;
    }
    /* ---- Facet ---- */
    if (extensionAgg && standingAgg) {
        S.facet_joint.score += 0.32;
        S.facet_joint.why.push("Extension + standing aggravation cluster");
    }
    else if (extensionAgg) {
        S.facet_joint.score += 0.12;
        S.facet_joint.why.push("Extension sensitivity (weaker facet signal)");
    }
    if (hasBack && !neuro && extensionAgg) {
        S.facet_joint.score += 0.06;
    }
    /* ---- SIJ ---- */
    if (hasButtock) {
        S.sij_related.score += 0.22;
        S.sij_related.why.push("Buttock-dominant pain");
    }
    if (sitToStandAgg) {
        S.sij_related.score += 0.12;
        S.sij_related.why.push("Sit-to-stand aggravation");
    }
    if (hasButtock && !legDominant && !neuro) {
        S.sij_related.score += 0.06;
    }
    /* ---- Stenosis ---- */
    if (ageOver50 && walkingAgg) {
        S.spinal_stenosis.score += 0.3;
        S.spinal_stenosis.why.push("Age >50 with walking intolerance pattern");
    }
    else if (walkingAgg) {
        S.spinal_stenosis.score += 0.08;
    }
    if (flexionAgg && walkingAgg) {
        S.spinal_stenosis.score += 0.22;
        S.spinal_stenosis.why.push("Flexion bias with walking-related symptoms");
    }
    if (legDominant && ageOver50 && walkingAgg) {
        S.spinal_stenosis.score += 0.08;
    }
    /* ---- Spondylolysis / spondylolisthesis ---- */
    if (extensionAgg && ageOver50 === false) {
        S.spondylolysis_spondylolisthesis.score += 0.22;
        S.spondylolysis_spondylolisthesis.why.push("Extension loading in younger patient (pars/spondy spectrum)");
    }
    else if (extensionAgg) {
        S.spondylolysis_spondylolisthesis.score += 0.06;
    }
    /* ---- Inflammatory axial ---- */
    if (morning === "long" && nightPain) {
        S.inflammatory_axial.score += 0.35;
        S.inflammatory_axial.why.push("Long morning stiffness + night pain (inflammatory pattern)");
    }
    else if (morning === "long") {
        S.inflammatory_axial.score += 0.12;
        S.inflammatory_axial.why.push("Long morning stiffness (partial inflammatory signal)");
    }
    else if (nightPain) {
        S.inflammatory_axial.score += 0.08;
        S.inflammatory_axial.why.push("Night pain (non-specific; interpret with other features)");
    }
    if (neuro && legDominant) {
        S.inflammatory_axial.score -= 0.06;
    }
    return S;
}
/* ----------------- summary builder ----------------- */
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
            "Urgent neuro screen incl. saddle + bladder/bowel",
            "Vitals + systemic screen as indicated",
            "Urgent referral / imaging pathway as appropriate",
        ]
        : [
            "Lumbar AROM/PROM + symptom behaviour",
            "Neuro screen if leg symptoms or red/yellow flags",
            "Functional provocation (sit–stand, walking tolerance)",
        ];
    const clinicalToDo = Array.from(new Set([...globalTests, ...top.flatMap((t) => t.objectiveTests)]));
    return {
        region: "Lumbar spine",
        triage,
        redFlagNotes: triage === "green" ? [] : notes,
        topDifferentials: top.map((t) => ({ name: t.name, score: t.score })),
        clinicalToDo,
        detailedTop: top,
    };
}
/* ----------------- callable ----------------- */
async function processKneeAssessmentCore(data, _ctx) {
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
            triageRegion: "knee",
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
exports.processKneeAssessment = functions
    .region("europe-west1")
    .https.onCall(async (data, ctx) => {
    return processKneeAssessmentCore(data, ctx);
});
//# sourceMappingURL=processKneeAssessment.js.map