"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildWristLegacyAnswers = buildWristLegacyAnswers;
/**
 * Build legacy Answer[] for the wrist scorer.
 *
 * Dart source of truth (v1):
 *  - wrist_questions_v1.dart (TS-aligned IDs + optionIds)
 * Legacy IDs expected by TS scorer:
 *  - Q1_system (multi)
 *  - Q2_injury (single)
 *  - Q3_injury_cluster (multi)
 *  - Q_side (single)
 *  - Q4_zone (single)
 *  - Q5_onset (single)
 *  - Q6a_mech (multi)
 *  - Q6b_aggs (multi)
 *  - Q7_features (multi)
 *  - Q8_weightbear (single)
 *  - Q10_risks (multi)
 *
 * NOTE: Returned array is ordered with RED FLAGS FIRST (Q1–Q3).
 * :contentReference[oaicite:0]{index=0} :contentReference[oaicite:1]{index=1}
 */
function buildWristLegacyAnswers(answers) {
    var _a, _b, _c, _d, _e;
    const v = (qid) => { var _a; return (_a = answers[qid]) === null || _a === void 0 ? void 0 : _a.v; };
    const single = (id, value) => ({
        id,
        kind: "single",
        value: value == null ? "" : String(value),
    });
    const multi = (id, values) => ({
        id,
        kind: "multi",
        values,
    });
    const slider = (id, value) => ({
        id,
        kind: "slider",
        value: typeof value === "number" ? value : Number(value !== null && value !== void 0 ? value : 0) || 0,
    });
    const asStringArray = (x) => Array.isArray(x) ? x.filter((s) => typeof s === "string") : [];
    const stripPrefix = (s, prefix) => s.startsWith(prefix) ? s.slice(prefix.length) : s;
    const noneIfEmpty = (arr) => (arr.length ? arr : ["none"]);
    // ---------------------------------------------------------------------------
    // RED FLAGS / SAFETY — FIRST (triage relies heavily on these)
    // ---------------------------------------------------------------------------
    // Q1_system (multi): fever | wtloss | both_hands_tingles | extreme_colour_temp | constant_night
    // Dart: wrist.redflags.systemic optionIds: system.*
    const systemRaw = asStringArray(v("wrist.redflags.systemic"));
    const system = noneIfEmpty(systemRaw
        .map((id) => stripPrefix(id, "system."))
        .filter((tok) => [
        "fever",
        "wtloss",
        "both_hands_tingles",
        "extreme_colour_temp",
        "constant_night",
    ].includes(tok)));
    // Q2_injury (single): yes | no
    // Dart: wrist.redflags.acuteInjury optionIds: injury.yes / injury.no
    const acuteInjury = String((_a = v("wrist.redflags.acuteInjury")) !== null && _a !== void 0 ? _a : "");
    const Q2_injury = acuteInjury === "injury.yes" ? "yes" : acuteInjury === "injury.no" ? "no" : "";
    // Q3_injury_cluster (multi): no_weight_bear | pop_crack | deformity | severe_pain | immediate_numb
    // Dart: wrist.redflags.injuryCluster optionIds: inj.*
    // Enforce conditional logic: only pass cluster if acute injury == yes; else none.
    const injClusterRaw = Q2_injury === "yes"
        ? asStringArray(v("wrist.redflags.injuryCluster"))
        : [];
    const injuryCluster = noneIfEmpty(injClusterRaw
        .map((id) => stripPrefix(id, "inj."))
        .filter((tok) => ["no_weight_bear", "pop_crack", "deformity", "severe_pain", "immediate_numb"].includes(tok)));
    // ---------------------------------------------------------------------------
    // CONTEXT
    // ---------------------------------------------------------------------------
    // Q_side (single): Left | Right | Both | Not sure
    // Dart: wrist.context.side optionIds: side.left/right/both/unsure
    const side = String((_b = v("wrist.context.side")) !== null && _b !== void 0 ? _b : "");
    const Q_side = side === "side.left"
        ? "Left"
        : side === "side.right"
            ? "Right"
            : side === "side.both"
                ? "Both"
                : side === "side.unsure"
                    ? "Not sure"
                    : "";
    // ---------------------------------------------------------------------------
    // SYMPTOMS / HISTORY — DIFFERENTIAL DRIVERS
    // ---------------------------------------------------------------------------
    // Q4_zone (single): radial | ulnar | dorsal | volar | diffuse
    // Dart: wrist.symptoms.zone optionIds: zone.*
    const zoneRaw = String((_c = v("wrist.symptoms.zone")) !== null && _c !== void 0 ? _c : "");
    const Q4_zone = (() => {
        const tok = stripPrefix(zoneRaw, "zone.");
        return ["radial", "ulnar", "dorsal", "volar", "diffuse"].includes(tok) ? tok : "";
    })();
    // Q5_onset (single): sudden | gradual | unsure
    // Dart: wrist.history.onset optionIds: onset.*
    const onsetRaw = String((_d = v("wrist.history.onset")) !== null && _d !== void 0 ? _d : "");
    const Q5_onset = (() => {
        const tok = stripPrefix(onsetRaw, "onset.");
        return ["sudden", "gradual", "unsure"].includes(tok) ? tok : "";
    })();
    // Q6a_mech (multi): foosh  (only FOOSH referenced by TS scoring)
    // Dart: wrist.history.mechanism optionIds include mech.foosh
    const mechRaw = asStringArray(v("wrist.history.mechanism"));
    const Q6a_mech = noneIfEmpty(mechRaw
        .map((id) => stripPrefix(id, "mech."))
        .filter((tok) => tok === "foosh"));
    // Q6b_aggs (multi): grip_lift | twist | typing | weight_bear
    // Dart: wrist.symptoms.aggravators optionIds: aggs.*
    const aggsRaw = asStringArray(v("wrist.symptoms.aggravators"));
    const Q6b_aggs = noneIfEmpty(aggsRaw
        .map((id) => stripPrefix(id, "aggs."))
        .filter((tok) => ["typing", "grip_lift", "weight_bear", "twist"].includes(tok)));
    // Q7_features (multi): swelling | bump_shape | clicking | weak_grip | tingle_thumb_index | extreme_colour_temp
    // Dart: wrist.symptoms.features optionIds: feat.*
    const featRaw = asStringArray(v("wrist.symptoms.features"));
    const Q7_features = noneIfEmpty(featRaw
        .map((id) => stripPrefix(id, "feat."))
        .filter((tok) => [
        "swelling",
        "bump_shape",
        "clicking",
        "weak_grip",
        "tingle_thumb_index",
        "extreme_colour_temp",
    ].includes(tok)));
    // Q8_weightbear (single): yes_ok | yes_pain | no
    // Dart: wrist.function.weightBear optionIds: wb.*
    const wbRaw = String((_e = v("wrist.function.weightBear")) !== null && _e !== void 0 ? _e : "");
    const Q8_weightbear = (() => {
        const tok = stripPrefix(wbRaw, "wb.");
        return ["yes_ok", "yes_pain", "no"].includes(tok) ? tok : "";
    })();
    // Q10_risks (multi): post_meno | preg_postpartum
    // Dart: wrist.context.risks optionIds: risk.*
    const risksRaw = asStringArray(v("wrist.context.risks"));
    const Q10_risks = noneIfEmpty(risksRaw
        .map((id) => stripPrefix(id, "risk."))
        .filter((tok) => ["post_meno", "preg_postpartum"].includes(tok)));
    // ---------------------------------------------------------------------------
    // Return in a stable, scorer-friendly order (RED FLAGS FIRST)
    // ---------------------------------------------------------------------------
    return [
        // Red flags / triage
        multi("Q1_system", system),
        single("Q2_injury", Q2_injury),
        multi("Q3_injury_cluster", injuryCluster),
        // Context
        single("Q_side", Q_side),
        // Differential drivers
        single("Q4_zone", Q4_zone),
        single("Q5_onset", Q5_onset),
        multi("Q6a_mech", Q6a_mech),
        multi("Q6b_aggs", Q6b_aggs),
        multi("Q7_features", Q7_features),
        single("Q8_weightbear", Q8_weightbear),
        multi("Q10_risks", Q10_risks),
        // If you keep any generic pipeline assumptions about sliders, keep them separate;
        // wrist scorer does NOT consume a pain slider legacy id.
        slider("Q_pain_now_unused", v("wrist.pain.now")),
    ];
}
//# sourceMappingURL=wristAdapter.js.map