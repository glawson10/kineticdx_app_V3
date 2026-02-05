"use strict";
// functions/src/clinic/intake/scoring/adapters/wristAdapter.ts
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildWristLegacyAnswers = buildWristLegacyAnswers;
function buildWristLegacyAnswers(canonical) {
    var _a, _b, _c, _d;
    const v = (qid) => { var _a; return (_a = canonical[qid]) === null || _a === void 0 ? void 0 : _a.v; };
    // ---------------------------
    // Q1_system (multi)
    // ---------------------------
    const sysCanon = Array.isArray(v("wrist.redflags.systemic"))
        ? v("wrist.redflags.systemic")
        : [];
    const sysMap = {
        "system.fever": "fever",
        "system.wtloss": "wtloss",
        "system.both_hands_tingles": "both_hands_tingles",
        "system.extreme_colour_temp": "extreme_colour_temp",
        "system.constant_night": "constant_night",
    };
    const Q1_system = sysCanon
        .map((x) => sysMap[String(x)])
        .filter(Boolean);
    // ---------------------------
    // Q2_injury (single yes/no)
    // ---------------------------
    const acute = v("wrist.redflags.acuteInjury");
    const Q2_injury = acute === "injury.yes" ? "yes" : "no";
    // ---------------------------
    // Q3_injury_cluster (multi, only meaningful if Q2_injury==yes)
    // ---------------------------
    const clusterCanon = Array.isArray(v("wrist.redflags.injuryCluster"))
        ? v("wrist.redflags.injuryCluster")
        : [];
    const clusterMap = {
        "inj.no_weight_bear": "no_weight_bear",
        "inj.pop_crack": "pop_crack",
        "inj.deformity": "deformity",
        "inj.severe_pain": "severe_pain",
        "inj.immediate_numb": "immediate_numb",
    };
    const Q3_injury_cluster = Q2_injury === "yes"
        ? clusterCanon.map((x) => clusterMap[String(x)]).filter(Boolean)
        : [];
    // ---------------------------
    // Q4_zone (single)
    // ---------------------------
    const zoneMap = {
        "zone.radial": "radial",
        "zone.ulnar": "ulnar",
        "zone.dorsal": "dorsal",
        "zone.volar": "volar",
        "zone.diffuse": "diffuse",
    };
    const Q4_zone = (_a = zoneMap[String(v("wrist.symptoms.zone"))]) !== null && _a !== void 0 ? _a : "diffuse";
    // ---------------------------
    // Q5_onset (single)
    // ---------------------------
    const onsetMap = {
        "onset.sudden": "sudden",
        "onset.gradual": "gradual",
        "onset.unsure": "unsure",
    };
    const Q5_onset = (_b = onsetMap[String(v("wrist.history.onset"))]) !== null && _b !== void 0 ? _b : "unsure";
    // ---------------------------
    // Q6a_mech (multi)
    // ---------------------------
    const mechCanon = Array.isArray(v("wrist.history.mechanism"))
        ? v("wrist.history.mechanism")
        : [];
    const mechMap = {
        "mech.foosh": "foosh",
        "mech.twist": "twist",
        "mech.typing": "typing",
        "mech.grip_lift": "grip_lift",
    };
    const Q6a_mech = mechCanon
        .map((x) => mechMap[String(x)])
        .filter(Boolean);
    // ---------------------------
    // Q6b_aggs (multi)
    // ---------------------------
    const aggsCanon = Array.isArray(v("wrist.symptoms.aggravators"))
        ? v("wrist.symptoms.aggravators")
        : [];
    const aggsMap = {
        "aggs.typing": "typing",
        "aggs.grip_lift": "grip_lift",
        "aggs.weight_bear": "weight_bear",
        "aggs.twist": "twist",
    };
    const Q6b_aggs = aggsCanon
        .map((x) => aggsMap[String(x)])
        .filter(Boolean);
    // ---------------------------
    // Q7_features (multi)
    // ---------------------------
    const featCanon = Array.isArray(v("wrist.symptoms.features"))
        ? v("wrist.symptoms.features")
        : [];
    const featMap = {
        "feat.swelling": "swelling",
        "feat.bump_shape": "bump_shape",
        "feat.clicking": "clicking",
        "feat.weak_grip": "weak_grip",
        "feat.tingle_thumb_index": "tingle_thumb_index",
        "feat.extreme_colour_temp": "extreme_colour_temp",
    };
    const Q7_features = featCanon
        .map((x) => featMap[String(x)])
        .filter(Boolean);
    // ---------------------------
    // Q8_weightbear (single)
    // ---------------------------
    const wbMap = {
        "wb.yes_ok": "yes_ok",
        "wb.yes_pain": "yes_pain",
        "wb.no": "no",
    };
    const Q8_weightbear = (_c = wbMap[String(v("wrist.function.weightBear"))]) !== null && _c !== void 0 ? _c : "no";
    // ---------------------------
    // Q10_risks (multi)
    // ---------------------------
    const risksCanon = Array.isArray(v("wrist.context.risks"))
        ? v("wrist.context.risks")
        : [];
    const riskMap = {
        "risk.post_meno": "post_meno",
        "risk.preg_postpartum": "preg_postpartum",
    };
    const Q10_risks = risksCanon
        .map((x) => riskMap[String(x)])
        .filter(Boolean);
    // ---------------------------
    // Q_side (single)
    // ---------------------------
    const sideMap = {
        "side.left": "left",
        "side.right": "right",
        "side.both": "both",
        "side.unsure": "unsure",
    };
    const Q_side = (_d = sideMap[String(v("wrist.context.side"))]) !== null && _d !== void 0 ? _d : "unsure";
    // Build legacy Answer[] in TS format
    return [
        { id: "Q1_system", kind: "multi", values: Q1_system }, // ✅ FIXED
        { id: "Q2_injury", kind: "single", value: Q2_injury },
        { id: "Q3_injury_cluster", kind: "multi", values: Q3_injury_cluster },
        { id: "Q4_zone", kind: "single", value: Q4_zone },
        { id: "Q5_onset", kind: "single", value: Q5_onset },
        { id: "Q6a_mech", kind: "multi", values: Q6a_mech },
        { id: "Q6b_aggs", kind: "multi", values: Q6b_aggs },
        { id: "Q7_features", kind: "multi", values: Q7_features },
        { id: "Q8_weightbear", kind: "single", value: Q8_weightbear },
        { id: "Q10_risks", kind: "multi", values: Q10_risks },
        { id: "Q_side", kind: "single", value: Q_side },
    ];
}
//# sourceMappingURL=wristAdapter%20-%20Copy.js.map