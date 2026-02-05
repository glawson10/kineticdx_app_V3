"use strict";
// functions/src/preassessmentRegion/cervical/processCervicalAssessment.ts
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildCervicalSummary = buildCervicalSummary;
exports.processCervicalAssessmentRaw = processCervicalAssessmentRaw;
const buildCervicalSummary_1 = require("../../../scoring/builders/buildCervicalSummary");
/**
 * Supported input shapes:
 *  - Record<string, any>
 *  - Array<{ key: string; value: any }>
 *  - Array<{ id: string; value: any }>
 *  - Array<{ questionId: string; answer: any }>
 *  - Array<string> in "key=value" form (best-effort)
 */
function normalizeToAnswerMap(input) {
    var _a, _b, _c, _d, _e;
    if (!input)
        return {};
    // Already a map
    if (typeof input === "object" && !Array.isArray(input)) {
        return { ...input };
    }
    // Array forms
    if (Array.isArray(input)) {
        const out = {};
        for (const item of input) {
            if (item == null)
                continue;
            // key/value objects
            if (typeof item === "object") {
                const key = String((_c = (_b = (_a = item.key) !== null && _a !== void 0 ? _a : item.id) !== null && _b !== void 0 ? _b : item.questionId) !== null && _c !== void 0 ? _c : "").trim();
                const value = (_e = (_d = item.value) !== null && _d !== void 0 ? _d : item.answer) !== null && _e !== void 0 ? _e : item.val;
                if (key)
                    out[key] = value;
                continue;
            }
            // string "key=value"
            if (typeof item === "string") {
                const s = item.trim();
                const eq = s.indexOf("=");
                if (eq > 0) {
                    const k = s.slice(0, eq).trim();
                    const v = s.slice(eq + 1).trim();
                    if (k)
                        out[k] = v;
                }
            }
        }
        return out;
    }
    return {};
}
function asBool(v) {
    if (v === true)
        return true;
    if (v === false)
        return false;
    if (typeof v === "number")
        return v !== 0;
    if (typeof v === "string") {
        const s = v.trim().toLowerCase();
        return s === "true" || s === "yes" || s === "y" || s === "1";
    }
    return false;
}
function asNum(v) {
    if (typeof v === "number" && Number.isFinite(v))
        return v;
    if (typeof v === "string") {
        const n = Number(v);
        if (Number.isFinite(n))
            return n;
    }
    return null;
}
function asStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
}
/**
 * Raw scoring pass.
 * This is intentionally conservative + generic because we don't know your exact key set.
 * You can progressively replace these heuristics with your real cervical engine.
 */
function computeRawCervical(answers) {
    var _a, _b, _c, _d, _e;
    const safety = [];
    const context = [];
    const symptoms = [];
    const functionTbl = [];
    const other = [];
    // --- Pull a few "best guess" common fields ---
    // Use multiple aliases so it works with mixed schemas.
    const trauma = asBool(answers.recentTrauma) ||
        asBool(answers.trauma) ||
        asBool(answers.majorTrauma);
    const fever = asBool(answers.fever) ||
        asBool(answers.unwell) ||
        asBool(answers.systemicSymptoms);
    const neuro = asBool(answers.neuroSymptoms) ||
        asBool(answers.neuroDeficit) ||
        asBool(answers.numbness) ||
        asBool(answers.weakness);
    const dizziness = asBool(answers.dizziness) ||
        asBool(answers.vertigo);
    const severeHeadache = asBool(answers.severeHeadache) ||
        asBool(answers.worstHeadache);
    const nightPain = asBool(answers.nightPain) ||
        asBool(answers.constantPain);
    const painNrs = (_b = (_a = asNum(answers.painNrs)) !== null && _a !== void 0 ? _a : asNum(answers.pain)) !== null && _b !== void 0 ? _b : asNum(answers.painScore);
    const durationDays = (_d = (_c = asNum(answers.durationDays)) !== null && _c !== void 0 ? _c : asNum(answers.symptomDurationDays)) !== null && _d !== void 0 ? _d : null;
    // --- Tables (minimal but useful) ---
    if (answers.painNrs != null || answers.pain != null || answers.painScore != null) {
        symptoms.push({ question: "Pain (0-10)", answer: String((_e = painNrs !== null && painNrs !== void 0 ? painNrs : answers.pain) !== null && _e !== void 0 ? _e : answers.painScore) });
    }
    if (answers.duration != null || answers.durationDays != null || answers.symptomDurationDays != null) {
        symptoms.push({ question: "Duration", answer: asStr(answers.duration || durationDays) });
    }
    // Track the safety Qs if present
    const safetyKeys = [
        ["recentTrauma", "Recent trauma"],
        ["fever", "Fever / systemic symptoms"],
        ["neuroSymptoms", "Neurological symptoms"],
        ["dizziness", "Dizziness / vertigo"],
        ["severeHeadache", "Severe headache"],
        ["nightPain", "Night/constant pain"],
    ];
    for (const [k, label] of safetyKeys) {
        if (k in answers)
            safety.push({ question: label, answer: asStr(answers[k]) });
    }
    // --- Triage ---
    const triageReasons = [];
    let triageLevel = "green";
    const redSignals = (trauma && asBool(answers.highImpactTrauma)) ||
        (severeHeadache && dizziness) ||
        (neuro && asBool(answers.progressiveNeuro)) ||
        asBool(answers.redFlag) ||
        asBool(answers.cadConcern) ||
        asBool(answers.cervicalMyelopathy);
    const amberSignals = trauma ||
        fever ||
        neuro ||
        dizziness ||
        nightPain ||
        (typeof painNrs === "number" && painNrs >= 8);
    if (redSignals) {
        triageLevel = "red";
        if (asBool(answers.redFlag))
            triageReasons.push("Red flag present");
        if (asBool(answers.cadConcern))
            triageReasons.push("Possible vascular presentation (CAD concern)");
        if (asBool(answers.cervicalMyelopathy))
            triageReasons.push("Possible myelopathy features");
        if (severeHeadache && dizziness)
            triageReasons.push("Severe headache with dizziness");
        if (neuro && asBool(answers.progressiveNeuro))
            triageReasons.push("Progressive neurological symptoms");
        if (trauma)
            triageReasons.push("Recent trauma");
    }
    else if (amberSignals) {
        triageLevel = "amber";
        if (trauma)
            triageReasons.push("Recent trauma");
        if (fever)
            triageReasons.push("Systemic symptoms");
        if (neuro)
            triageReasons.push("Neurological symptoms");
        if (dizziness)
            triageReasons.push("Dizziness/vertigo");
        if (nightPain)
            triageReasons.push("Night/constant pain");
        if (typeof painNrs === "number" && painNrs >= 8)
            triageReasons.push("High pain rating");
    }
    else {
        triageLevel = "green";
        triageReasons.push("No red flags detected from available answers");
    }
    // --- Differentials (generic heuristics; replace with your true engine later) ---
    const diffs = [];
    // Mechanical neck pain
    {
        let score = 0;
        const triggers = [];
        if (!fever && !trauma && !neuro) {
            score += 2;
            triggers.push("No systemic / neuro flags");
        }
        if (typeof painNrs === "number" && painNrs > 0) {
            score += 1;
            triggers.push("Pain reported");
        }
        if (durationDays != null && durationDays <= 42) {
            score += 1;
            triggers.push("Sub-acute duration");
        }
        diffs.push({ code: "MECH_NECK", label: "Mechanical neck pain", score, triggers });
    }
    // Cervical radiculopathy (very light signals)
    {
        let score = 0;
        const triggers = [];
        if (asBool(answers.armPain) || asBool(answers.radiation)) {
            score += 2;
            triggers.push("Arm pain/radiation");
        }
        if (asBool(answers.paraesthesia) || asBool(answers.numbness)) {
            score += 1;
            triggers.push("Paraesthesia/numbness");
        }
        if (asBool(answers.weakness)) {
            score += 1;
            triggers.push("Weakness");
        }
        diffs.push({ code: "RADIC", label: "Cervical radiculopathy features", score, triggers });
    }
    // Headache related to neck (cervicogenic-type)
    {
        let score = 0;
        const triggers = [];
        if (asBool(answers.headache) || severeHeadache) {
            score += 2;
            triggers.push("Headache reported");
        }
        if (asBool(answers.neckStiffness) || asBool(answers.stiffness)) {
            score += 1;
            triggers.push("Neck stiffness");
        }
        diffs.push({ code: "CGH", label: "Headache with cervical contribution", score, triggers });
    }
    // --- Recommended tests (keep short and generic) ---
    const recommendedTests = [];
    if (triageLevel === "red") {
        recommendedTests.push("Urgent medical review / escalation per clinic policy");
    }
    else {
        if (asBool(answers.neckRangeLimited) || asBool(answers.stiffness)) {
            recommendedTests.push("Cervical AROM screening");
        }
        if (asBool(answers.armPain) || neuro) {
            recommendedTests.push("Neuro screen (myotomes/dermatomes/reflexes)");
        }
        if (asBool(answers.headache) || dizziness) {
            recommendedTests.push("Headache/vestibular screening as indicated");
        }
    }
    // --- Narrative (simple) ---
    const narrative = triageLevel === "red"
        ? "Responses indicate potential high-risk features. Escalate for urgent medical review per protocol."
        : triageLevel === "amber"
            ? "Responses indicate some cautionary features. Proceed with appropriate screening and clinical reasoning."
            : "Presentation appears low-risk from available answers. Proceed with standard MSK assessment.";
    // --- Put a couple items into other/context if present ---
    if ("occupation" in answers)
        context.push({ question: "Occupation", answer: asStr(answers.occupation) });
    if ("sport" in answers)
        context.push({ question: "Sport", answer: asStr(answers.sport) });
    if ("goal" in answers)
        other.push({ question: "Goal", answer: asStr(answers.goal) });
    return {
        triageLevel,
        triageReasons,
        differentials: diffs,
        recommendedTests,
        summaryNarrative: narrative,
        tables: {
            safety,
            context,
            symptoms,
            function: functionTbl,
            other,
        },
    };
}
/**
 * ✅ Main export used by scoring engines.
 * Input is "legacy" answer structures; output is the unified CervicalSummary.
 */
function buildCervicalSummary(legacyAnswers) {
    const answers = normalizeToAnswerMap(legacyAnswers);
    const raw = computeRawCervical(answers);
    return (0, buildCervicalSummary_1.buildCervicalSummary)(raw, answers);
}
/**
 * Optional: if you want other callers to use the raw stage for debugging/testing.
 */
function processCervicalAssessmentRaw(legacyAnswers) {
    const answers = normalizeToAnswerMap(legacyAnswers);
    const raw = computeRawCervical(answers);
    return { raw, answers };
}
//# sourceMappingURL=buildCervicalSummary.js.map