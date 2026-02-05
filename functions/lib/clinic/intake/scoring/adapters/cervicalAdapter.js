"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildCervicalLegacyAnswers = buildCervicalLegacyAnswers;
function buildCervicalLegacyAnswers(answers) {
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
    // Map canonical optionIds -> engine expected enum
    const painLocationLegacy = (opt) => {
        // canonical: painLocation.central | painLocation.oneSide | painLocation.bothSides
        // engine expects: central | one_side | both_sides
        const s = typeof opt === "string" ? opt : "";
        if (s === "painLocation.oneSide")
            return "one_side";
        if (s === "painLocation.bothSides")
            return "both_sides";
        return "central";
    };
    return [
        // ---------------------------------------------------------------------
        // TRIAGE / RED FLAGS (must match engine IDs)
        // ---------------------------------------------------------------------
        single("C_rf_age65plus", yesNo(v("cervical.redflags.age65plus"))),
        single("C_rf_high_speed_crash", yesNo(v("cervical.redflags.highSpeedCrash"))),
        single("C_rf_paresthesia_post_incident", yesNo(v("cervical.redflags.paresthesiaPostIncident"))),
        single("C_rf_unable_walk_immediately", yesNo(v("cervical.redflags.unableWalkImmediately"))),
        single("C_rf_immediate_neck_pain", yesNo(v("cervical.redflags.immediateNeckPain"))),
        single("C_rf_rotation_lt45_both", yesNo(v("cervical.redflags.rotationLt45Both"))),
        single("C_rf_major_trauma", yesNo(v("cervical.redflags.majorTrauma"))),
        // Engine intent: “widespread neuro deficit”
        single("C_rf_neuro_deficit", yesNo(v("cervical.redflags.widespreadNeuroDeficit"))),
        single("C_rf_bladder_bowel", yesNo(v("cervical.redflags.bowelBladderChange"))),
        single("C_rf_cad_cluster", yesNo(v("cervical.redflags.cadCluster"))),
        single("C_night_pain", yesNo(v("cervical.redflags.nightPain"))),
        single("C_morning_stiff_30", yesNo(v("cervical.redflags.morningStiffnessOver30min"))),
        single("C_visual_disturbance", yesNo(v("cervical.redflags.visualDisturbance"))),
        // ✅ FIX: match your actual canonical questionId
        single("C_gait_unsteady", yesNo(v("cervical.redflags.balanceOrWalkingIssues"))),
        single("C_hand_clumsiness", yesNo(v("cervical.redflags.handClumsiness"))),
        // ---------------------------------------------------------------------
        // SCORING INPUTS
        // ---------------------------------------------------------------------
        single("C_pain_location", painLocationLegacy(v("cervical.symptoms.painLocation"))),
        single("C_pain_into_shoulder", yesNo(v("cervical.symptoms.painIntoShoulder"))),
        single("C_pain_below_elbow", yesNo(v("cervical.symptoms.painBelowElbow"))),
        // Pain worst 24h (0–10)
        slider("C_vas_worst", v("cervical.pain.worst24h")),
        single("C_arm_tingling", yesNo(v("cervical.symptoms.armTingling"))),
        single("C_arm_weakness", yesNo(v("cervical.redflags.armWeakness"))),
        single("C_cough_sneeze_worse", yesNo(v("cervical.symptoms.coughSneezeWorse"))),
        single("C_neck_movt_worse", yesNo(v("cervical.symptoms.neckMovementWorse"))),
        // Headache + modifiers
        single("C_headache_present", yesNo(v("cervical.symptoms.headache"))),
        single("C_headache_one_side", yesNo(v("cervical.symptoms.headacheOneSide"))),
        single("C_headache_worse_with_neck", yesNo(v("cervical.symptoms.headacheWorseWithNeck"))),
        single("C_headache_better_with_neck_care", yesNo(v("cervical.symptoms.headacheBetterWithNeckCare"))),
    ];
}
//# sourceMappingURL=cervicalAdapter.js.map