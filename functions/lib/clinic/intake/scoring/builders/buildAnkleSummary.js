"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildAnkleSummary = buildAnkleSummary;
/* ------------------------------- helpers -------------------------------- */
function answerToString(v) {
    if (v == null)
        return "";
    if (typeof v === "string")
        return v;
    if (typeof v === "number")
        return String(v);
    if (typeof v === "boolean")
        return v ? "yes" : "no";
    if (Array.isArray(v))
        return v.map(String).join(", ");
    try {
        return JSON.stringify(v);
    }
    catch {
        return String(v);
    }
}
function isTriggered(val) {
    if (val == null)
        return false;
    if (typeof val === "string")
        return val.trim().length > 0;
    if (typeof val === "number")
        return true; // sliders always meaningful
    if (typeof val === "boolean")
        return val === true;
    if (Array.isArray(val))
        return val.length > 0;
    return true;
}
function uniq(arr) {
    return Array.from(new Set(arr.filter((x) => typeof x === "string" && x.trim().length > 0)));
}
function isMultiAnswer(av) {
    return !!av && av.t === "multi" && Array.isArray(av.v);
}
/**
 * Sanitise multi-select values where "none" must be mutually exclusive.
 * This is for clinician-facing tables/triggeredAnswers so they don't show
 * contradictory combos like ["follow.none","follow.deformity"].
 *
 * NOTE: Scoring integrity is enforced in the adapter. This is display-only.
 */
function sanitizeAnswersForDisplay(answers) {
    const cloned = { ...answers };
    const cleanNoneMulti = (qid, noneOptionId) => {
        const av = cloned[qid];
        if (!isMultiAnswer(av))
            return;
        const arr = av.v.map(String);
        if (arr.length === 0)
            return;
        // If only "none" selected => treat as no positives
        if (arr.length === 1) {
            if (arr[0] === noneOptionId) {
                cloned[qid] = { ...av, v: [] };
            }
            return;
        }
        // If "none" + others => drop "none"
        if (arr.includes(noneOptionId)) {
            cloned[qid] = {
                ...av,
                v: arr.filter((x) => x !== noneOptionId),
            };
        }
    };
    cleanNoneMulti("ankle.redflags.followUps", "follow.none");
    cleanNoneMulti("ankle.function.loadAggravators", "load.none");
    return cloned;
}
/* ------------------------- question bucketing ---------------------------- */
function buildTables(answers) {
    var _a;
    const safety = [];
    const context = [];
    const symptoms = [];
    const func = [];
    const other = [];
    for (const qid of Object.keys(answers)) {
        const val = (_a = answers[qid]) === null || _a === void 0 ? void 0 : _a.v;
        const r = { questionId: qid, answer: answerToString(val) };
        if (qid.startsWith("ankle.redflags."))
            safety.push(r);
        else if (qid.startsWith("ankle.history."))
            context.push(r);
        else if (qid.startsWith("ankle.symptoms."))
            symptoms.push(r);
        else if (qid.startsWith("ankle.function."))
            func.push(r);
        else
            other.push(r);
    }
    const sortById = (a, b) => a.questionId.localeCompare(b.questionId);
    safety.sort(sortById);
    context.sort(sortById);
    symptoms.sort(sortById);
    func.sort(sortById);
    other.sort(sortById);
    return { safety, context, symptoms, function: func, other };
}
function buildTriggered(answers) {
    var _a;
    const out = [];
    for (const qid of Object.keys(answers)) {
        const val = (_a = answers[qid]) === null || _a === void 0 ? void 0 : _a.v;
        if (!isTriggered(val))
            continue;
        out.push({ questionId: qid, answer: answerToString(val) });
    }
    out.sort((a, b) => a.questionId.localeCompare(b.questionId));
    return out;
}
/* ------------------------------ builder ---------------------------------- */
function buildAnkleSummary(raw, answers) {
    const region = (raw === null || raw === void 0 ? void 0 : raw.region) || "Ankle";
    const triageLevel = ((raw === null || raw === void 0 ? void 0 : raw.triage) || "green");
    const triageReasons = Array.isArray(raw === null || raw === void 0 ? void 0 : raw.redFlagNotes) ? raw.redFlagNotes : [];
    const detailedTop = Array.isArray(raw === null || raw === void 0 ? void 0 : raw.detailedTop) ? raw.detailedTop : [];
    const top3 = detailedTop.slice(0, 3).map((d) => {
        var _a;
        return ({
            code: d.key,
            label: d.name,
            score: typeof d.score === "number" ? d.score : Number((_a = d.score) !== null && _a !== void 0 ? _a : 0),
            rationale: Array.isArray(d.rationale) ? d.rationale : [],
            objectiveTests: Array.isArray(d.objectiveTests) ? d.objectiveTests : [],
        });
    });
    const fromRawClinical = Array.isArray(raw === null || raw === void 0 ? void 0 : raw.clinicalToDo)
        ? raw.clinicalToDo
        : [];
    const fromTopTests = detailedTop.flatMap((d) => Array.isArray(d.objectiveTests) ? d.objectiveTests : []);
    const objectiveTests = uniq([...fromRawClinical, ...fromTopTests]);
    const displayAnswers = sanitizeAnswersForDisplay(answers);
    const tables = buildTables(displayAnswers);
    const triggeredAnswers = buildTriggered(displayAnswers);
    const narrative = triageLevel === "red"
        ? "Red-flag features were identified. Urgent clinical review is recommended."
        : triageLevel === "amber"
            ? "Some caution features were identified. Review triage notes and consider appropriate escalation."
            : "No major red-flag features identified from the provided answers. Review differentials and tests below.";
    return {
        region,
        triage: {
            level: triageLevel,
            reasons: triageReasons,
        },
        topDifferentials: top3,
        objectiveTests,
        narrative,
        tables,
        triggeredAnswers,
    };
}
//# sourceMappingURL=buildAnkleSummary.js.map