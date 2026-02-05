"use strict";
// functions/src/clinic/intake/scoring/adapters/lumbarAdapter.ts
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildLumbarLegacyAnswers = buildLumbarLegacyAnswers;
function buildLumbarLegacyAnswers(answers) {
    const v = (qid) => { var _a; return (_a = answers[qid]) === null || _a === void 0 ? void 0 : _a.v; };
    // Helpers to translate our canonical option ids to scorer option codes
    const mapAgeBand = (x) => {
        switch (x) {
            case "age.18_35":
                return "18-35";
            case "age.36_50":
                return "36-50";
            case "age.51_65":
                return "51-65";
            case "age.65plus":
                return "65+";
            default:
                return undefined;
        }
    };
    const mapPainPattern = (x) => {
        switch (x) {
            case "pattern.central":
                return "central";
            case "pattern.oneSide":
                return "oneSide";
            case "pattern.bothSides":
                return "bothSides";
            default:
                return undefined;
        }
    };
    const mapWhereLeg = (arr) => {
        const xs = Array.isArray(arr) ? arr : [];
        // If patient chose "none", return empty list (no leg distribution)
        if (xs.includes("where.none"))
            return [];
        return xs
            .map((x) => {
            switch (x) {
                case "where.buttock":
                    return "buttock";
                case "where.thigh":
                    return "thigh";
                case "where.belowKnee":
                    return "belowKnee";
                case "where.foot":
                    return "foot";
                default:
                    return null;
            }
        })
            .filter(Boolean);
    };
    const mapAggs = (arr) => {
        const xs = Array.isArray(arr) ? arr : [];
        if (xs.includes("aggs.none"))
            return [];
        return xs
            .map((x) => {
            switch (x) {
                case "aggs.bendLift":
                    return "bendLift";
                case "aggs.coughSneeze":
                    return "coughSneeze";
                case "aggs.walk":
                    return "walk";
                case "aggs.extend":
                    return "extend";
                case "aggs.sitProlonged":
                    return "sitProlonged";
                case "aggs.stand":
                    return "stand";
                default:
                    return null;
            }
        })
            .filter(Boolean);
    };
    const mapEases = (arr) => {
        const xs = Array.isArray(arr) ? arr : [];
        if (xs.includes("eases.none"))
            return [];
        return xs
            .map((x) => {
            switch (x) {
                case "eases.backArched":
                    return "backArched";
                case "eases.lieKneesBent":
                    return "lieKneesBent";
                case "eases.shortWalk":
                    return "shortWalk";
                default:
                    return null;
            }
        })
            .filter(Boolean);
    };
    const mapGait = (x) => {
        switch (x) {
            case "gait.normal":
                return "normal";
            case "gait.limp":
                return "limp";
            case "gait.support":
                return "support";
            case "gait.cannot":
                return "cannot";
            default:
                return undefined;
        }
    };
    return {
        // --- Red flags used directly in triageColour()
        L_rf_bladderBowel: v("lumbar.redflags.bladderBowelChange") === true,
        L_rf_saddleNumbness: v("lumbar.redflags.saddleAnaesthesia") === true,
        L_rf_progressiveWeak: v("lumbar.redflags.progressiveWeakness") === true,
        L_rf_fever: v("lumbar.redflags.feverUnwell") === true,
        L_rf_cancerHistory: v("lumbar.redflags.historyOfCancer") === true,
        L_rf_highEnergyTrauma: v("lumbar.redflags.recentTrauma") === true,
        L_rf_nightConstant: v("lumbar.redflags.constantNightPain") === true,
        // --- Scoring features
        L_age_band: mapAgeBand(v("lumbar.context.ageBand")),
        L_painPattern: mapPainPattern(v("lumbar.symptoms.painPattern")),
        L_whereLeg: mapWhereLeg(v("lumbar.symptoms.whereLeg")),
        L_aggs: mapAggs(v("lumbar.symptoms.aggravators")),
        L_eases: mapEases(v("lumbar.symptoms.easers")),
        L_pinsNeedles: v("lumbar.symptoms.pinsNeedles") === true,
        L_numbness: v("lumbar.symptoms.numbness") === true,
        L_gaitAbility: mapGait(v("lumbar.function.gaitAbility")),
    };
}
//# sourceMappingURL=lumbarAdapter%20-%20Copy.js.map