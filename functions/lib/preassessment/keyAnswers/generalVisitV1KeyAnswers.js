"use strict";
// functions/src/preassessment/keyAnswers/generalVisitV1KeyAnswers.ts
//
// Server-side keyAnswers extraction for generalVisit.v1
// Patient-reported only, whitelisted. :contentReference[oaicite:5]{index=5}
Object.defineProperty(exports, "__esModule", { value: true });
exports.extractGeneralVisitV1KeyAnswers = extractGeneralVisitV1KeyAnswers;
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
}
function readText(answers, qid) {
    const a = answers[qid];
    if (a && typeof a === "object" && a.t === "text") {
        const v = safeStr(a.v);
        return v.length ? v : null;
    }
    return null;
}
function readSingle(answers, qid) {
    const a = answers[qid];
    if (a && typeof a === "object" && a.t === "single") {
        const v = safeStr(a.v);
        return v.length ? v : null;
    }
    return null;
}
function readMulti(answers, qid) {
    const a = answers[qid];
    if (a && typeof a === "object" && a.t === "multi" && Array.isArray(a.v)) {
        const vals = a.v.map((x) => safeStr(x)).filter(Boolean);
        return vals.length ? vals : null;
    }
    return null;
}
// Label maps (must match your UI maps; safe to compute server-side for previews)
const concernClarityLabels = {
    "concern.single": "One main concern",
    "concern.multiple": "Multiple concerns",
    "concern.unsure": "Not sure",
};
const bodyAreaLabels = {
    "area.neck": "Neck",
    "area.upperBack": "Upper back",
    "area.lowerBack": "Lower back",
    "area.shoulder": "Shoulder",
    "area.elbow": "Elbow",
    "area.wristHand": "Wrist/Hand",
    "area.hip": "Hip",
    "area.knee": "Knee",
    "area.ankleFoot": "Ankle/Foot",
    "area.multiple": "Multiple areas",
    "area.general": "General / whole body",
};
const durationLabels = {
    "duration.days": "Days",
    "duration.weeks": "Weeks",
    "duration.months": "Months",
    "duration.years": "Years",
    "duration.unsure": "Not sure",
};
const impactLabels = {
    "impact.work": "Work",
    "impact.sport": "Sport / exercise",
    "impact.sleep": "Sleep",
    "impact.dailyActivities": "Daily activities",
    "impact.generalMovement": "General movement",
    "impact.unclear": "Not sure",
};
function labelSingle(id, map) {
    var _a;
    if (!id)
        return "—";
    return (_a = map[id]) !== null && _a !== void 0 ? _a : id;
}
function labelsMulti(ids, map) {
    var _a;
    if (!ids)
        return [];
    const out = [];
    const seen = new Set();
    for (const raw of ids) {
        const id = safeStr(raw);
        if (!id || seen.has(id))
            continue;
        seen.add(id);
        out.push((_a = map[id]) !== null && _a !== void 0 ? _a : id);
    }
    return out;
}
function joinOrDash(items) {
    return items.length ? items.join(", ") : "—";
}
function extractGeneralVisitV1KeyAnswers(answers) {
    var _a, _b, _c, _d;
    // Whitelist (must match the contract you defined)
    const qReason = "generalVisit.goals.reasonForVisit";
    const qClarity = "generalVisit.meta.concernClarity";
    const qAreas = "generalVisit.history.bodyAreas";
    const qImpact = "generalVisit.function.primaryImpact";
    const qDuration = "generalVisit.history.duration";
    const qIntent = "generalVisit.goals.visitIntent";
    const keyAnswers = {
        [qReason]: readText(answers, qReason),
        [qClarity]: readSingle(answers, qClarity),
        [qAreas]: readMulti(answers, qAreas),
        [qImpact]: readSingle(answers, qImpact),
        [qDuration]: readSingle(answers, qDuration),
        [qIntent]: readMulti(answers, qIntent),
    };
    // Remove nulls for compact storage
    for (const k of Object.keys(keyAnswers)) {
        if (keyAnswers[k] == null)
            delete keyAnswers[k];
    }
    // Tiny preview labels for clinician list rows/cards (optional but very helpful)
    const clarityLabel = labelSingle((_a = keyAnswers[qClarity]) !== null && _a !== void 0 ? _a : null, concernClarityLabels);
    const areasLabel = joinOrDash(labelsMulti((_b = keyAnswers[qAreas]) !== null && _b !== void 0 ? _b : null, bodyAreaLabels));
    const durationLabel = labelSingle((_c = keyAnswers[qDuration]) !== null && _c !== void 0 ? _c : null, durationLabels);
    const impactLabel = labelSingle((_d = keyAnswers[qImpact]) !== null && _d !== void 0 ? _d : null, impactLabels);
    const summaryPreview = {
        concernClarityLabel: clarityLabel,
        areasLabel,
        durationLabel,
        impactLabel,
    };
    return {
        keyAnswers,
        keyAnswersVersion: "generalVisit.v1",
        summaryPreview,
    };
}
//# sourceMappingURL=generalVisitV1KeyAnswers.js.map