"use strict";
// functions/src/clinic/intake/scoring/adapters/shoulderAdapter.ts
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildShoulderLegacyInput = buildShoulderLegacyInput;
function buildShoulderLegacyInput(answers) {
    const v = (qid) => { var _a; return (_a = answers[qid]) === null || _a === void 0 ? void 0 : _a.v; };
    const mapSide = (x) => {
        switch (x) {
            case "side.left":
                return "left";
            case "side.right":
                return "right";
            case "side.both":
                return "both";
            case "side.unsure":
            default:
                return "";
        }
    };
    const mapOnset = (x) => {
        switch (x) {
            case "onset.gradual":
                return "gradual";
            case "onset.afterOverhead":
                return "afterOverhead";
            case "onset.afterLiftPull":
                return "afterLiftPull";
            case "onset.minorFallJar":
                return "minorFallJar";
            case "onset.appeared":
                return "appeared";
            default:
                return "gradual";
        }
    };
    const mapPainArea = (x) => {
        switch (x) {
            case "painArea.top_front":
                return "top_front";
            case "painArea.outer_side":
                return "outer_side";
            case "painArea.back":
                return "back";
            case "painArea.diffuse":
            default:
                return "diffuse";
        }
    };
    const mapTenderSpot = (x) => {
        switch (x) {
            case "tender.ac_point":
                return "ac_point";
            case "tender.bicipital_groove":
                return "bicipital_groove";
            case "tender.none_unsure":
            default:
                return "none_unsure";
        }
    };
    // TS compares functionLimits strings EXACTLY.
    const mapFunctionLimits = (arr) => {
        const xs = Array.isArray(arr) ? arr : [];
        if (xs.includes("limit.none"))
            return [];
        const out = [];
        for (const x of xs) {
            if (x === "limit.reaching_overhead")
                out.push("Reaching overhead");
            if (x === "limit.sports_overhead_work")
                out.push("Sports/overhead work");
            if (x === "limit.putting_on_jacket")
                out.push("Putting on a jacket");
            if (x === "limit.sleeping_on_side")
                out.push("Sleeping on that side");
        }
        return out;
    };
    return {
        answers: {
            side: mapSide(v("shoulder.context.side")),
            onset: mapOnset(v("shoulder.history.onset")),
            painArea: mapPainArea(v("shoulder.symptoms.painArea")),
            nightPain: v("shoulder.symptoms.nightPain") === true,
            overheadAggravates: v("shoulder.symptoms.overheadAggravates") === true,
            weakness: v("shoulder.symptoms.weakness") === true,
            stiffness: v("shoulder.symptoms.stiffness") === true,
            clicking: v("shoulder.symptoms.clicking") === true,
            neckInvolved: v("shoulder.symptoms.neckInvolved") === true,
            handNumbness: v("shoulder.symptoms.handNumbness") === true,
            tenderSpot: mapTenderSpot(v("shoulder.symptoms.tenderSpot")),
            functionLimits: mapFunctionLimits(v("shoulder.function.limits")),
        },
        redFlags: {
            feverOrHotRedJoint: v("shoulder.redflags.feverOrHotRedJoint") === true,
            deformityAfterInjury: v("shoulder.redflags.deformityAfterInjury") === true,
            newNeuroSymptoms: v("shoulder.redflags.newNeuroSymptoms") === true,
            constantUnrelentingPain: v("shoulder.redflags.constantUnrelentingPain") === true,
            cancerHistoryOrWeightLoss: v("shoulder.redflags.cancerHistoryOrWeightLoss") === true,
            traumaHighEnergy: v("shoulder.redflags.traumaHighEnergy") === true,
            // TS expects YES means can elevate (and uses yn() to convert)
            canActiveElevateToShoulderHeight: v("shoulder.redflags.canActiveElevateToShoulderHeight") === true,
        },
    };
}
//# sourceMappingURL=shoulderAdapter%20-%20Copy.js.map