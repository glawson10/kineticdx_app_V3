"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildCervicalSummary = buildCervicalSummary;
function buildCervicalSummary(raw, answers) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p;
    return {
        region: "cervical",
        triage: {
            level: raw.triageLevel,
            reasons: (_a = raw.triageReasons) !== null && _a !== void 0 ? _a : [],
        },
        topDifferentials: ((_b = raw.differentials) !== null && _b !== void 0 ? _b : [])
            .sort((a, b) => b.score - a.score)
            .slice(0, 3)
            .map((d) => {
            var _a;
            return ({
                code: d.code,
                label: d.label,
                score: d.score,
                rationale: (_a = d.triggers) !== null && _a !== void 0 ? _a : [],
            });
        }),
        objectiveTests: (_c = raw.recommendedTests) !== null && _c !== void 0 ? _c : [],
        narrative: (_d = raw.summaryNarrative) !== null && _d !== void 0 ? _d : "Patient reports neck symptoms consistent with the above findings.",
        tables: {
            safety: (_f = (_e = raw.tables) === null || _e === void 0 ? void 0 : _e.safety) !== null && _f !== void 0 ? _f : [],
            context: (_h = (_g = raw.tables) === null || _g === void 0 ? void 0 : _g.context) !== null && _h !== void 0 ? _h : [],
            symptoms: (_k = (_j = raw.tables) === null || _j === void 0 ? void 0 : _j.symptoms) !== null && _k !== void 0 ? _k : [],
            function: (_m = (_l = raw.tables) === null || _l === void 0 ? void 0 : _l.function) !== null && _m !== void 0 ? _m : [],
            other: (_p = (_o = raw.tables) === null || _o === void 0 ? void 0 : _o.other) !== null && _p !== void 0 ? _p : [],
        },
    };
}
//# sourceMappingURL=buildCervicalSummary.js.map