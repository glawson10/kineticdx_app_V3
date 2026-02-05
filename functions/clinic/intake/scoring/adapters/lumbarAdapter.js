"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildLumbarAnswerMap = buildLumbarAnswerMap;
/**
 * Build AnswerMap for processLumbarAssessmentCore/processLumbarAssessment.ts
 * (expects legacy L_* keys).
 *
 * IMPORTANT: Do not invent data. Only map what is answered.
 */
function buildLumbarAnswerMap(answers) {
    const v = (qid) => { var _a; return (_a = answers[qid]) === null || _a === void 0 ? void 0 : _a.v; };
    const yesNo = (b) => (b === true ? "yes" : "no");
    // Helper: map multi optionIds like "aggs.bendLift" -> "bendLift"
    const stripPrefix = (s, prefix) => s.startsWith(prefix) ? s.slice(prefix.length) : s;
    // Helper: normalize multiChoice with a "none" option
    const multi = (qid, noneOptionId, prefixToStrip) => {
        const raw = v(qid);
        if (!Array.isArray(raw))
            return [];
        const cleaned = raw
            .filter((x) => typeof x === "string")
            .filter((x) => x !== noneOptionId)
            .map((x) => stripPrefix(x, prefixToStrip));
        return Array.from(new Set(cleaned));
    };
    const a = {
        // -------------------------
        // RED FLAGS (triageColour)
        // -------------------------
        L_rf_bladderBowel: yesNo(v("lumbar.redflags.bladderBowelChange")),
        L_rf_saddleNumbness: yesNo(v("lumbar.redflags.saddleAnaesthesia")),
        L_rf_progressiveWeak: yesNo(v("lumbar.redflags.progressiveWeakness")),
        L_rf_fever: yesNo(v("lumbar.redflags.feverUnwell")),
        L_rf_cancerHistory: yesNo(v("lumbar.redflags.historyOfCancer")),
        // If you later add a true "high energy" question, switch mapping to that.
        L_rf_highEnergyTrauma: yesNo(v("lumbar.redflags.recentTrauma")),
        L_rf_nightConstant: yesNo(v("lumbar.redflags.constantNightPain")),
        // -------------------------
        // CONTEXT
        // -------------------------
        L_age_band: (() => {
            const age = v("lumbar.context.ageBand");
            if (typeof age !== "string")
                return "";
            switch (age) {
                case "age.18_35":
                    return "18-35";
                case "age.36_50":
                    return "36-50";
                case "age.51_65":
                    return "51-65";
                case "age.65plus":
                    return "65+";
                default:
                    return "";
            }
        })(),
        // -------------------------
        // SYMPTOMS / PATTERN MATCHING
        // -------------------------
        L_painPattern: (() => {
            const p = v("lumbar.symptoms.painPattern");
            if (typeof p !== "string")
                return "";
            switch (p) {
                case "pattern.central":
                    return "central";
                case "pattern.oneSide":
                    return "oneSide";
                case "pattern.bothSides":
                    return "bothSides";
                default:
                    return "";
            }
        })(),
        // L_whereLeg expects codes: buttock, thigh, belowKnee, foot
        L_whereLeg: (() => {
            const raw = v("lumbar.symptoms.whereLeg");
            if (!Array.isArray(raw))
                return [];
            return Array.from(new Set(raw
                .filter((x) => typeof x === "string")
                .filter((x) => x !== "where.none")
                .map((x) => stripPrefix(x, "where."))));
        })(),
        // Neuro symptoms (scorer checks either/both)
        L_pinsNeedles: yesNo(v("lumbar.symptoms.pinsNeedles")),
        L_numbness: yesNo(v("lumbar.symptoms.numbness")),
        // Aggravators (bendLift, coughSneeze, extend, sitProlonged, stand, walk)
        L_aggs: multi("lumbar.symptoms.aggravators", "aggs.none", "aggs."),
        // Eases (backArched, lieKneesBent, shortWalk)
        L_eases: multi("lumbar.symptoms.easers", "eases.none", "eases."),
        // -------------------------
        // FUNCTION
        // -------------------------
        L_gaitAbility: (() => {
            const g = v("lumbar.function.gaitAbility");
            if (typeof g !== "string")
                return "";
            switch (g) {
                case "gait.normal":
                    return "normal";
                case "gait.limp":
                    return "limp";
                case "gait.support":
                    return "support";
                case "gait.cannot":
                    return "cannot";
                default:
                    return "";
            }
        })(),
    };
    return a;
}
//# sourceMappingURL=lumbarAdapter.js.map