"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildKneeLegacyAnswers = buildKneeLegacyAnswers;
function buildKneeLegacyAnswers(answers) {
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
        if (x === "side.left")
            return "left";
        if (x === "side.right")
            return "right";
        if (x === "side.both")
            return "both";
        return undefined;
    };
    const mapOnset = (x) => {
        if (x === "onset.gradual")
            return "gradual";
        if (x === "onset.twist")
            return "twist";
        if (x === "onset.directBlow")
            return "directBlow";
        if (x === "onset.afterLoad")
            return "afterLoad";
        return "gradual";
    };
    const mapLoc = (x) => {
        if (x === "loc.front")
            return "front";
        if (x === "loc.medial")
            return "medial";
        if (x === "loc.lateral")
            return "lateral";
        if (x === "loc.back")
            return "back";
        return "diffuse";
    };
    const mapAggs = (arr) => {
        const xs = Array.isArray(arr) ? arr : [];
        if (xs.includes("aggs.none"))
            return [];
        return xs
            .map((x) => {
            if (x === "aggs.walk")
                return "walk";
            if (x === "aggs.stairs")
                return "stairs";
            if (x === "aggs.squat")
                return "squat";
            if (x === "aggs.run")
                return "run";
            if (x === "aggs.kneel")
                return "kneel";
            return null;
        })
            .filter(Boolean);
    };
    return {
        K_rf_traumaHighEnergy: v("knee.redflags.highEnergyTrauma") === true,
        K_rf_lockedKnee: v("knee.redflags.lockedKnee") === true,
        K_rf_hotSwollen: v("knee.redflags.hotSwollenJoint") === true,
        K_rf_unableWeightBear: v("knee.redflags.unableToWeightBear") === true,
        K_rf_historyCancer: v("knee.redflags.historyOfCancer") === true,
        K_side: mapSide(v("knee.context.side")),
        K_ageBand: mapAge(v("knee.context.ageBand")),
        K_onset: mapOnset(v("knee.history.onset")),
        K_painLocation: mapLoc(v("knee.symptoms.painLocation")),
        K_swelling: v("knee.symptoms.swelling") === true,
        K_givingWay: v("knee.symptoms.givingWay") === true,
        K_clickingLocking: v("knee.symptoms.clickingLocking") === true,
        K_stiffness: v("knee.symptoms.stiffness") === true,
        K_aggs: mapAggs(v("knee.function.aggravators")),
    };
}
//# sourceMappingURL=kneeAdapter%20-%20Copy.js.map