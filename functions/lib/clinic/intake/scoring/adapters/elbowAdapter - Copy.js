"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildElbowLegacyAnswers = buildElbowLegacyAnswers;
function buildElbowLegacyAnswers(answers) {
    const v = (qid) => { var _a; return (_a = answers[qid]) === null || _a === void 0 ? void 0 : _a.v; };
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
        if (x === "onset.afterLoad")
            return "afterLoad";
        if (x === "onset.afterTrauma")
            return "afterTrauma";
        return "gradual";
    };
    const mapLocation = (x) => {
        if (x === "loc.lateral")
            return "lateral";
        if (x === "loc.medial")
            return "medial";
        if (x === "loc.posterior")
            return "posterior";
        return "diffuse";
    };
    const mapAggs = (arr) => {
        const xs = Array.isArray(arr) ? arr : [];
        if (xs.includes("aggs.none"))
            return [];
        return xs
            .map((x) => {
            if (x === "aggs.grip")
                return "grip";
            if (x === "aggs.lift")
                return "lift";
            if (x === "aggs.twist")
                return "twist";
            if (x === "aggs.restingOnElbow")
                return "restingOnElbow";
            return null;
        })
            .filter(Boolean);
    };
    return {
        E_rf_trauma: v("elbow.redflags.trauma") === true,
        E_rf_fever: v("elbow.redflags.fever") === true,
        E_rf_infectionRisk: v("elbow.redflags.infectionRisk") === true,
        E_rf_neuroDeficit: v("elbow.redflags.neuroDeficit") === true,
        E_side: mapSide(v("elbow.context.side")),
        E_dominantSide: v("elbow.context.dominantSide"),
        E_onset: mapOnset(v("elbow.history.onset")),
        E_painLocation: mapLocation(v("elbow.symptoms.painLocation")),
        E_grippingPain: v("elbow.symptoms.grippingPain") === true,
        E_stiffness: v("elbow.symptoms.stiffness") === true,
        E_swelling: v("elbow.symptoms.swelling") === true,
        E_aggs: mapAggs(v("elbow.function.aggravators")),
    };
}
//# sourceMappingURL=elbowAdapter%20-%20Copy.js.map