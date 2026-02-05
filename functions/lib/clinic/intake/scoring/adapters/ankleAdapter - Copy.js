"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildAnkleLegacyAnswerArray = buildAnkleLegacyAnswerArray;
function buildAnkleLegacyAnswerArray(answers) {
    const v = (qid) => { var _a; return (_a = answers[qid]) === null || _a === void 0 ? void 0 : _a.v; };
    const yesNo = (b) => (b === true ? "yes" : "no");
    const single = (id, value) => ({
        id,
        kind: "single",
        value: value == null ? "" : String(value),
    });
    const multi = (id, arr) => ({
        id,
        kind: "multi",
        values: Array.isArray(arr) ? arr.map(String) : [],
    });
    const slider = (id, value) => ({
        id,
        kind: "slider",
        value: typeof value === "number" ? value : Number(value !== null && value !== void 0 ? value : 0),
    });
    // helpers to strip prefixes used in Flutter option ids
    const stripPrefix = (s, prefix) => {
        const x = String(s !== null && s !== void 0 ? s : "");
        return x.startsWith(prefix) ? x.substring(prefix.length) : x;
    };
    const stripMany = (arr, prefix) => {
        const xs = Array.isArray(arr) ? arr : [];
        return xs
            .filter((x) => x != null)
            .map((x) => stripPrefix(x, prefix));
    };
    // ---- legacy mapping ----
    const mech = stripPrefix(v("ankle.history.mechanism"), "mechanism.");
    const timeSince = stripPrefix(v("ankle.history.timeSinceStart"), "time.");
    const onsetStyle = stripPrefix(v("ankle.history.onsetStyle"), "onset.");
    const painSite = stripMany(v("ankle.symptoms.painSite"), "painSite.")
        // keep ONLY values TS expects
        .filter((x) => ["lateralATFL", "syndesmosisHigh", "achilles", "plantar", "midfoot"].includes(x));
    const loadAggs = stripMany(v("ankle.function.loadAggravators"), "load.")
        .filter((x) => ["walkFlat", "stairsHillsTiptoe", "cuttingLanding", "firstStepsWorse", "throbsAtRest"].includes(x));
    const followUps = stripMany(v("ankle.redflags.followUps"), "follow.")
        .filter((x) => ["fourStepsImmediate", "popHeard", "deformity", "numbPins"].includes(x));
    const instability = stripPrefix(v("ankle.function.instability"), "instability.");
    const walk4 = stripPrefix(v("ankle.redflags.walk4StepsNow"), "walk4.");
    return [
        // Safety
        single("A_rf_fromFallTwistLanding", yesNo(v("ankle.redflags.fromFallTwistLanding"))),
        multi("A_rf_followUps", followUps),
        single("A_rf_walk4Now", walk4),
        single("A_rf_hotRedFever", yesNo(v("ankle.redflags.hotRedFeverish"))),
        single("A_rf_calfHotTight", yesNo(v("ankle.redflags.calfHotTight"))),
        single("A_rf_tiptoes", yesNo(v("ankle.redflags.tiptoes"))),
        single("A_rf_highSwelling", yesNo(v("ankle.redflags.highSwelling"))),
        // Differential drivers
        single("A_mech", mech),
        single("A_timeSince", timeSince),
        single("A_onsetStyle", onsetStyle),
        multi("A_painSite", painSite),
        multi("A_loadAggs", loadAggs),
        single("A_instability", instability),
        // Impact (slider)
        slider("A_impactScore", v("ankle.function.dayImpact")),
    ];
}
//# sourceMappingURL=ankleAdapter%20-%20Copy.js.map