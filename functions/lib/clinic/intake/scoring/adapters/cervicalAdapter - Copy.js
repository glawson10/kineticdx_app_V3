"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildCervicalLegacyAnswers = buildCervicalLegacyAnswers;
function buildCervicalLegacyAnswers(answers) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q, _r;
    return {
        C_rf_majorTrauma: ((_a = answers["cervical.redflags.majorTrauma"]) === null || _a === void 0 ? void 0 : _a.v) === true,
        C_rf_progressiveNeurology: ((_b = answers["cervical.redflags.progressiveNeurology"]) === null || _b === void 0 ? void 0 : _b.v) === true,
        C_rf_armWeakness: ((_c = answers["cervical.redflags.armWeakness"]) === null || _c === void 0 ? void 0 : _c.v) === true,
        C_rf_balanceIssues: ((_d = answers["cervical.redflags.balanceOrWalkingIssues"]) === null || _d === void 0 ? void 0 : _d.v) === true,
        C_rf_bowelBladder: ((_e = answers["cervical.redflags.bowelBladderChange"]) === null || _e === void 0 ? void 0 : _e.v) === true,
        C_rf_systemic: (_g = (_f = answers["cervical.redflags.systemicSymptoms"]) === null || _f === void 0 ? void 0 : _f.v) !== null && _g !== void 0 ? _g : [],
        C_onset: (_h = answers["cervical.history.onset"]) === null || _h === void 0 ? void 0 : _h.v,
        C_timeSince: (_j = answers["cervical.history.timeSinceStart"]) === null || _j === void 0 ? void 0 : _j.v,
        C_armSymptoms: (_l = (_k = answers["cervical.symptoms.armSymptoms"]) === null || _k === void 0 ? void 0 : _k.v) !== null && _l !== void 0 ? _l : [],
        C_headache: ((_m = answers["cervical.symptoms.headache"]) === null || _m === void 0 ? void 0 : _m.v) === true,
        C_dizziness: ((_o = answers["cervical.symptoms.dizzinessOrVisual"]) === null || _o === void 0 ? void 0 : _o.v) === true,
        C_nightPain: ((_p = answers["cervical.symptoms.nightOrConstantPain"]) === null || _p === void 0 ? void 0 : _p.v) === true,
        C_functionImpact: (_r = (_q = answers["cervical.function.dayImpact"]) === null || _q === void 0 ? void 0 : _q.v) !== null && _r !== void 0 ? _r : 0,
    };
}
//# sourceMappingURL=cervicalAdapter%20-%20Copy.js.map