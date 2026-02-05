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
exports.processWristAssessment = void 0;
exports.processWristAssessmentCore = processWristAssessmentCore;
/* Hand Region (Wrist + Thumb + Fingers) – callable scoring + summary (europe-west1, v1 API)
   NOTE: Keeps function name processWristAssessment for compatibility with existing wiring.
*/
const functions = __importStar(require("firebase-functions/v1"));
const firestore_1 = require("firebase-admin/firestore");
const db = (0, firestore_1.getFirestore)();
const diffs = {
    /* ---------------- Wrist ---------------- */
    tfcc: {
        key: "tfcc",
        name: "TFCC injury / ulnar-sided intra-articular wrist pain",
        base: 0.18,
        tests: [
            "Ulnar fovea sign",
            "DRUJ ballottement / piano key (as indicated)",
            "Ulnar deviation + axial load (ulnar grind) / press test (chair push-up)",
        ],
    },
    ecu: {
        key: "ecu",
        name: "ECU tendinopathy / subluxation",
        base: 0.1,
        tests: [
            "ECU synergy test",
            "Resisted ulnar deviation + supination",
            "Palpate ECU during pronation↔supination (subluxation/snapping)",
        ],
    },
    lt_ligament: {
        key: "lt_ligament",
        name: "Lunotriquetral ligament injury (ulnar/dorsoulnar wrist)",
        base: 0.05,
        tests: [
            "LT ballottement / shuck",
            "Ulnar-sided provocation with extension/ulnar deviation",
            "Assess carpal instability signs as indicated",
        ],
    },
    ulnar_impaction: {
        key: "ulnar_impaction",
        name: "Ulnar impaction syndrome (ulnocarpal overload)",
        base: 0.1,
        tests: [
            "Ulnar deviation + axial compression provocation (ulnocarpal stress)",
            "Grip under ulnar load",
            "Consider imaging if persistent + strong pattern",
        ],
    },
    de_quervain: {
        key: "de_quervain",
        name: "De Quervain’s tenosynovitis (APL/EPB)",
        base: 0.14,
        tests: ["Finkelstein / Eichhoff", "Resisted thumb abduction/extension"],
    },
    intersection: {
        key: "intersection",
        name: "Intersection syndrome (dorsoradial extensor overuse)",
        base: 0.03,
        tests: [
            "Palpation 4–8 cm proximal to wrist dorsoradially",
            "Crepitus with resisted wrist extension",
            "Pain with repetitive extension tasks",
        ],
    },
    ganglion: {
        key: "ganglion",
        name: "Ganglion cyst",
        base: 0.1,
        tests: ["Inspection/palpation ± transillumination", "Pain with end-range extension"],
    },
    carpal_boss: {
        key: "carpal_boss",
        name: "Carpal boss (2nd/3rd CMC dorsal osteophyte)",
        base: 0.05,
        tests: ["Fixed dorsal bony prominence", "Pain with resisted wrist extension"],
    },
    wrist_oa: {
        key: "wrist_oa",
        name: "Wrist osteoarthritis / degenerative wrist pain",
        base: 0.1,
        tests: ["ROM (extension often limited)", "Joint line palpation", "Grip under load"],
    },
    kienbock: {
        key: "kienbock",
        name: "Kienböck’s disease (lunate AVN) – consider if persistent dorsal pain",
        base: 0.01,
        tests: ["Dorsal lunate palpation", "Axial load pain", "Consider imaging if high suspicion"],
    },
    radial_nerve: {
        key: "radial_nerve",
        name: "Superficial radial nerve irritation (Wartenberg’s)",
        base: 0.01,
        tests: ["Tinel’s over radial styloid", "Sensation dorsoradial hand", "Provocation by tight watch/bracelet"],
    },
    ulnar_nerve: {
        key: "ulnar_nerve",
        name: "Guyon’s canal syndrome (ulnar nerve)",
        base: 0.02,
        tests: ["Tinel’s at Guyon’s canal", "Intrinsic strength + ulnar digits sensation"],
    },
    referred_cervical: {
        key: "referred_cervical",
        name: "Cervical referred pain / radicular contribution",
        base: 0.06,
        tests: ["Cervical ROM", "Spurling’s / ULNT as indicated", "Neuro screen"],
    },
    /* ---------------- Thumb / Finger (Hand) ---------------- */
    thumb_cmc_oa: {
        key: "thumb_cmc_oa",
        name: "Thumb CMC osteoarthritis",
        base: 0.06,
        tests: [
            "CMC grind test",
            "Thumb opposition/pinch strength",
            "Palpation CMC joint line; compare sides",
        ],
    },
    thumb_mcp_ucl_rcl: {
        key: "thumb_mcp_ucl_rcl",
        name: "Thumb MCP collateral ligament injury (UCL/RCL – skier’s/gamekeeper’s thumb)",
        base: 0.03,
        tests: [
            "Valgus/varus stress test MCP (compare to other side)",
            "Assess firm end-feel vs laxity (consider Stener lesion if gross laxity)",
            "Palpate ligament + bruising/swelling pattern",
        ],
    },
    trigger_finger: {
        key: "trigger_finger",
        name: "Trigger finger / trigger thumb (stenosing flexor tenosynovitis)",
        base: 0.12,
        tests: [
            "Palpate A1 pulley tenderness/nodule",
            "Active flexion–extension for catching/locking",
            "Pain with resisted finger flexion (compare sides)",
        ],
    },
    flexor_tenosynovitis_noninfective: {
        key: "flexor_tenosynovitis_noninfective",
        name: "Flexor tenosynovitis (non-infective / inflammatory / overload)",
        base: 0.04,
        tests: [
            "Palpation along flexor sheath for diffuse tenderness",
            "Pain with active flexion + passive extension",
            "Screen for inflammatory pattern (multiple joints, morning stiffness, swelling)",
        ],
    },
    extensor_tendon_injury: {
        key: "extensor_tendon_injury",
        name: "Extensor tendon injury (mallet / central slip / boutonnière)",
        base: 0.03,
        tests: [
            "Active extension test at DIP and PIP",
            "Elson test (central slip) if PIP issue",
            "Check for resting deformity and compare sides",
        ],
    },
    collateral_ligament: {
        key: "collateral_ligament",
        name: "Finger collateral ligament sprain (MCP/PIP – ‘jammed finger’)",
        base: 0.05,
        tests: [
            "Varus/valgus stress at affected joint",
            "Point tenderness at collateral ligament",
            "Assess instability vs pain-only response",
        ],
    },
    volar_plate: {
        key: "volar_plate",
        name: "Volar plate injury (PIP hyperextension sprain)",
        base: 0.03,
        tests: [
            "History: forced hyperextension mechanism",
            "Pain/tenderness on volar PIP",
            "Assess hyperextension laxity vs contralateral",
        ],
    },
    finger_oa: {
        key: "finger_oa",
        name: "Finger osteoarthritis (DIP/PIP – Heberden/Bouchard pattern)",
        base: 0.06,
        tests: [
            "Bony enlargement DIP/PIP, ROM loss",
            "Joint line tenderness/crepitus",
            "Grip and pinch tolerance under load",
        ],
    },
    inflammatory_arthritis_hand: {
        key: "inflammatory_arthritis_hand",
        name: "Inflammatory arthritis (RA/PsA spectrum – hand/finger pattern)",
        base: 0.02,
        tests: [
            "Joint count: multiple swollen/tender joints (MCP/PIP/wrist)",
            "Morning stiffness duration + systemic screen",
            "Look for dactylitis/nail changes (PsA) + referral considerations",
        ],
    },
    septic_joint_or_tenosynovitis: {
        key: "septic_joint_or_tenosynovitis",
        name: "Septic arthritis / pyogenic flexor tenosynovitis (urgent)",
        base: 0.0,
        tests: [
            "Kanavel signs (flexor sheath infection): fusiform swelling, flexed posture, tenderness along sheath, pain on passive extension",
            "Temp/erythema + severe pain",
            "Urgent medical/surgical referral (imaging/labs as indicated)",
        ],
    },
    dupuytren: {
        key: "dupuytren",
        name: "Dupuytren’s contracture (palmar cord/nodule, fixed flexion)",
        base: 0.02,
        tests: [
            "Palmar cord/nodule palpation",
            "Table-top test (hand flat on table)",
            "Differentiate from trigger: fixed contracture vs painful catching",
        ],
    },
    glomus_tumour: {
        key: "glomus_tumour",
        name: "Glomus tumour (subungual) – cold sensitivity + point tenderness",
        base: 0.0,
        tests: [
            "Love’s test (point pressure under nail → severe pain)",
            "Cold sensitivity history",
            "Consider imaging / hand specialist referral",
        ],
    },
    digital_nerve: {
        key: "digital_nerve",
        name: "Digital nerve irritation/neuroma (local fingertip numbness/pain)",
        base: 0.02,
        tests: [
            "Sensation testing in involved digit",
            "Tinel’s over scar/nerve course",
            "History of laceration/trauma",
        ],
    },
    crps_hand: {
        key: "crps_hand",
        name: "Complex regional pain syndrome (CRPS) – disproportionate pain + autonomic signs",
        base: 0.0,
        tests: [
            "Budapest features screen: sensory/allodynia, vasomotor, sudomotor/edema, motor/trophic",
            "Compare colour/temp/sweating vs other side",
            "Early escalation/referral if strong pattern",
        ],
    },
    /* ---------------- Red pathway ---------------- */
    acute_red_pathway: {
        key: "acute_red_pathway",
        name: "Suspected fracture/dislocation / infection / neurovascular compromise",
        base: 0.0,
        tests: [
            "Urgent imaging as indicated",
            "Neurovascular exam (cap refill, sensation, motor)",
            "Escalate urgently for infection/instability/vascular compromise",
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
const getSlider = (answers, id) => {
    const a = answers.find((x) => x.id === id && x.kind === "slider");
    return typeof (a === null || a === void 0 ? void 0 : a.value) === "number" ? a.value : undefined;
};
const yn = (v) => (v !== null && v !== void 0 ? v : "").toLowerCase() === "yes";
/* ----------------- triage ----------------- */
function computeTriage(answers) {
    let triage = "green";
    const notes = [];
    // Existing wrist red flags
    const trauma = yn(getOne(answers, "W_rf_high_energy"));
    const deformity = yn(getOne(answers, "W_rf_deformity"));
    const fever = yn(getOne(answers, "W_rf_fever"));
    const cantUse = yn(getOne(answers, "W_rf_cant_use"));
    // Optional hand/finger red flags (safe if Dart doesn't send them)
    const openWound = yn(getOne(answers, "H_rf_open_wound"));
    const spreadingRedness = yn(getOne(answers, "H_rf_spreading_redness"));
    const severeDisproportionatePain = yn(getOne(answers, "H_rf_pain_out_of_proportion"));
    const colourTempChange = yn(getOne(answers, "H_rf_colour_temp_change"));
    const numbColdPale = yn(getOne(answers, "H_rf_numb_cold_pale"));
    // Force RED: trauma/deformity/infection-compromise patterns
    if (trauma) {
        triage = "red";
        notes.push("High-energy/trauma mechanism");
    }
    if (deformity) {
        triage = "red";
        notes.push("Deformity or suspected dislocation/fracture");
    }
    if (fever && cantUse) {
        triage = "red";
        notes.push("Fever/unwell + unable to use hand (infection concern)");
    }
    if (openWound && (deformity || cantUse)) {
        triage = "red";
        notes.push("Open wound with functional compromise");
    }
    if (numbColdPale) {
        triage = "red";
        notes.push("Neurovascular compromise concern");
    }
    // AMBER: significant infection/CRPS cues without full red cluster
    if (triage === "green" && spreadingRedness) {
        triage = "amber";
        notes.push("Spreading redness/warmth (infection/inflammation concern)");
    }
    if (triage === "green" && (severeDisproportionatePain || colourTempChange)) {
        triage = "amber";
        notes.push("Disproportionate pain or autonomic change (CRPS risk)");
    }
    return { triage, notes };
}
/* ----------------- scoring ----------------- */
function score(answers, triage) {
    var _a, _b, _c;
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
    // Otherwise exclude acute pathway entirely from ranking
    S.acute_red_pathway.score = -Infinity;
    // Core inputs (wrist)
    const part = ((_a = getOne(answers, "H_part")) !== null && _a !== void 0 ? _a : "wrist").toLowerCase(); // wrist | thumb | finger
    const where = getMany(answers, "W_where"); // radial/ulnar/dorsal/volar
    const aggs = getMany(answers, "W_aggs"); // grip/twist/supination/ulnar_dev/ulnar_load/ext_load/pushup/thumb/typing/repetitive_flexion
    const feats = getMany(answers, "W_feats"); // click/snap/tingle/stiff/swelling/night/weak_grip/locking/deformity
    const lump = yn(getOne(answers, "W_lump"));
    const neck = yn(getOne(answers, "W_neck"));
    const hxFall = yn(getOne(answers, "W_hx_fall"));
    const cantGrip = yn(getOne(answers, "W_cant_grip"));
    // Optional finger-specific detail (safe if not sent)
    const digit = ((_b = getOne(answers, "H_digit")) !== null && _b !== void 0 ? _b : "").toLowerCase(); // thumb/index/middle/ring/little
    const joint = ((_c = getOne(answers, "H_joint")) !== null && _c !== void 0 ? _c : "").toLowerCase(); // dip/pip/mcp/cmc
    const nailBedPain = yn(getOne(answers, "H_nailbed_pain"));
    const fusiformSwelling = yn(getOne(answers, "H_fusiform_swelling"));
    const flexedRestingPosture = yn(getOne(answers, "H_flexed_resting_posture"));
    const painPassiveExtension = yn(getOne(answers, "H_pain_passive_extension"));
    const palmarCord = yn(getOne(answers, "H_palmar_cord"));
    const fixedContracture = yn(getOne(answers, "H_fixed_contracture"));
    const painOutOfProportion = yn(getOne(answers, "H_rf_pain_out_of_proportion"));
    const colourTempChange = yn(getOne(answers, "H_rf_colour_temp_change"));
    const W = new Set(where);
    const A = new Set(aggs);
    const F = new Set(feats);
    /* ----------------- part gating (big win) ----------------- */
    // Downweight entire clusters when part clearly not relevant.
    const isWrist = part === "wrist";
    const isThumb = part === "thumb";
    const isFinger = part === "finger";
    if (isFinger) {
        // De-emphasize wrist-only differentials
        ["tfcc", "ecu", "lt_ligament", "ulnar_impaction", "intersection", "carpal_boss", "kienbock"].forEach((k) => (S[k].score -= 0.14));
    }
    if (isThumb) {
        // Keep DeQ + thumb CMC, reduce deep ulnar wrist instability unless where supports
        ["lt_ligament", "kienbock"].forEach((k) => (S[k].score -= 0.10));
    }
    if (isWrist) {
        // De-emphasize finger-only patterns
        [
            "trigger_finger",
            "flexor_tenosynovitis_noninfective",
            "extensor_tendon_injury",
            "collateral_ligament",
            "volar_plate",
            "finger_oa",
            "dupuytren",
            "glomus_tumour",
            "digital_nerve",
        ].forEach((k) => (S[k].score -= 0.10));
    }
    /* ----------------- wrist location gating (soft) ----------------- */
    // Only apply this strongly when part is wrist or thumb. Fingers often don’t have W_where.
    if (!isFinger) {
        if (!W.has("ulnar")) {
            ["tfcc", "ecu", "lt_ligament", "ulnar_impaction"].forEach((k) => (S[k].score -= 0.12));
        }
        if (!W.has("radial")) {
            ["de_quervain", "intersection", "radial_nerve"].forEach((k) => (S[k].score -= 0.12));
        }
        if (!W.has("dorsal")) {
            ["ganglion", "carpal_boss", "kienbock", "intersection"].forEach((k) => (S[k].score -= 0.06));
        }
        if (!W.has("volar")) {
            S.ulnar_nerve.score -= 0.06;
        }
    }
    /* -------- Ulnar-sided overlap tuning (TFCC vs ECU vs LT vs impaction) -------- */
    if (!isFinger && W.has("ulnar")) {
        S.tfcc.score += 0.18;
        S.tfcc.why.push("Ulnar-sided pain cluster");
        S.ecu.score += 0.12;
        S.ecu.why.push("Ulnar-sided pain cluster");
        S.ulnar_impaction.score += 0.10;
        S.ulnar_impaction.why.push("Ulnar-sided pain cluster");
        S.lt_ligament.score += 0.08;
        S.lt_ligament.why.push("Ulnar-sided pain cluster");
    }
    // TFCC
    if (!isFinger && A.has("twist")) {
        S.tfcc.score += 0.22;
        S.tfcc.why.push("Twisting/pronation-supination aggravation");
    }
    if (!isFinger && (A.has("ulnar_dev") || A.has("ulnar_load"))) {
        S.tfcc.score += 0.14;
        S.tfcc.why.push("Ulnar deviation/ulnar loading");
    }
    if (!isFinger && F.has("click")) {
        S.tfcc.score += 0.10;
        S.tfcc.why.push("Click/catch feature");
    }
    if (!isFinger && (A.has("ext_load") || A.has("pushup"))) {
        S.tfcc.score += 0.10;
        S.tfcc.why.push("Weight-bearing through wrist");
    }
    // ECU
    if (!isFinger && F.has("snap")) {
        S.ecu.score += 0.28;
        S.ecu.why.push("Snapping sensation (ECU sublux/tendon)");
    }
    if (!isFinger && A.has("supination")) {
        S.ecu.score += 0.16;
        S.ecu.why.push("Supination aggravation (ECU)");
    }
    if (!isFinger && A.has("ulnar_dev")) {
        S.ecu.score += 0.10;
        S.ecu.why.push("Ulnar deviation aggravation");
    }
    // LT ligament
    if (!isFinger && W.has("dorsal") && W.has("ulnar")) {
        S.lt_ligament.score += 0.12;
        S.lt_ligament.why.push("Dorsoulnar location");
    }
    if (!isFinger && F.has("click") && !F.has("snap")) {
        S.lt_ligament.score += 0.10;
        S.lt_ligament.why.push("Clicking without snapping (ligament)");
    }
    if (!isFinger && hxFall) {
        S.lt_ligament.score += 0.14;
        S.lt_ligament.why.push("History of fall/FOOSH");
    }
    // Ulnar impaction
    if (!isFinger && A.has("ulnar_load")) {
        S.ulnar_impaction.score += 0.26;
        S.ulnar_impaction.why.push("Ulnar load pain");
    }
    if (!isFinger && (A.has("grip") || A.has("ext_load") || A.has("pushup"))) {
        S.ulnar_impaction.score += 0.10;
        S.ulnar_impaction.why.push("Load/grip aggravation");
    }
    if (!isFinger && F.has("stiff")) {
        S.ulnar_impaction.score += 0.08;
        S.ulnar_impaction.why.push("Stiffness feature");
    }
    // Overlap guards
    if (!isFinger && F.has("snap")) {
        S.tfcc.score -= 0.14;
        S.ulnar_impaction.score -= 0.06;
        S.lt_ligament.score -= 0.06;
    }
    if (!isFinger && F.has("stiff") && A.has("ulnar_load")) {
        S.ecu.score -= 0.08;
        S.tfcc.score -= 0.08;
    }
    if (!isFinger && hxFall && W.has("dorsal") && !A.has("ulnar_load") && !A.has("twist")) {
        S.lt_ligament.score += 0.08;
        S.tfcc.score -= 0.10;
    }
    /* -------- Radial-sided overlap tuning (DeQ vs Intersection vs nerve) -------- */
    if (!isFinger && W.has("radial")) {
        S.de_quervain.score += 0.14;
        S.de_quervain.why.push("Radial styloid area");
        S.intersection.score += 0.10;
        S.intersection.why.push("Dorsoradial region overlap");
        S.radial_nerve.score += 0.06;
        S.radial_nerve.why.push("Radial distribution consideration");
    }
    if (!isFinger && A.has("thumb")) {
        S.de_quervain.score += 0.24;
        S.de_quervain.why.push("Thumb loading/aggravation");
        S.intersection.score -= 0.06;
    }
    if (!isFinger && A.has("ext_load") && !A.has("thumb") && W.has("radial")) {
        S.intersection.score += 0.18;
        S.intersection.why.push("Resisted extension/overuse pattern");
    }
    if (!isFinger && F.has("tingle") && W.has("radial")) {
        S.radial_nerve.score += 0.16;
        S.radial_nerve.why.push("Paresthesia in dorsoradial area");
        S.de_quervain.score -= 0.06;
    }
    /* -------- Lumps: ganglion vs carpal boss -------- */
    if (!isFinger && lump) {
        S.ganglion.score += 0.30;
        S.ganglion.why.push("Reported lump");
        S.carpal_boss.score += 0.16;
        S.carpal_boss.why.push("Reported lump");
        if (W.has("dorsal")) {
            S.ganglion.score += 0.10;
            S.carpal_boss.score += 0.06;
        }
        if (A.has("ext_load") || A.has("pushup")) {
            S.ganglion.score += 0.08;
            S.ganglion.why.push("Pain with extension/loading");
            S.carpal_boss.score += 0.08;
            S.carpal_boss.why.push("Pain with extension/loading");
        }
    }
    /* -------- OA / degenerative (wrist) -------- */
    if (!isFinger && F.has("stiff")) {
        S.wrist_oa.score += 0.22;
        S.wrist_oa.why.push("Stiffness");
    }
    if (!isFinger && F.has("swelling")) {
        S.wrist_oa.score += 0.06;
    }
    if (!isFinger && A.has("grip")) {
        S.wrist_oa.score += 0.06;
    }
    /* -------- Kienbock (keep low unless classic) -------- */
    if (!isFinger && W.has("dorsal") && !W.has("ulnar") && !W.has("radial")) {
        S.kienbock.score += 0.08;
        S.kienbock.why.push("Central dorsal wrist pain");
    }
    if (!isFinger && (A.has("ext_load") || A.has("pushup"))) {
        S.kienbock.score += 0.06;
    }
    if (!isFinger && F.has("stiff")) {
        S.kienbock.score += 0.04;
    }
    if (!isFinger && lump) {
        S.kienbock.score -= 0.05;
    }
    /* -------- Ulnar nerve / cervical -------- */
    if (!isFinger && W.has("volar") && W.has("ulnar")) {
        S.ulnar_nerve.score += 0.16;
        S.ulnar_nerve.why.push("Volar ulnar distribution");
    }
    if (!isFinger && F.has("tingle")) {
        S.ulnar_nerve.score += 0.10;
        S.ulnar_nerve.why.push("Paresthesia feature");
    }
    if (neck) {
        S.referred_cervical.score += 0.26;
        S.referred_cervical.why.push("Neck involvement");
        if (F.has("tingle")) {
            S.radial_nerve.score -= 0.04;
            S.ulnar_nerve.score -= 0.04;
        }
    }
    /* ----------------- Thumb logic ----------------- */
    if (isThumb || digit === "thumb") {
        if (A.has("thumb") && (F.has("stiff") || A.has("grip"))) {
            S.thumb_cmc_oa.score += 0.26;
            S.thumb_cmc_oa.why.push("Thumb loading + stiffness/grip pattern");
        }
        // Ligament injury – sudden mechanism often helps (hxFall or trauma flags)
        if (hxFall || yn(getOne(answers, "W_rf_high_energy"))) {
            if (joint === "mcp" || joint === "" /* allow */) {
                S.thumb_mcp_ucl_rcl.score += 0.18;
                S.thumb_mcp_ucl_rcl.why.push("Trauma mechanism for thumb MCP ligament");
            }
        }
        // DeQ remains relevant for thumb-side wrist
        if (A.has("thumb") && (W.has("radial") || !W.size)) {
            S.de_quervain.score += 0.10;
        }
        // Trigger thumb
        if (F.has("locking") || (F.has("click") && (A.has("thumb") || digit === "thumb"))) {
            S.trigger_finger.score += 0.14;
            S.trigger_finger.why.push("Thumb catching/locking (trigger thumb pattern)");
        }
    }
    /* ----------------- Finger logic ----------------- */
    if (isFinger) {
        // Trigger finger: catching/locking + flexion load
        if (F.has("locking") || F.has("click")) {
            S.trigger_finger.score += 0.30;
            S.trigger_finger.why.push("Catching/locking/clicking in finger movement");
        }
        if (A.has("grip") || A.has("repetitive_flexion")) {
            S.trigger_finger.score += 0.12;
            S.trigger_finger.why.push("Repetitive flexion/grip load");
        }
        // Dupuytren: fixed contracture + palmar cord, typically not painful locking
        if (palmarCord || fixedContracture) {
            S.dupuytren.score += 0.30;
            S.dupuytren.why.push("Palmar cord and/or fixed flexion contracture");
            S.trigger_finger.score -= 0.10;
        }
        // Extensor tendon injury: deformity + loss of active extension (approx proxy)
        if (F.has("deformity")) {
            S.extensor_tendon_injury.score += 0.20;
            S.extensor_tendon_injury.why.push("Deformity/resting posture change");
        }
        if (joint === "dip" && F.has("deformity")) {
            S.extensor_tendon_injury.score += 0.10; // mallet bias
            S.extensor_tendon_injury.why.push("DIP deformity pattern (mallet consideration)");
        }
        if (joint === "pip" && F.has("deformity")) {
            S.extensor_tendon_injury.score += 0.08; // central slip/boutonniere
        }
        // Collateral ligament / volar plate: trauma + focal joint pain/instability patterns
        if (hxFall || yn(getOne(answers, "W_rf_high_energy"))) {
            if (joint === "pip" || joint === "mcp") {
                S.collateral_ligament.score += 0.18;
                S.collateral_ligament.why.push("Trauma mechanism + MCP/PIP involvement");
            }
            if (yn(getOne(answers, "H_mech_hyperextension")) || yn(getOne(answers, "H_mech_jammed"))) {
                S.volar_plate.score += 0.16;
                S.volar_plate.why.push("Hyperextension/jammed mechanism");
            }
        }
        // Finger OA: stiffness + DIP/PIP pattern
        if (F.has("stiff")) {
            S.finger_oa.score += 0.20;
            S.finger_oa.why.push("Stiffness feature");
            if (joint === "dip" || joint === "pip") {
                S.finger_oa.score += 0.10;
                S.finger_oa.why.push("DIP/PIP involvement (OA pattern)");
            }
        }
        // Inflammatory arthritis: multi-joint swelling + morning stiffness proxy
        if (yn(getOne(answers, "H_multi_joint")) || yn(getOne(answers, "H_morning_stiff_60"))) {
            S.inflammatory_arthritis_hand.score += 0.28;
            S.inflammatory_arthritis_hand.why.push("Multi-joint / inflammatory stiffness pattern");
        }
        // Digital nerve: tingling localized and/or scar/trauma history
        if (F.has("tingle") && !neck) {
            S.digital_nerve.score += 0.12;
            S.digital_nerve.why.push("Digit tingling without clear cervical driver");
        }
        if (yn(getOne(answers, "H_hx_laceration"))) {
            S.digital_nerve.score += 0.12;
            S.digital_nerve.why.push("History of laceration/scar (neuroma/nerve irritation)");
        }
        // Glomus tumour: nail bed pain + cold sensitivity proxy
        if (nailBedPain && yn(getOne(answers, "H_cold_sensitive"))) {
            S.glomus_tumour.score += 0.40;
            S.glomus_tumour.why.push("Nail-bed pain + cold sensitivity (glomus pattern)");
        }
        else if (nailBedPain) {
            S.glomus_tumour.score += 0.10;
            S.glomus_tumour.why.push("Nail-bed pain feature");
        }
        // Infection urgent pattern (Kanavel proxy)
        if (fusiformSwelling || flexedRestingPosture || painPassiveExtension) {
            S.septic_joint_or_tenosynovitis.score += 0.50;
            S.septic_joint_or_tenosynovitis.why.push("Kanavel-style features (infection concern)");
        }
        // Noninfective flexor tenosynovitis (if swelling + pain but not Kanavel cluster)
        if (F.has("swelling") && !fusiformSwelling && !painPassiveExtension) {
            S.flexor_tenosynovitis_noninfective.score += 0.16;
            S.flexor_tenosynovitis_noninfective.why.push("Swelling/tendon sheath irritation without strong infection cluster");
        }
        // CRPS weighting (disproportionate pain + colour/temp change)
        if (painOutOfProportion || colourTempChange) {
            S.crps_hand.score += 0.38;
            S.crps_hand.why.push("Disproportionate pain and/or autonomic change");
        }
    }
    /* ----------------- “severity bump” (light) ----------------- */
    if (cantGrip) {
        ["tfcc", "ulnar_impaction", "de_quervain", "wrist_oa", "trigger_finger", "finger_oa"].forEach((k) => (S[k].score += 0.04));
    }
    return S;
}
/* ----------------- summary builder ----------------- */
function buildSummary(answers) {
    var _a, _b;
    const { triage, notes } = computeTriage(answers);
    const scored = score(answers, triage);
    const part = ((_a = getOne(answers, "H_part")) !== null && _a !== void 0 ? _a : "wrist").toLowerCase();
    const side = (_b = getOne(answers, "W_side")) !== null && _b !== void 0 ? _b : "";
    const sideLabel = side ? `Hand (${side})` : "Hand";
    const partLabel = part === "finger" ? "Fingers" : part === "thumb" ? "Thumb" : "Wrist";
    const regionLabel = `${sideLabel} – ${partLabel}`;
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
        ? ["Urgent imaging as indicated", "Neurovascular exam", "Escalate urgently for infection/instability/vascular concern"]
        : ["AROM/PROM of involved joints", "Palpation of focal structures", "Neuro screen if tingling/numbness"];
    const clinicalToDo = Array.from(new Set([...globalTests, ...top.flatMap((t) => t.objectiveTests)]));
    return {
        region: regionLabel,
        triage,
        redFlagNotes: triage === "green" ? [] : notes,
        topDifferentials: top.map((t) => ({ name: t.name, score: t.score })),
        clinicalToDo,
        detailedTop: top,
    };
}
/* ----------------- callable ----------------- */
async function processWristAssessmentCore(data, _ctx) {
    const assessmentId = data === null || data === void 0 ? void 0 : data.assessmentId;
    const answers = Array.isArray(data === null || data === void 0 ? void 0 : data.answers) ? data.answers : [];
    if (!assessmentId) {
        throw new functions.https.HttpsError("invalid-argument", "assessmentId is required");
    }
    const summary = buildSummary(answers);
    await db.collection("assessments").doc(assessmentId).set({
        triageStatus: summary.triage,
        topDifferentials: summary.topDifferentials,
        clinicianSummary: summary,
        triageRegion: "hand",
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    }, { merge: true });
    return {
        triageStatus: summary.triage,
        topDifferentials: summary.topDifferentials,
        clinicianSummary: summary,
    };
}
// -------------------------------
// Firebase callable wrapper
// -------------------------------
exports.processWristAssessment = functions
    .region("europe-west1")
    .https.onCall(async (data, ctx) => {
    return processWristAssessmentCore(data, ctx);
});
//# sourceMappingURL=processWristAssessment.js.map