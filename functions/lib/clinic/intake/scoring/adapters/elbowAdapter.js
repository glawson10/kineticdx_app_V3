"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildElbowLegacyAnswers = buildElbowLegacyAnswers;
function buildElbowLegacyAnswers(answers) {
    const v = (qid) => { var _a; return (_a = answers[qid]) === null || _a === void 0 ? void 0 : _a.v; };
    const yesNo = (b) => (b === true ? "yes" : "no");
    const single = (id, value) => ({
        id,
        kind: "single",
        value: value == null ? "" : String(value),
    });
    const slider = (id, value) => ({
        id,
        kind: "slider",
        value: typeof value === "number" ? value : Number(value !== null && value !== void 0 ? value : 0),
    });
    const multi = (id, arr) => ({
        id,
        kind: "multi",
        values: Array.isArray(arr) ? arr.map(String) : [],
    });
    // Map onset (canonical) -> TS expected values: gradual | sudden | traumaHigh | unknown
    const onsetToTS = (onset) => {
        const o = typeof onset === "string" ? onset : "";
        switch (o) {
            case "onset.gradual":
            case "onset.afterLoad":
                return "gradual";
            case "onset.afterTrauma":
                return "traumaHigh";
            case "onset.unsure":
            default:
                return "unknown";
        }
    };
    // Map pain location (canonical) -> TS E_loc values
    const locToTS = (loc) => {
        const s = typeof loc === "string" ? loc : "";
        switch (s) {
            case "loc.lateral":
                return "lateral";
            case "loc.medial":
                return "medial";
            case "loc.posterior":
                return "posterior";
            case "loc.anterior":
                return "anterior";
            case "loc.diffuse":
                return "diffuse";
            default:
                return "";
        }
    };
    // Map canonical aggravators -> TS E_aggs coded values
    const aggsToTS = (xs) => {
        const arr = Array.isArray(xs) ? xs.map(String) : [];
        const out = [];
        const has = (id) => arr.includes(id);
        if (has("aggs.palmDownGrip"))
            out.push("palmDownGrip");
        if (has("aggs.twistJar"))
            out.push("twistJar");
        if (has("aggs.palmUpCarry"))
            out.push("palmUpCarry");
        if (has("aggs.overheadThrow"))
            out.push("overheadThrow");
        if (has("aggs.restOnOlecranon"))
            out.push("restOnOlecranon");
        if (has("aggs.pushUpWB"))
            out.push("pushUpWB");
        // If "none" selected, return empty set (it should override others)
        if (has("aggs.none"))
            return [];
        return out;
    };
    const side = typeof v("elbow.context.side") === "string" ? String(v("elbow.context.side")) : "";
    const bilateral = side === "side.both";
    return [
        // -----------------------------------------------------------------------
        // Safety / triage (include both older + newer RF ids for robustness)
        // -----------------------------------------------------------------------
        single("E_rf_trauma", yesNo(v("elbow.redflags.trauma"))),
        single("E_rf_fever", yesNo(v("elbow.redflags.fever"))),
        single("E_rf_infectionRisk", yesNo(v("elbow.redflags.infectionRisk"))),
        single("E_rf_neuroDeficit", yesNo(v("elbow.redflags.neuroDeficit"))),
        single("E_rf_injury_force", yesNo(v("elbow.redflags.injuryForce"))),
        single("E_rf_swelling", yesNo(v("elbow.redflags.rapidSwelling"))),
        single("E_rf_deformity", yesNo(v("elbow.redflags.visibleDeformity"))),
        // TS expects E_can_straighten as yes/no
        single("E_can_straighten", yesNo(v("elbow.redflags.canStraighten"))),
        // TS extra triage-style flag
        single("E_hot_swollen_no_fever", yesNo(v("elbow.redflags.hotSwollenNoFever"))),
        // Some scorer versions use E_rf_numb specifically
        single("E_rf_numb", yesNo(v("elbow.redflags.neuroDeficit"))),
        // -----------------------------------------------------------------------
        // Context
        // -----------------------------------------------------------------------
        single("E_side", side),
        single("E_dominantSide", v("elbow.context.dominantSide")),
        single("E_bilateral", bilateral ? "yes" : "no"),
        // -----------------------------------------------------------------------
        // Pain (if the scorer uses them; safe to include)
        // -----------------------------------------------------------------------
        slider("E_pain_now", v("elbow.pain.now")),
        slider("E_pain_worst24h", v("elbow.pain.worst24h")),
        // -----------------------------------------------------------------------
        // History / onset
        // -----------------------------------------------------------------------
        single("E_onset", onsetToTS(v("elbow.history.onset"))),
        // -----------------------------------------------------------------------
        // Location
        // -----------------------------------------------------------------------
        single("E_loc", locToTS(v("elbow.symptoms.painLocation"))),
        // -----------------------------------------------------------------------
        // Baseline symptom flags (older ids some scorers still reference)
        // -----------------------------------------------------------------------
        single("E_grippingPain", yesNo(v("elbow.symptoms.grippingPain"))),
        single("E_stiffness", yesNo(v("elbow.symptoms.stiffness"))),
        single("E_swelling", yesNo(v("elbow.symptoms.swelling"))),
        // -----------------------------------------------------------------------
        // Differential drivers used by the current scorer
        // -----------------------------------------------------------------------
        multi("E_aggs", aggsToTS(v("elbow.function.aggravators"))),
        single("E_swelling_post", yesNo(v("elbow.symptoms.swellingAfterActivity"))),
        single("E_click_snap", yesNo(v("elbow.symptoms.clickSnap"))),
        single("E_catching", yesNo(v("elbow.symptoms.catching"))),
        single("E_stiff_morning", yesNo(v("elbow.symptoms.morningStiffness"))),
        single("E_pop_ant", yesNo(v("elbow.symptoms.popAnterior"))),
        single("E_pain_forearm_thumbside", yesNo(v("elbow.symptoms.forearmThumbSidePain"))),
        single("E_para_ulnar", yesNo(v("elbow.symptoms.paraUlnar"))),
        single("E_para_thumbindex", yesNo(v("elbow.symptoms.paraThumbIndex"))),
        single("E_neck_radiation", yesNo(v("elbow.symptoms.neckRadiation"))),
        single("E_pronation_pain", yesNo(v("elbow.symptoms.pronationPain"))),
        single("E_resisted_extension_pain", yesNo(v("elbow.symptoms.resistedExtensionPain"))),
        single("E_throw_valgus_pain", yesNo(v("elbow.symptoms.throwValgusPain"))),
        single("E_posteromedial_endext", yesNo(v("elbow.symptoms.posteromedialEndRangeExtensionPain"))),
    ];
}
//# sourceMappingURL=elbowAdapter.js.map