"use strict";
// functions/src/clinic/intake/scoring/adapters/thoracicAdapter.ts
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildThoracicLegacyAnswerArray = buildThoracicLegacyAnswerArray;
function buildThoracicLegacyAnswerArray(answers) {
    var _a;
    const v = (qid) => { var _a; return (_a = answers[qid]) === null || _a === void 0 ? void 0 : _a.v; };
    const asSingle = (id, value) => ({
        id,
        kind: "single",
        value: value == null ? "" : String(value),
    });
    const asMulti = (id, arr) => {
        const xs = Array.isArray(arr) ? arr : [];
        return { id, kind: "multi", values: xs.map(String) };
    };
    // Multi helpers: if user picked "none", TS filters it out anyway
    // (but we still pass it through cleanly).
    const normalizeNoneMulti = (arr) => {
        const xs = Array.isArray(arr) ? arr : [];
        // Keep as-is; TS filters "none".
        return xs;
    };
    return [
        // Q1 – trauma (single)
        asSingle("Q1_trauma", v("thoracic.redflags.trauma")),
        // Q2 – red cluster (multi)
        asMulti("Q2_redcluster", normalizeNoneMulti(v("thoracic.redflags.redCluster"))),
        // Q3 – neuro (multi)
        asMulti("Q3_neuro", normalizeNoneMulti(v("thoracic.redflags.neuro"))),
        // Q4 – rest pattern (single)
        asSingle("Q4_rest", v("thoracic.symptoms.restPattern")),
        // Q5 – onset (single)
        asSingle("Q5_onset", v("thoracic.history.onset")),
        // Q6 – location (single)
        asSingle("Q6_location", v("thoracic.symptoms.location")),
        // Q7 – worse (multi)  (strip the UI-only "none" if present)
        asMulti("Q7_worse", (Array.isArray(v("thoracic.symptoms.worse")) ? v("thoracic.symptoms.worse") : [])
            .filter((x) => x !== "none")),
        // Q8 – better (multi)
        asMulti("Q8_better", (Array.isArray(v("thoracic.symptoms.better")) ? v("thoracic.symptoms.better") : [])
            .filter((x) => x !== "none")),
        // Q9 – irritability (single)
        asSingle("Q9_irritability", v("thoracic.symptoms.irritability")),
        // Q10 – breath provocation (single)
        asSingle("Q10_breathprov", v("thoracic.symptoms.breathProvocation")),
        // Q11 – sleep (single)
        asSingle("Q11_sleep", v("thoracic.symptoms.sleep")),
        // Q12 – band (single)
        asSingle("Q12_band", v("thoracic.symptoms.band")),
        // Q13 – pain now (single numeric stored as string)
        asSingle("Q13_pain_now", (_a = v("thoracic.pain.now")) !== null && _a !== void 0 ? _a : 0),
    ];
}
//# sourceMappingURL=thoracicAdapter%20-%20Copy.js.map