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
exports.processElbowAssessment = void 0;
exports.buildSummary = buildSummary;
/* Elbow Region – callable scoring + summary (europe-west1, v1 API) */
const functions = __importStar(require("firebase-functions/v1"));
const firestore_1 = require("firebase-admin/firestore");
const db = (0, firestore_1.getFirestore)();
const diffs = {
    lat_epi: {
        key: "lat_epi",
        name: "Lateral epicondylalgia (common extensor)",
        base: 0.18,
        tests: [
            "Cozen’s / Chair test / Resisted wrist extension",
            "Palpate CET 2–3 cm distal to lateral epicondyle",
            "Grip dynamometry vs other side",
        ],
    },
    med_epi: {
        key: "med_epi",
        name: "Medial epicondylalgia (flexor–pronator)",
        base: 0.16,
        tests: [
            "Resisted wrist flexion / resisted pronation",
            "Palpate common flexor origin at medial epicondyle",
        ],
    },
    olecranon_bursitis: {
        key: "olecranon_bursitis",
        name: "Olecranon bursitis",
        base: 0.1,
        tests: [
            "Inspect/palpate posterior swelling",
            "Assess warmth/redness; consider aspiration pathway if infected features",
        ],
    },
    distal_biceps: {
        key: "distal_biceps",
        name: "Distal biceps pathology/tear",
        base: 0.1,
        tests: ["Hook test", "Resisted supination strength vs other side"],
    },
    ulnar_neuritis: {
        key: "ulnar_neuritis",
        name: "Ulnar neuritis / cubital tunnel",
        base: 0.12,
        tests: ["Tinel’s at cubital tunnel", "Elbow flexion test", "Ulnar nerve palpation/subluxation check"],
    },
    radial_tunnel: {
        key: "radial_tunnel",
        name: "Radial tunnel / PIN entrapment",
        base: 0.1,
        tests: ["Resisted middle finger extension (Maudsley)", "Tinel’s over radial tunnel", "Resisted supination test"],
    },
    chondral_oa: {
        key: "chondral_oa",
        name: "Chondral/OA or loose body",
        base: 0.08,
        tests: ["End-range flex/extension pain", "Crepitus; consider imaging if persistent mechanical block"],
    },
    referred_cervical: {
        key: "referred_cervical",
        name: "Referred cervical/radicular pain",
        base: 0.06,
        tests: ["C-spine screen: ROM, Spurling’s, neuro, ULNTs"],
    },
    acute_red_pathway: {
        key: "acute_red_pathway",
        name: "Suspected fracture / dislocation / septic joint",
        base: 0.0,
        tests: [
            "Immobilize; urgent elbow X-ray",
            "Neurovascular exam (pulses, cap refill, motor/sensory)",
            "Same-day medical review if fever or hot, red joint",
        ],
    },
    // ──────────────────────────────────────────────────────────────
    // ✅ NEW DIFFERENTIALS (8) + objective tests
    // ──────────────────────────────────────────────────────────────
    ucl_sprain: {
        key: "ucl_sprain",
        name: "UCL sprain/tear (throwing valgus overload)",
        base: 0.08,
        tests: [
            "Valgus stress test (at ~20–30° flexion)",
            "Moving valgus stress test (throwing athletes)",
            "Milking maneuver",
            "Assess medial joint line tenderness; consider US/MRI if severe",
        ],
    },
    plri_lucl: {
        key: "plri_lucl",
        name: "Posterolateral rotatory instability (LUCL/PLRI)",
        base: 0.06,
        tests: [
            "Posterolateral rotatory drawer test",
            "Chair push-up test / tabletop relocation test",
            "Pivot-shift (specialist setting)",
            "Assess apprehension with supination + axial load",
        ],
    },
    triceps_tendinopathy: {
        key: "triceps_tendinopathy",
        name: "Triceps tendinopathy / partial tear",
        base: 0.06,
        tests: [
            "Resisted elbow extension (pain/weakness)",
            "Palpate triceps insertion at olecranon",
            "Pain with press-ups/dips; compare strength bilaterally",
        ],
    },
    valgus_extension_overload: {
        key: "valgus_extension_overload",
        name: "Valgus extension overload / posteromedial impingement",
        base: 0.06,
        tests: [
            "Posteromedial tenderness; pain with forced extension",
            "Valgus-extension overload test",
            "Assess throwing mechanics history; imaging if persistent catching/locking",
        ],
    },
    capitellar_ocd: {
        key: "capitellar_ocd",
        name: "Capitellar OCD / radiocapitellar chondral injury",
        base: 0.05,
        tests: [
            "Radiocapitellar compression test",
            "Pain with valgus load + extension in athletes",
            "Mechanical symptoms; consider X-ray/MRI if suspected",
        ],
    },
    synovial_plica: {
        key: "synovial_plica",
        name: "Synovial plica / lateral snapping elbow",
        base: 0.05,
        tests: [
            "Reproduce snapping with flex–extend + pronation/supination",
            "Posterolateral tenderness; rule out instability",
            "Ultrasound can visualize plica in some cases",
        ],
    },
    crystal_arthritis: {
        key: "crystal_arthritis",
        name: "Crystal/inflammatory arthritis flare (e.g., gout/pseudogout)",
        base: 0.05,
        tests: [
            "Check warmth/redness/effusion; ROM limited by pain",
            "Screen systemic features; consider urgent aspiration if uncertain vs infection",
            "Assess other joints; medical review for flare management",
        ],
    },
    median_neuropathy_pronator: {
        key: "median_neuropathy_pronator",
        name: "Median neuropathy (pronator syndrome)",
        base: 0.05,
        tests: [
            "Resisted pronation with elbow flexed (symptom reproduction)",
            "Tinel’s over pronator teres / proximal forearm",
            "Median nerve neuro screen; differentiate from cervical radic/CTS",
        ],
    },
};
// ---------- triage ----------
function computeTriage(answers) {
    var _a, _b, _c, _d, _e, _f;
    const get = (id) => answers.find((a) => a.id === id && a.kind === "single");
    const notes = [];
    let triage = "green";
    const injuryHigh = ((_a = get("E_rf_injury_force")) === null || _a === void 0 ? void 0 : _a.value) === "yes";
    const deformity = ((_b = get("E_rf_deformity")) === null || _b === void 0 ? void 0 : _b.value) === "yes";
    const rapidSwelling = ((_c = get("E_rf_swelling")) === null || _c === void 0 ? void 0 : _c.value) === "yes";
    const numbAfter = ((_d = get("E_rf_numb")) === null || _d === void 0 ? void 0 : _d.value) === "yes";
    const feverHot = ((_e = get("E_rf_fever")) === null || _e === void 0 ? void 0 : _e.value) === "yes";
    const canStraightenRF = ((_f = get("E_can_straighten")) === null || _f === void 0 ? void 0 : _f.value) === "yes";
    const cantFullyStraighten = !canStraightenRF;
    if (feverHot) {
        notes.push("Fever / hot, red joint");
        triage = "red";
    }
    if (numbAfter) {
        notes.push("New numbness after injury");
        triage = "red";
    }
    if (injuryHigh && (deformity || rapidSwelling || cantFullyStraighten)) {
        notes.push("High-force trauma with deformity/swelling/cannot fully extend");
        triage = "red";
    }
    else {
        if (deformity) {
            notes.push("Visible deformity");
            triage = "red";
        }
        if (rapidSwelling) {
            notes.push("Rapid swelling (haemarthrosis/fracture?)");
            triage = "red";
        }
    }
    if (triage === "green" && injuryHigh) {
        notes.push("High-force trauma mechanism");
        triage = "amber";
    }
    if (triage === "green" && cantFullyStraighten) {
        notes.push("Unable to fully bend/straighten");
        triage = "amber";
    }
    return { triage, notes };
}
// ---------- scoring ----------
function score(answers, triage) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q, _r, _s, _t;
    const getSingle = (id) => answers.find((a) => a.id === id && a.kind === "single");
    const getMulti = (id) => {
        var _a, _b;
        return ((_b = (_a = answers.find((a) => a.id === id && a.kind === "multi")) === null || _a === void 0 ? void 0 : _a.values) !== null && _b !== void 0 ? _b : []);
    };
    const S = Object.keys(diffs).reduce((acc, k) => {
        acc[k] = { score: diffs[k].base, why: [] };
        return acc;
    }, {});
    if (triage === "red") {
        S.acute_red_pathway.score = 999;
        S.acute_red_pathway.why.push("Red flags present – prioritize acute medical causes");
        return S;
    }
    S.acute_red_pathway.score = -Infinity;
    const loc = (_a = getSingle("E_loc")) === null || _a === void 0 ? void 0 : _a.value; // lateral/medial/posterior/anterior/diffuse
    const onset = (_b = getSingle("E_onset")) === null || _b === void 0 ? void 0 : _b.value; // gradual/sudden/traumaHigh/unknown
    const aggs = getMulti("E_aggs"); // coded strings
    const ulnar = ((_c = getSingle("E_para_ulnar")) === null || _c === void 0 ? void 0 : _c.value) === "yes";
    const thumbIx = ((_d = getSingle("E_para_thumbindex")) === null || _d === void 0 ? void 0 : _d.value) === "yes";
    const painRT = ((_e = getSingle("E_pain_forearm_thumbside")) === null || _e === void 0 ? void 0 : _e.value) === "yes";
    const postSw = ((_f = getSingle("E_swelling_post")) === null || _f === void 0 ? void 0 : _f.value) === "yes";
    const canExt = ((_g = getSingle("E_can_straighten")) === null || _g === void 0 ? void 0 : _g.value) === "yes";
    const popAnt = ((_h = getSingle("E_pop_ant")) === null || _h === void 0 ? void 0 : _h.value) === "yes";
    const stiff30 = ((_j = getSingle("E_stiff_morning")) === null || _j === void 0 ? void 0 : _j.value) === "yes";
    const catchLk = ((_k = getSingle("E_catching")) === null || _k === void 0 ? void 0 : _k.value) === "yes";
    const neckRad = ((_l = getSingle("E_neck_radiation")) === null || _l === void 0 ? void 0 : _l.value) === "yes";
    // ✅ NEW question IDs
    const clickSnap = ((_m = getSingle("E_click_snap")) === null || _m === void 0 ? void 0 : _m.value) === "yes";
    const valgusPain = ((_o = getSingle("E_throw_valgus_pain")) === null || _o === void 0 ? void 0 : _o.value) === "yes";
    const pmEndExt = ((_p = getSingle("E_posteromedial_endext")) === null || _p === void 0 ? void 0 : _p.value) === "yes";
    const triExtPain = ((_q = getSingle("E_resisted_extension_pain")) === null || _q === void 0 ? void 0 : _q.value) === "yes";
    const hotSwNoFever = ((_r = getSingle("E_hot_swollen_no_fever")) === null || _r === void 0 ? void 0 : _r.value) === "yes";
    const pronationPain = ((_s = getSingle("E_pronation_pain")) === null || _s === void 0 ? void 0 : _s.value) === "yes";
    const hasPalmDownGrip = aggs.includes("palmDownGrip");
    const hasTwistJar = aggs.includes("twistJar");
    // ─────────────────────────────────────────
    // Existing diffs (kept, slightly tuned)
    // ─────────────────────────────────────────
    // Lateral epi
    if (loc === "lateral") {
        S.lat_epi.score += 0.35;
        S.lat_epi.why.push("Lateral pain");
    }
    if (hasPalmDownGrip) {
        S.lat_epi.score += 0.25;
        S.lat_epi.why.push("Worse with palm-down grip/typing");
    }
    if (hasTwistJar) {
        S.lat_epi.score += 0.15;
        S.lat_epi.why.push("Worse with jar/screwdriver twist");
    }
    if (onset === "gradual") {
        S.lat_epi.score += 0.12;
        S.lat_epi.why.push("Gradual/overuse onset");
    }
    if (painRT && !hasPalmDownGrip && !hasTwistJar) {
        S.lat_epi.score -= 0.12;
        S.lat_epi.why.push("Less likely with thumb-side forearm radiation without classic lat-epi aggs");
    }
    // Medial epi
    if (loc === "medial") {
        S.med_epi.score += 0.35;
        S.med_epi.why.push("Medial pain");
    }
    if (aggs.includes("palmUpCarry")) {
        S.med_epi.score += 0.25;
        S.med_epi.why.push("Worse carrying palm-up");
    }
    if (aggs.includes("overheadThrow")) {
        S.med_epi.score += 0.08;
        S.med_epi.why.push("Throwing can load flexor–pronator origin");
    }
    // Olecranon bursitis
    if (loc === "posterior") {
        S.olecranon_bursitis.score += 0.25;
        S.olecranon_bursitis.why.push("Posterior pain");
    }
    if (postSw) {
        S.olecranon_bursitis.score += 0.35;
        S.olecranon_bursitis.why.push("Posterior swelling");
    }
    if (aggs.includes("restOnOlecranon")) {
        S.olecranon_bursitis.score += 0.2;
        S.olecranon_bursitis.why.push("Pain resting on olecranon");
    }
    // Distal biceps
    if (loc === "anterior") {
        S.distal_biceps.score += 0.25;
        S.distal_biceps.why.push("Anterior crease pain");
    }
    if (popAnt) {
        S.distal_biceps.score += 0.45;
        S.distal_biceps.why.push("Sudden “pop” anterior");
    }
    if (onset === "sudden" || onset === "traumaHigh") {
        S.distal_biceps.score += 0.15;
        S.distal_biceps.why.push("Sudden/traumatic onset");
    }
    // Ulnar neuritis
    if (ulnar) {
        S.ulnar_neuritis.score += 0.45;
        S.ulnar_neuritis.why.push("Ring/little finger paraesthesia");
    }
    if (canExt === false) {
        S.ulnar_neuritis.score += 0.1;
        S.ulnar_neuritis.why.push("Trouble fully extending");
    }
    if (aggs.includes("pushUpWB")) {
        S.ulnar_neuritis.score += 0.1;
        S.ulnar_neuritis.why.push("Worse weight-bearing in flexion");
    }
    // Radial tunnel
    if (painRT) {
        S.radial_tunnel.score += 0.45;
        S.radial_tunnel.why.push("Pain into forearm (thumb side)");
    }
    if (aggs.includes("overheadThrow")) {
        S.radial_tunnel.score += 0.15;
        S.radial_tunnel.why.push("Overhead/throwing provocation");
    }
    if (loc === "lateral" && painRT) {
        S.radial_tunnel.score += 0.1;
        S.radial_tunnel.why.push("Lateral elbow + radiating forearm pain pattern");
    }
    // Chondral/OA/loose body
    if (catchLk) {
        S.chondral_oa.score += 0.35;
        S.chondral_oa.why.push("Catching/locking");
    }
    if (stiff30) {
        S.chondral_oa.score += 0.15;
        S.chondral_oa.why.push("Stiffness >30 min");
    }
    if (pmEndExt) {
        S.chondral_oa.score += 0.12;
        S.chondral_oa.why.push("End-range extension pain");
    }
    // Referred cervical
    if (neckRad) {
        S.referred_cervical.score += 0.35;
        S.referred_cervical.why.push("Neck pain radiating past elbow");
    }
    if (thumbIx) {
        S.referred_cervical.score += 0.1;
        S.referred_cervical.why.push("Thumb/index paraesthesia");
    }
    // ─────────────────────────────────────────
    // ✅ NEW DIFFERENTIAL SCORING (8)
    // ─────────────────────────────────────────
    // UCL sprain/tear
    if (valgusPain) {
        S.ucl_sprain.score += 0.5;
        S.ucl_sprain.why.push("Valgus/throwing pain");
    }
    if (loc === "medial") {
        S.ucl_sprain.score += 0.2;
        S.ucl_sprain.why.push("Medial pain");
    }
    if (ulnar) {
        S.ucl_sprain.score += 0.08;
        S.ucl_sprain.why.push("Ulnar nerve symptoms can coexist with UCL overload");
    }
    // Valgus extension overload / posteromedial impingement
    if (pmEndExt && aggs.includes("overheadThrow")) {
        S.valgus_extension_overload.score += 0.55;
        S.valgus_extension_overload.why.push("Posteromedial end-range extension pain + throwing");
    }
    if (catchLk) {
        S.valgus_extension_overload.score += 0.15;
        S.valgus_extension_overload.why.push("Mechanical symptoms");
    }
    // PLRI / LUCL
    if (clickSnap && aggs.includes("pushUpWB")) {
        S.plri_lucl.score += 0.6;
        S.plri_lucl.why.push("Clicking/snapping + push-up/weight-bearing provocation");
    }
    if (onset === "sudden" || onset === "traumaHigh") {
        S.plri_lucl.score += 0.12;
        S.plri_lucl.why.push("Sudden/traumatic onset");
    }
    if (loc === "lateral") {
        S.plri_lucl.score += 0.1;
        S.plri_lucl.why.push("Often lateral-sided symptoms");
    }
    // Triceps tendinopathy
    if (triExtPain) {
        S.triceps_tendinopathy.score += 0.6;
        S.triceps_tendinopathy.why.push("Pain with resisted elbow extension");
    }
    if (loc === "posterior") {
        S.triceps_tendinopathy.score += 0.15;
        S.triceps_tendinopathy.why.push("Posterior pain location");
    }
    // Capitellar OCD / radiocapitellar lesion
    if (loc === "lateral" && catchLk) {
        S.capitellar_ocd.score += 0.45;
        S.capitellar_ocd.why.push("Lateral pain + catching/locking (radiocapitellar/loose body pattern)");
    }
    if (aggs.includes("overheadThrow")) {
        S.capitellar_ocd.score += 0.15;
        S.capitellar_ocd.why.push("Throwing/overhead load risk");
    }
    // Synovial plica / lateral snapping
    if (clickSnap && loc === "lateral") {
        S.synovial_plica.score += 0.5;
        S.synovial_plica.why.push("Lateral clicking/snapping");
    }
    if (catchLk) {
        S.synovial_plica.score += 0.1;
        S.synovial_plica.why.push("Mechanical symptoms");
    }
    // Crystal/inflammatory arthritis (non-febrile hot swollen elbow)
    if (hotSwNoFever) {
        S.crystal_arthritis.score += 0.55;
        S.crystal_arthritis.why.push("Hot/swollen joint without fever reported");
    }
    if (stiff30 && ((_t = getSingle("E_bilateral")) === null || _t === void 0 ? void 0 : _t.value) === "yes") {
        S.crystal_arthritis.score += 0.1;
        S.crystal_arthritis.why.push("Inflammatory features / bilateral symptoms");
    }
    // Median neuropathy (pronator syndrome)
    if (thumbIx && pronationPain && !neckRad) {
        S.median_neuropathy_pronator.score += 0.55;
        S.median_neuropathy_pronator.why.push("Thumb/index symptoms provoked by pronation without neck-radiation features");
    }
    if (loc === "anterior") {
        S.median_neuropathy_pronator.score += 0.12;
        S.median_neuropathy_pronator.why.push("Anterior/forearm region symptoms");
    }
    if (neckRad) {
        S.median_neuropathy_pronator.score -= 0.2;
        S.median_neuropathy_pronator.why.push("Neck radiation suggests cervical contribution instead");
    }
    return S;
}
function buildSummary(answers) {
    const { triage, notes } = computeTriage(answers);
    const scored = score(answers, triage);
    const ranked = Object.keys(scored)
        .filter((k) => (triage === "red" ? true : k !== "acute_red_pathway"))
        .map((k) => ({ key: k, ...scored[k] }))
        .sort((a, b) => b.score - a.score);
    const topCount = triage === "red" ? 1 : 3;
    const top = ranked.slice(0, topCount).map((item) => ({
        key: item.key,
        name: diffs[item.key].name,
        score: Number(item.score.toFixed(2)),
        rationale: item.why,
        objectiveTests: diffs[item.key].tests,
    }));
    const globalTests = triage === "red"
        ? [
            "Immobilize and arrange urgent elbow X-ray",
            "Neurovascular exam (pulses, capillary refill, motor/sensory)",
            "Same-day medical review if fever or hot, red joint",
        ]
        : [
            "Elbow AROM/PROM and end-range pain",
            "Grip dynamometry vs other side",
            "C-spine screen if neck/radicular features",
        ];
    return {
        region: "Elbow",
        triage,
        redFlagNotes: triage === "green" ? [] : notes,
        topDifferentials: top.map((t) => ({ name: t.name, score: t.score })),
        clinicalToDo: Array.from(new Set([...globalTests, ...top.flatMap((t) => t.objectiveTests)])),
        detailedTop: top,
    };
}
exports.processElbowAssessment = functions
    .region("europe-west1")
    .https.onCall(async (data, _ctx) => {
    const assessmentId = data === null || data === void 0 ? void 0 : data.assessmentId;
    const answers = Array.isArray(data === null || data === void 0 ? void 0 : data.answers) ? data.answers : [];
    if (!assessmentId) {
        throw new functions.https.HttpsError("invalid-argument", "assessmentId is required");
    }
    const summary = buildSummary(answers);
    const ref = db.collection("assessments").doc(assessmentId);
    await ref.set({
        triageStatus: summary.triage,
        topDifferentials: summary.topDifferentials,
        clinicianSummary: summary,
        triageRegion: "elbow",
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    }, { merge: true });
    return {
        triageStatus: summary.triage,
        topDifferentials: summary.topDifferentials,
        clinicianSummary: summary,
    };
});
//# sourceMappingURL=buildElbowSummary.js.map