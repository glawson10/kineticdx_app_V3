"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildAnkleLegacyAnswers = buildAnkleLegacyAnswers;
/**
 * Build the exact legacy Answer[] required by the ankle scorer.
 * This function must stay in lockstep with:
 * - ankle_questions_v1.dart
 * - processAnkleAssessment.ts
 */
function buildAnkleLegacyAnswers(answers) {
    const v = (qid) => { var _a; return (_a = answers[qid]) === null || _a === void 0 ? void 0 : _a.v; };
    const yesNo = (b) => (b === true ? "yes" : "no");
    const single = (id, value) => ({
        id,
        kind: "single",
        value: value == null ? "" : String(value),
    });
    const multi = (id, arr) => ({
        id,
        kind: "multi",
        values: Array.isArray(arr) ? arr.map(String) : [],
    });
    const slider = (id, value) => ({
        id,
        kind: "slider",
        value: typeof value === "number" ? value : Number(value !== null && value !== void 0 ? value : 0),
    });
    const strip = (val, prefix) => typeof val === "string" && val.startsWith(prefix)
        ? val.substring(prefix.length)
        : "";
    const stripMany = (arr, prefix) => Array.isArray(arr)
        ? arr
            .map((x) => typeof x === "string" && x.startsWith(prefix)
            ? x.substring(prefix.length)
            : null)
            .filter(Boolean)
        : [];
    /**
     * Enforce mutual exclusivity for a "none" option in a multi-select.
     * - If only "none" selected => treat as no positives []
     * - If "none" + others => drop "none"
     */
    const stripManyExclusiveNone = (arr, prefix, noneValue) => {
        const out = stripMany(arr, prefix);
        if (out.length === 0)
            return out;
        if (out.length === 1) {
            return out[0] === noneValue ? [] : out;
        }
        return out.filter((x) => x !== noneValue);
    };
    return [
        // -------------------------
        // RED FLAGS
        // -------------------------
        single("A_rf_fromFallTwistLanding", yesNo(v("ankle.redflags.fromFallTwistLanding"))),
        multi("A_rf_followUps", stripManyExclusiveNone(v("ankle.redflags.followUps"), "follow.", "none")),
        single("A_rf_walk4Now", strip(v("ankle.redflags.walk4StepsNow"), "walk4.")),
        single("A_rf_hotRedFever", yesNo(v("ankle.redflags.hotRedFeverish"))),
        single("A_rf_calfHotTight", yesNo(v("ankle.redflags.calfHotTight"))),
        // tiptoes is a single-choice (e.g., tiptoes.yes / tiptoes.partial / tiptoes.notatall)
        single("A_rf_tiptoes", strip(v("ankle.redflags.tiptoes"), "tiptoes.")),
        single("A_rf_highSwelling", yesNo(v("ankle.redflags.highSwelling"))),
        // -------------------------
        // HISTORY / CONTEXT
        // -------------------------
        single("A_mech", strip(v("ankle.history.mechanism"), "mechanism.")),
        single("A_timeSince", strip(v("ankle.history.timeSinceStart"), "time.")),
        single("A_onsetStyle", strip(v("ankle.history.onsetStyle"), "onset.")),
        // -------------------------
        // SYMPTOMS
        // -------------------------
        multi("A_painSite", stripMany(v("ankle.symptoms.painSite"), "painSite.")),
        // -------------------------
        // FUNCTION
        // -------------------------
        multi("A_loadAggs", stripManyExclusiveNone(v("ankle.function.loadAggravators"), "load.", "none")),
        single("A_instability", strip(v("ankle.function.instability"), "instability.")),
        // -------------------------
        // IMPACT SCORE
        // -------------------------
        slider("A_impactScore", v("ankle.function.dayImpact")),
    ];
}
//# sourceMappingURL=ankleAdapter.js.map