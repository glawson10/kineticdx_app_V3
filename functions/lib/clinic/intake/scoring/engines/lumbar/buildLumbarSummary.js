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
exports.processLumbarAssessment = void 0;
exports.buildSummary = buildSummary;
const functions = __importStar(require("firebase-functions/v1"));
const firestore_1 = require("firebase-admin/firestore");
const db = (0, firestore_1.getFirestore)();
const Y = (v) => v === "yes" || v === true;
function normalizeAnswers(src) {
    const out = {};
    for (const [k, v] of Object.entries(src || {})) {
        out[k] = typeof v === "boolean" ? (v ? "yes" : "no") : v;
    }
    return out;
}
function triageColour(a) {
    const notes = [];
    let triage = "green";
    const bladderBowel = Y(a["L_rf_bladderBowel"]);
    const saddleNumb = Y(a["L_rf_saddleNumbness"]);
    const progWeak = Y(a["L_rf_progressiveWeak"]);
    const feverChills = Y(a["L_rf_fever"]);
    const caHistory = Y(a["L_rf_cancerHistory"]);
    const highEnergy = Y(a["L_rf_highEnergyTrauma"]);
    const nightNoRel = Y(a["L_rf_nightConstant"]);
    if (bladderBowel) {
        notes.push("New bladder/bowel dysfunction (CES risk)");
        triage = "red";
    }
    if (saddleNumb) {
        notes.push("Saddle/groin numbness");
        triage = "red";
    }
    if (progWeak) {
        notes.push("Rapidly progressive neuro deficit");
        triage = "red";
    }
    if (feverChills && nightNoRel) {
        notes.push("Infection red flags");
        triage = "red";
    }
    if (caHistory && nightNoRel) {
        notes.push("Malignancy red flags");
        triage = "red";
    }
    if (highEnergy && progWeak) {
        notes.push("High-energy trauma with neuro deficit");
        triage = "red";
    }
    if (triage === "green" &&
        (feverChills || caHistory || nightNoRel || highEnergy)) {
        notes.push("Systemic/trauma features present");
        triage = "amber";
    }
    return { triage, notes };
}
function hasAgg(a, code) {
    return Array.isArray(a["L_aggs"]) && a["L_aggs"].includes(code);
}
function hasEase(a, code) {
    return Array.isArray(a["L_eases"]) && a["L_eases"].includes(code);
}
function hasWhereLeg(a, code) {
    return (Array.isArray(a["L_whereLeg"]) && a["L_whereLeg"].includes(code));
}
const dx = {
    disc_radiculopathy: {
        name: "Lumbar discogenic radiculopathy",
        base: 0.8,
        include: (a) => {
            let s = 0;
            if (hasWhereLeg(a, "belowKnee") || hasWhereLeg(a, "foot"))
                s += 1.0;
            if (Y(a["L_pinsNeedles"]) || Y(a["L_numbness"]))
                s += 0.6;
            if (hasAgg(a, "bendLift"))
                s += 0.6;
            if (hasAgg(a, "coughSneeze"))
                s += 0.6;
            if (hasEase(a, "backArched"))
                s += 0.2;
            return s;
        },
        tests: [
            "Neuro screen (myo/derm/reflex, SLR/Slump)",
            "Lumbar flexion/centralization trial",
            "Hip ROM; crossed SLR if severe",
        ],
    },
    spinal_stenosis: {
        name: "Lumbar spinal stenosis / neurogenic claudication",
        base: 0.7,
        include: (a) => {
            let s = 0;
            const age = a["L_age_band"];
            if (age === "65+" || age === "51-65")
                s += 0.8;
            if (hasAgg(a, "walk"))
                s += 0.8;
            if (hasEase(a, "lieKneesBent"))
                s += 0.6;
            if (hasAgg(a, "extend"))
                s += 0.6;
            if (a["L_painPattern"] === "bothSides" &&
                (hasWhereLeg(a, "thigh") ||
                    hasWhereLeg(a, "belowKnee") ||
                    hasWhereLeg(a, "foot")))
                s += 0.4;
            return s;
        },
        tests: [
            "Treadmill/extension provocation vs flexion relief",
            "Neuro screen; femoral nerve tension if anterior thigh",
            "Hip flexion in standing (Psoas sign) as needed",
        ],
    },
    facet_joint: {
        name: "Facet joint–dominant low back pain",
        base: 0.5,
        include: (a) => {
            let s = 0;
            const buttocky = hasWhereLeg(a, "buttock") &&
                !hasWhereLeg(a, "belowKnee") &&
                !hasWhereLeg(a, "foot");
            if (buttocky)
                s += 0.5;
            if (hasAgg(a, "extend"))
                s += 0.4;
            if (hasEase(a, "lieKneesBent"))
                s += 0.3;
            return s;
        },
        tests: [
            "Extension/rotation quadrant test",
            "Segmental PA provocation",
            "Assess hip ext ROM & lumbopelvic control",
        ],
    },
    sij_related: {
        name: "SIJ-related pain",
        base: 0.4,
        include: (a) => {
            let s = 0;
            if (hasWhereLeg(a, "buttock"))
                s += 0.3;
            if (hasAgg(a, "bendLift"))
                s += 0.5;
            return s;
        },
        tests: [
            "SIJ provocation cluster (≥3 of 5)",
            "Thigh thrust / compression / distraction",
            "Hip screen to exclude",
        ],
    },
    nslbp_mechanical: {
        name: "Non-specific mechanical LBP",
        base: 0.6,
        include: (a) => {
            let s = 0;
            const centralOrButtock = a["L_painPattern"] === "central" || hasWhereLeg(a, "buttock");
            if (centralOrButtock)
                s += 0.4;
            if (hasAgg(a, "sitProlonged") || hasAgg(a, "stand"))
                s += 0.3;
            if (hasEase(a, "shortWalk"))
                s += 0.3;
            return s;
        },
        tests: [
            "AROM/PROM; repeated movement response",
            "Hip ROM; lumbar endurance/coordination",
            "Yellow flags screen as indicated",
        ],
    },
    vertebral_fracture: {
        name: "Possible vertebral fracture",
        base: 0.4,
        include: (a) => {
            let s = 0;
            const age = a["L_age_band"];
            if (age === "65+" || age === "51-65")
                s += 0.4;
            if (Y(a["L_rf_highEnergyTrauma"]))
                s += 0.8;
            return s;
        },
        tests: [
            "Percussion/palpation; observe kyphosis",
            "Imaging per local rule if indicated",
            "Red flag screen re-check",
        ],
    },
    malignancy_infection: {
        name: "Malignancy / infection concern",
        base: 0.2,
        include: (a) => {
            let s = 0;
            if (Y(a["L_rf_cancerHistory"]) && Y(a["L_rf_nightConstant"]))
                s += 1.2;
            if (Y(a["L_rf_fever"]) && Y(a["L_rf_nightConstant"]))
                s += 1.2;
            return s;
        },
        tests: [
            "Vitals; labs per pathway",
            "Imaging as indicated",
            "Urgent medical review if clustered",
        ],
    },
    acute_red_pathway: {
        name: "Acute red pathway (CES/infection/unstable trauma)",
        base: 0,
        include: () => 0,
        tests: [
            "Urgent medical assessment",
            "Neuro status; bladder/bowel function",
            "Imaging/labs per protocol",
        ],
    },
};
function score(a, triage) {
    const S = Object.keys(dx).reduce((acc, k) => {
        acc[k] = { score: dx[k].base, why: [] };
        return acc;
    }, {});
    if (triage === "red") {
        S.acute_red_pathway.score = 999;
        S.acute_red_pathway.why.push("Red-flag criteria met");
        return S;
    }
    else {
        S.acute_red_pathway.score = -Infinity;
    }
    Object.keys(dx).forEach((k) => {
        if (k === "acute_red_pathway")
            return;
        const def = dx[k];
        const inc = def.include(a) || 0;
        const exc = def.exclude ? def.exclude(a) || 0 : 0;
        S[k].score += inc + exc;
        if (inc !== 0 || exc !== 0)
            S[k].why.push("Pattern match to history/behaviour");
    });
    if (a["L_gaitAbility"] === "support" ||
        a["L_gaitAbility"] === "cannot" ||
        a["L_gaitAbility"] === "limp") {
        S.disc_radiculopathy.score += 0.1;
        S.spinal_stenosis.score += 0.1;
    }
    return S;
}
function buildSummary(a) {
    const { triage, notes } = triageColour(a);
    const scored = score(a, triage);
    const ranked = Object.keys(scored)
        .filter((k) => (triage === "red" ? true : k !== "acute_red_pathway"))
        .map((k) => ({ key: k, ...scored[k] }))
        .sort((x, y) => y.score - x.score);
    const topCount = triage === "red" ? 1 : 3;
    const top = ranked.slice(0, topCount).map((item) => ({
        key: item.key,
        name: dx[item.key].name,
        score: Number(item.score.toFixed(2)),
        rationale: item.why,
        objectiveTests: dx[item.key].tests,
    }));
    const globalTests = triage === "red"
        ? [
            "Urgent medical assessment",
            "Neuro status; bladder/bowel function",
            "Imaging/labs per protocol",
        ]
        : [
            "Lumbar AROM/PROM; repeated movement response",
            "Neuro screen (myo/derm/reflex)",
            "Hip screen; SIJ cluster if indicated",
        ];
    return {
        region: "Lumbar",
        triage,
        redFlagNotes: triage === "green" ? [] : notes,
        topDifferentials: top.map((t) => ({ name: t.name, score: t.score })),
        clinicalToDo: Array.from(new Set([...globalTests, ...top.flatMap((t) => t.objectiveTests)])),
        detailedTop: top,
    };
}
exports.processLumbarAssessment = functions
    .region("europe-west1")
    .https.onCall(async (data, _ctx) => {
    var _a;
    const assessmentId = data === null || data === void 0 ? void 0 : data.assessmentId;
    const answers = ((_a = data === null || data === void 0 ? void 0 : data.answers) !== null && _a !== void 0 ? _a : {});
    if (!assessmentId) {
        throw new functions.https.HttpsError("invalid-argument", "assessmentId is required");
    }
    const norm = normalizeAnswers(answers);
    const summary = buildSummary(norm);
    await db
        .collection("assessments")
        .doc(assessmentId)
        .set({
        triageStatus: summary.triage,
        topDifferentials: summary.topDifferentials,
        clinicianSummary: summary,
        triageRegion: "lumbar",
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    }, { merge: true });
    return {
        triageStatus: summary.triage,
        topDifferentials: summary.topDifferentials,
        clinicianSummary: summary,
    };
});
//# sourceMappingURL=buildLumbarSummary.js.map