"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildHipSummary = buildHipSummary;
/**
 * Convert raw hip scorer output into clinician-friendly summary.
 * This does not change scoring; it just shapes data for UI.
 */
function buildHipSummary(raw, answers) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q, _r, _s, _t, _u, _v;
    return {
        region: "hip",
        triage: {
            level: (_b = (_a = raw.triage) !== null && _a !== void 0 ? _a : raw.triageLevel) !== null && _b !== void 0 ? _b : "green",
            reasons: (_d = (_c = raw.notes) !== null && _c !== void 0 ? _c : raw.triageReasons) !== null && _d !== void 0 ? _d : [],
        },
        topDifferentials: ((_f = (_e = raw.ranked) !== null && _e !== void 0 ? _e : raw.differentials) !== null && _f !== void 0 ? _f : [])
            .sort((a, b) => { var _a, _b; return Number((_a = b.score) !== null && _a !== void 0 ? _a : 0) - Number((_b = a.score) !== null && _b !== void 0 ? _b : 0); })
            .slice(0, 3)
            .map((d) => {
            var _a, _b, _c, _d, _e, _f, _g;
            return ({
                code: (_b = (_a = d.key) !== null && _a !== void 0 ? _a : d.code) !== null && _b !== void 0 ? _b : "unknown",
                label: (_d = (_c = d.name) !== null && _c !== void 0 ? _c : d.label) !== null && _d !== void 0 ? _d : "Unknown",
                score: Number((_e = d.score) !== null && _e !== void 0 ? _e : 0),
                rationale: (_g = (_f = d.why) !== null && _f !== void 0 ? _f : d.triggers) !== null && _g !== void 0 ? _g : [],
            });
        }),
        objectiveTests: (_h = (_g = raw.recommendedTests) !== null && _g !== void 0 ? _g : raw.tests) !== null && _h !== void 0 ? _h : [],
        narrative: (_k = (_j = raw.summaryNarrative) !== null && _j !== void 0 ? _j : raw.summary) !== null && _k !== void 0 ? _k : "Patient reports hip symptoms consistent with the above findings.",
        tables: {
            safety: (_m = (_l = raw.tables) === null || _l === void 0 ? void 0 : _l.safety) !== null && _m !== void 0 ? _m : [],
            context: (_p = (_o = raw.tables) === null || _o === void 0 ? void 0 : _o.context) !== null && _p !== void 0 ? _p : [],
            symptoms: (_r = (_q = raw.tables) === null || _q === void 0 ? void 0 : _q.symptoms) !== null && _r !== void 0 ? _r : [],
            function: (_t = (_s = raw.tables) === null || _s === void 0 ? void 0 : _s.function) !== null && _t !== void 0 ? _t : [],
            other: (_v = (_u = raw.tables) === null || _u === void 0 ? void 0 : _u.other) !== null && _v !== void 0 ? _v : [],
        },
    };
}
//# sourceMappingURL=buildHipSummary.js.map