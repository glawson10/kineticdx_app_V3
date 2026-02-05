"use strict";
// functions/src/knee/processKneeAssessment.ts
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
/* Knee Region – callable scoring + summary (europe-west1, v1 API) */
const functions = __importStar(require("firebase-functions/v1"));
const firestore_1 = require("firebase-admin/firestore");
const db = (0, firestore_1.getFirestore)();
const diffs = {
    acl: {
        key: "acl",
        name: "ACL rupture / high-grade sprain",
        base: 0.15,
        tests: [
            "Lachman (high sensitivity)",
            "Pivot shift (if tolerated)",
            "Effusion + quad inhibition",
        ],
    },
    pcl: {
        key: "pcl",
        name: "PCL sprain",
        base: 0.08,
        tests: ["Posterior drawer", "Posterior sag sign", "Quadriceps active test"],
    },
    mcl_lcl: {
        key: "mcl_lcl",
        name: "Collateral ligament injury (MCL/LCL)",
        base: 0.1,
        tests: [
            "Valgus / varus stress (30°)",
            "Palpation along ligament",
            "Assess joint line opening",
        ],
    },
    meniscus_mechanical: {
        key: "meniscus_mechanical",
        name: "Meniscal tear / loose body (mechanical)",
        base: 0.14,
        tests: [
            "Joint line tenderness",
            "Thessaly / McMurray",
            "Extension block / bounce home",
        ],
    },
    patellar_instability: {
        key: "patellar_instability",
        name: "Patellar instability / subluxation",
        base: 0.12,
        tests: [
            "Patellar apprehension",
            "Medial glide / lateral tilt",
            "Tracking during squat",
        ],
    },
    pfp: {
        key: "pfp",
        name: "Patellofemoral pain (PFP)",
        base: 0.18,
        tests: [
            "Pain on squat / step-down",
            "Patellar compression (symptom reproduction)",
            "Hip & foot control",
        ],
    },
    patellar_tendinopathy: {
        key: "patellar_tendinopathy",
        name: "Patellar tendinopathy",
        base: 0.14,
        tests: [
            "Inferior pole palpation",
            "Single-leg decline squat",
            "Load tolerance testing",
        ],
    },
    quadriceps_tendinopathy: {
        key: "quadriceps_tendinopathy",
        name: "Quadriceps tendinopathy",
        base: 0.06,
        tests: [
            "Superior patellar pole palpation",
            "Resisted knee extension (mid-range)",
        ],
    },
    itb: {
        key: "itb",
        name: "ITB friction / lateral overload",
        base: 0.1,
        tests: [
            "Palpation lateral femoral epicondyle",
            "Single-leg step-down",
            "Running load review",
        ],
    },
    lateral_compartment_overload: {
        key: "lateral_compartment_overload",
        name: "Lateral compartment overload / OA pattern",
        base: 0.06,
        tests: ["Varus alignment assessment", "Crepitus / joint line palpation"],
    },
    knee_oa: {
        key: "knee_oa",
        name: "Knee osteoarthritis",
        base: 0.12,
        tests: ["ROM incl. extension loss", "Crepitus / bony enlargement", "Sit-to-stand / stairs"],
    },
    prepatellar_bursitis: {
        key: "prepatellar_bursitis",
        name: "Prepatellar / infrapatellar bursitis",
        base: 0.05,
        tests: ["Focal anterior swelling", "Palpation of bursa"],
    },
    referred_hip_spine: {
        key: "referred_hip_spine",
        name: "Referred pain (hip or lumbar spine)",
        base: 0.08,
        tests: ["Hip ROM screen", "Lumbar neuro screen"],
    },
    acute_red_pathway: {
        key: "acute_red_pathway",
        name: "Suspected fracture / locked knee / septic arthritis",
        base: 0.0,
        tests: ["Urgent imaging / medical review", "Neurovascular assessment"],
    },
};
/* ---------------- helpers ---------------- */
const getOne = (answers, id) => {
    const a = answers.find((x) => x.id === id && x.kind === "single");
    return a === null || a === void 0 ? void 0 : a.value;
};
const getMany = (answers, id) => {
    const a = answers.find((x) => x.id === id && x.kind === "multi");
    return Array.isArray(a === null || a === void 0 ? void 0 : a.values) ? a.values : [];
};
const yn = (v) => (v !== null && v !== void 0 ? v : "").toLowerCase() === "yes";
/* ---------------- triage ---------------- */
function computeTriage(answers) {
    const notes = [];
    let triage = "green";
    // NOTE: these IDs must match your Knee Dart workflow
    const cantWB = yn(getOne(answers, "K_rf_cantWB_initial"));
    const locked = yn(getOne(answers, "K_rf_lockedNow"));
    const hotFever = yn(getOne(answers, "K_rf_hotRedFeverish"));
    const numbFoot = yn(getOne(answers, "K_rf_newNumbFoot"));
    const coldPale = yn(getOne(answers, "K_rf_coldPaleFoot"));
    const highEnergy = yn(getOne(answers, "K_rf_highEnergyTrauma"));
    const neuroVasc = numbFoot || coldPale;
    // Force RED
    if (locked) {
        notes.push("True locked knee (cannot fully straighten) — urgent assessment");
        triage = "red";
    }
    if (hotFever) {
        notes.push("Hot/red knee with fever/unwell — septic concern");
        triage = "red";
    }
    if (neuroVasc) {
        notes.push("Neurovascular compromise symptoms");
        triage = "red";
    }
    if (highEnergy && cantWB) {
        notes.push("High-energy trauma + unable to weight-bear (fracture concern)");
        triage = "red";
    }
    // AMBER: significant internal derangement signals (if still green)
    if (triage === "green") {
        const feltPop = yn(getOne(answers, "K_feltPop"));
        const rapidSwelling = yn(getOne(answers, "K_rapidSwellingUnder2h"));
        if (feltPop || rapidSwelling) {
            triage = "amber";
            notes.push("Pop and/or rapid swelling — possible internal derangement");
        }
    }
    return { triage, notes };
}
/* ---------------- scoring ---------------- */
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
    // Core
    const onset = (_a = getOne(answers, "K_onsetType")) !== null && _a !== void 0 ? _a : ""; // e.g. pivotSport/twistCatch/directBlow/overuse/gradual/unknown
    const loc = getMany(answers, "K_painLocation"); // e.g. anterior/medial/lateral/posterior/diffuse
    const trig = getMany(answers, "K_painTriggers"); // e.g. stairs/squatKneel/sitting/running/jumping/none
    const feltPop = yn(getOne(answers, "K_feltPop"));
    const swellingFast = yn(getOne(answers, "K_rapidSwellingUnder2h"));
    const givingWay = yn(getOne(answers, "K_currentInstability"));
    const blockedExtension = yn(getOne(answers, "K_blockedExtension"));
    // Key discriminators (added/used for PFP vs tendon vs OA separation)
    const tendonFocus = yn(getOne(answers, "K_tendonFocus"));
    const stiffMorning = yn(getOne(answers, "K_stiffMorning"));
    const lateralRunPain = yn(getOne(answers, "K_lateralRunPain"));
    /* -------- ACL -------- */
    if (onset === "pivotSport") {
        S.acl.score += 0.4;
        S.acl.why.push("Pivoting mechanism");
    }
    if (feltPop && swellingFast) {
        S.acl.score += 0.5;
        S.acl.why.push("Pop + rapid effusion");
    }
    if (givingWay) {
        S.acl.score += 0.3;
        S.acl.why.push("Instability / giving way");
    }
    // ACL – classic triad override (weight tweak)
    if (onset === "pivotSport" && feltPop && swellingFast) {
        S.acl.score += 0.35;
        S.acl.why.push("Classic ACL triad (pivot + pop + rapid effusion)");
    }
    /* -------- Meniscus / loose body -------- */
    if (onset === "twistCatch") {
        S.meniscus_mechanical.score += 0.4;
        S.meniscus_mechanical.why.push("Twist/catch mechanism");
    }
    if (blockedExtension) {
        S.meniscus_mechanical.score += 0.5;
        S.meniscus_mechanical.why.push("Mechanical block / extension loss");
    }
    /* -------- Collateral ligaments -------- */
    if (onset === "directBlow") {
        S.mcl_lcl.score += 0.28;
        S.mcl_lcl.why.push("Direct blow mechanism (consider collateral injury)");
    }
    if (loc.includes("medial") || loc.includes("lateral")) {
        S.mcl_lcl.score += 0.08;
        S.mcl_lcl.why.push("Medial/lateral pain location (collateral possible)");
    }
    /* -------- PFP -------- */
    const anterior = loc.includes("anterior");
    const pfpTriggers = trig.some((t) => ["stairs", "squatKneel", "sitting"].includes(t));
    if (anterior && pfpTriggers) {
        S.pfp.score += 0.6;
        S.pfp.why.push("Anterior knee pain with stairs/squat/sitting");
    }
    else if (anterior) {
        S.pfp.score += 0.12;
        S.pfp.why.push("Anterior knee pain");
    }
    /* -------- Tendinopathy (patellar/quads) -------- */
    if (tendonFocus) {
        // Weight tweak: tendon focus shifts probability away from generic PFP
        S.pfp.score -= 0.25;
        S.pfp.why.push("Focal tendon pain reduces likelihood of PFP");
        S.patellar_tendinopathy.score += 0.25;
        S.patellar_tendinopathy.why.push("Focal tendon pain supports tendinopathy");
    }
    // If jumping/running is selected, tendinopathy may climb further (optional but helpful)
    if (trig.includes("jumping")) {
        S.patellar_tendinopathy.score += 0.12;
        S.patellar_tendinopathy.why.push("Jump/land load pattern");
        S.quadriceps_tendinopathy.score += 0.06;
    }
    if (trig.includes("running")) {
        S.patellar_tendinopathy.score += 0.06;
    }
    /* -------- ITB -------- */
    if (lateralRunPain) {
        S.itb.score += 0.6;
        S.itb.why.push("Lateral pain with running");
    }
    else if (loc.includes("lateral") && trig.includes("running")) {
        S.itb.score += 0.22;
        S.itb.why.push("Lateral knee pain with running");
    }
    /* -------- OA -------- */
    if (stiffMorning) {
        S.knee_oa.score += 0.25;
        S.knee_oa.why.push("Morning stiffness supports OA");
        // Weight tweak: stiffness reduces PFP likelihood
        S.pfp.score -= 0.15;
        S.pfp.why.push("Morning stiffness reduces likelihood of PFP");
    }
    if (stiffMorning && trig.includes("stairs")) {
        S.knee_oa.score += 0.35;
        S.knee_oa.why.push("Stiffness + stairs/activity pain pattern");
    }
    else if (stiffMorning) {
        S.knee_oa.score += 0.1;
    }
    // Lateral compartment overload (optional soft signal)
    if (loc.includes("lateral") && stiffMorning) {
        S.lateral_compartment_overload.score += 0.18;
        S.lateral_compartment_overload.why.push("Lateral pain with stiffness (compartment overload pattern)");
    }
    /* -------- Patellar instability -------- */
    if (onset === "patellaSlip") {
        S.patellar_instability.score += 0.5;
        S.patellar_instability.why.push("Patella slip/subluxation history");
    }
    if (givingWay && anterior) {
        S.patellar_instability.score += 0.12;
    }
    /* -------- Referred hip/spine -------- */
    // If no clear knee pattern, and no classic trauma signs, bump referred
    if (loc.length === 0 && !feltPop && !blockedExtension && !lateralRunPain) {
        S.referred_hip_spine.score += 0.2;
        S.referred_hip_spine.why.push("No clear knee local pattern — consider hip/spine screen");
    }
    /* -------- clamp (prevent weird negatives) -------- */
    Object.keys(S).forEach((k) => {
        S[k].score = Math.max(S[k].score, -0.2);
    });
    return S;
}
/* ---------------- summary builder ---------------- */
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
        ? ["Urgent imaging / medical review", "Neurovascular assessment"]
        : ["Knee AROM/PROM; effusion check", "Functional: squat/step, gait", "Hip/lumbar screen if unclear"];
    const clinicalToDo = Array.from(new Set([...globalTests, ...top.flatMap((t) => t.objectiveTests)]));
    return {
        region: "Knee",
        triage,
        redFlagNotes: triage === "green" ? [] : notes,
        topDifferentials: top.map((t) => ({ name: t.name, score: t.score })),
        clinicalToDo,
        detailedTop: top,
    };
}
function processKneeAssessmentCore(answers) {
    return buildSummary(Array.isArray(answers) ? answers : []);
}
/* ----------------- callable ----------------- */
exports.processKneeAssessment = functions
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
        triageRegion: "knee",
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    }, { merge: true });
    return {
        triageStatus: summary.triage,
        topDifferentials: summary.topDifferentials,
        clinicianSummary: summary,
    };
});
//# sourceMappingURL=processKneeAssessment.js.map