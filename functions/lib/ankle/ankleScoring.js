"use strict";
// functions/src/ankle/ankleScoring.ts
//
// Pure ankle scoring module (no Firebase side effects).
// This is the canonical scorer used by your intake engines.
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildAnkleSummary = buildAnkleSummary;
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
            "Squeeze test (tibia/fibula)",
            "External rotation stress test",
            "Palpation syndesmosis + interosseous membrane",
            "Hop test (if appropriate)",
        ],
    },
    achilles_tendinopathy: {
        key: "achilles_tendinopathy",
        name: "Achilles tendinopathy / paratendinopathy",
        base: 0.25,
        tests: [
            "Palpation Achilles (midportion/insertion)",
            "Single-leg heel raises (capacity/pain)",
            "Pain provocation: hopping (if appropriate)",
            "Assess calf strength + ankle DF range",
        ],
    },
    plantar_fascia: {
        key: "plantar_fascia",
        name: "Plantar fascia / heel pain syndrome",
        base: 0.2,
        tests: [
            "Palpation medial calcaneal tubercle",
            "Windlass test",
            "1st step pain pattern history",
            "Ankle DF ROM, calf length",
        ],
    },
    midfoot_lisfranc: {
        key: "midfoot_lisfranc",
        name: "Midfoot / Lisfranc injury",
        base: 0.15,
        tests: [
            "Midfoot squeeze/compression",
            "Piano key test / dorsal-plantar translation",
            "Single-leg heel raise (if safe)",
            "Imaging pathway if suspicion persists",
        ],
    },
    fracture_possible: {
        key: "fracture_possible",
        name: "Fracture possible (Ottawa positive / severe injury)",
        base: 0.0,
        tests: ["Ottawa Ankle/Foot Rules", "X-ray referral pathway if positive"],
    },
    infection_or_gout: {
        key: "infection_or_gout",
        name: "Hot swollen joint (infection / gout / inflammatory)",
        base: 0.0,
        tests: [
            "Assess systemic symptoms + fever",
            "Urgent medical pathway per protocol",
            "Bloods per pathway",
        ],
    },
    dvt_possible: {
        key: "dvt_possible",
        name: "DVT possible (calf symptoms / risk)",
        base: 0.0,
        tests: [
            "Wells criteria / DVT screen per protocol",
            "Urgent medical pathway per protocol",
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
// ---------- triage ----------
function computeTriage(answers) {
    const notes = [];
    let force;
    const fromMech = getSingle(answers, "A_rf_fromFallTwistLanding");
    const followUps = getMulti(answers, "A_rf_followUps");
    const walk4Now = getSingle(answers, "A_rf_walk4Now");
    const highSwelling = getSingle(answers, "A_rf_highSwelling");
    const hotRedFever = getSingle(answers, "A_rf_hotRedFever");
    const calfHotTight = getSingle(answers, "A_rf_calfHotTight");
    const tiptoes = getSingle(answers, "A_rf_tiptoes");
    if (yes(hotRedFever)) {
        notes.push("Hot/red/swollen and feeling unwell/feverish");
        force = "infection_or_gout";
        return { triage: "red", notes, force };
    }
    if (yes(calfHotTight)) {
        notes.push("Calf hot/tight/tender – DVT screen required");
        force = "dvt_possible";
        return { triage: "red", notes, force };
    }
    const severeInjury = yes(fromMech) ||
        followUps.includes("deformity") ||
        followUps.includes("popHeard") ||
        followUps.includes("fourStepsImmediate");
    if (severeInjury && (walk4Now === "no" || walk4Now === "barely")) {
        notes.push("Severe injury pattern + cannot weight bear well");
        force = "fracture_possible";
        return { triage: "red", notes, force };
    }
    if (tiptoes === "notatall") {
        notes.push("Cannot go onto tiptoes – consider Achilles rupture");
        force = "achilles_rupture_urgent";
        return { triage: "red", notes, force };
    }
    if (yes(highSwelling) && (walk4Now === "no" || walk4Now === "barely")) {
        notes.push("High swelling with reduced weight bearing – consider syndesmosis/severe injury");
        return { triage: "amber", notes, force: undefined };
    }
    return { triage: "green", notes: [], force: undefined };
}
// ---------- scoring ----------
function score(answers, triage) {
    var _a;
    const S = Object.keys(diffs).reduce((acc, k) => {
        acc[k] = { score: diffs[k].base, why: [] };
        return acc;
    }, {});
    const mech = getSingle(answers, "A_mech");
    const painSite = getMulti(answers, "A_painSite");
    const loadAggs = getMulti(answers, "A_loadAggs");
    const onsetStyle = getSingle(answers, "A_onsetStyle");
    const timeSince = getSingle(answers, "A_timeSince");
    const instability = getSingle(answers, "A_instability");
    const impact = (_a = getSlider(answers, "A_impactScore")) !== null && _a !== void 0 ? _a : 0;
    const walk4Now = getSingle(answers, "A_rf_walk4Now");
    const highSwelling = getSingle(answers, "A_rf_highSwelling");
    const tiptoes = getSingle(answers, "A_rf_tiptoes");
    // Lateral sprain
    if (mech === "inversionRoll") {
        S.lateral_sprain.score += 0.5;
        S.lateral_sprain.why.push("Inversion mechanism");
    }
    if (painSite.includes("lateralATFL")) {
        S.lateral_sprain.score += 0.6;
        S.lateral_sprain.why.push("Lateral ligament pain site");
    }
    if (instability === "often") {
        S.lateral_sprain.score += 0.3;
        S.lateral_sprain.why.push("Frequent give-way / instability");
    }
    // Syndesmosis
    if (highSwelling === "yes") {
        S.syndesmosis.score += 0.45;
        S.syndesmosis.why.push("High swelling pattern");
    }
    if (painSite.includes("syndesmosisHigh")) {
        S.syndesmosis.score += 0.6;
        S.syndesmosis.why.push("High ankle pain site");
    }
    if (mech === "footFixedTwist") {
        S.syndesmosis.score += 0.25;
        S.syndesmosis.why.push("Foot planted + twist mechanism");
    }
    // Achilles tendinopathy
    if (painSite.includes("achilles")) {
        S.achilles_tendinopathy.score += 0.6;
        S.achilles_tendinopathy.why.push("Achilles pain site");
    }
    if (loadAggs.includes("stairsHillsTiptoe")) {
        S.achilles_tendinopathy.score += 0.35;
        S.achilles_tendinopathy.why.push("Worse with stairs/hills/tiptoe");
    }
    if (timeSince === ">6wk" || onsetStyle === "creeping" || onsetStyle === "creepingOn") {
        S.achilles_tendinopathy.score += 0.2;
        S.achilles_tendinopathy.why.push("Chronic/creeping onset pattern");
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
        S.midfoot_lisfranc.why.push("Midfoot pain site");
    }
    if (mech === "hardLanding") {
        S.midfoot_lisfranc.score += 0.25;
        S.midfoot_lisfranc.why.push("Hard landing mechanism");
    }
    if (loadAggs.includes("walkFlat") && loadAggs.includes("throbsAtRest")) {
        S.midfoot_lisfranc.score += 0.2;
        S.midfoot_lisfranc.why.push("Load painful + throbs at rest");
    }
    // Fracture possible bump if weight bearing poor
    if (walk4Now === "no") {
        S.fracture_possible.score += 0.5;
        S.fracture_possible.why.push("Cannot weight bear (4 steps)");
    }
    else if (walk4Now === "barely") {
        S.fracture_possible.score += 0.3;
        S.fracture_possible.why.push("Barely weight bearing");
    }
    // Achilles rupture signal
    if (tiptoes === "notatall") {
        S.achilles_rupture_urgent.score += 1.0;
        S.achilles_rupture_urgent.why.push("Cannot perform tiptoe");
    }
    // Global “impact” nudges
    if (impact >= 8) {
        S.fracture_possible.score += 0.1;
        S.syndesmosis.score += 0.05;
        S.lateral_sprain.score += 0.05;
    }
    // Triage modifiers
    if (triage === "amber") {
        S.syndesmosis.score += 0.05;
    }
    // (Optional) if you want chronicity to influence plantar/achilles etc you can add it here,
    // but don't change until you're sure it matches legacy behaviour.
    return S;
}
function buildAnkleSummary(answers) {
    const { triage, notes, force } = computeTriage(answers);
    const scored = score(answers, triage);
    const ranked = Object.keys(scored)
        .map((k) => ({ key: k, ...scored[k] }))
        .sort((a, b) => b.score - a.score);
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
//# sourceMappingURL=ankleScoring.js.map