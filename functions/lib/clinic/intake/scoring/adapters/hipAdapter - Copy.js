"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildHipLegacyAnswers = buildHipLegacyAnswers;
function buildHipLegacyAnswers(answers) {
    const v = (qid) => { var _a; return (_a = answers[qid]) === null || _a === void 0 ? void 0 : _a.v; };
    const mapAge = (x) => {
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
    const mapSide = (x) => {
        switch (x) {
            case "side.left":
                return "left";
            case "side.right":
                return "right";
            case "side.both":
                return "both";
            default:
                return undefined;
        }
    };
    const mapLoc = (x) => {
        switch (x) {
            case "loc.groin":
                return "groin";
            case "loc.outer":
                return "outer";
            case "loc.buttock":
                return "buttock";
            default:
                return "diffuse";
        }
    };
    const mapAggs = (arr) => {
        const xs = Array.isArray(arr) ? arr : [];
        if (xs.includes("aggs.none"))
            return [];
        return xs
            .map((x) => {
            switch (x) {
                case "aggs.walk":
                    return "walk";
                case "aggs.stairs":
                    return "stairs";
                case "aggs.sitLong":
                    return "sitLong";
                case "aggs.twist":
                    return "twist";
                case "aggs.run":
                    return "run";
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
                case "eases.rest":
                    return "rest";
                case "eases.shortWalk":
                    return "shortWalk";
                case "eases.heat":
                    return "heat";
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
        H_rf_traumaHighEnergy: v("hip.redflags.highEnergyTrauma") === true,
        H_rf_feverUnwell: v("hip.redflags.feverUnwell") === true,
        H_rf_cancerHistory: v("hip.redflags.historyOfCancer") === true,
        H_rf_constantNightPain: v("hip.redflags.constantNightPain") === true,
        H_rf_unableWeightBear: v("hip.redflags.unableToWeightBear") === true,
        H_ageBand: mapAge(v("hip.context.ageBand")),
        H_side: mapSide(v("hip.context.side")),
        H_painLocation: mapLoc(v("hip.symptoms.painLocation")),
        H_groinPain: v("hip.symptoms.groinPain") === true,
        H_clickingCatching: v("hip.symptoms.clickingCatching") === true,
        H_stiffness: v("hip.symptoms.stiffness") === true,
        H_aggs: mapAggs(v("hip.symptoms.aggravators")),
        H_eases: mapEases(v("hip.symptoms.easers")),
        H_gaitAbility: mapGait(v("hip.function.gaitAbility")),
    };
}
//# sourceMappingURL=hipAdapter%20-%20Copy.js.map