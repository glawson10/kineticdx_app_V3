"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildShoulderSummary = buildShoulderSummary;
/**
 * Your shoulder scorer currently returns:
 * {
 *   region: "Shoulder",
 *   triage,
 *   redFlagNotes,
 *   topDifferentials: [{ name, score }],
 *   clinicalToDo,
 *   detailedTop: [{ name, score, rationale, objectiveTests }]
 * }
 *
 * We normalize that into the unified structure used in clinician UI.
 */
function buildShoulderSummary(raw, _answers) {
    var _a, _b, _c;
    const triage = ((_a = raw === null || raw === void 0 ? void 0 : raw.triage) !== null && _a !== void 0 ? _a : "green");
    const reasons = Array.isArray(raw === null || raw === void 0 ? void 0 : raw.redFlagNotes)
        ? raw.redFlagNotes
        : [];
    const detailedTop = Array.isArray(raw === null || raw === void 0 ? void 0 : raw.detailedTop) ? raw.detailedTop : [];
    const top3 = detailedTop.slice(0, 3).map((d) => {
        var _a, _b, _c;
        return ({
            code: (_a = d === null || d === void 0 ? void 0 : d.name) !== null && _a !== void 0 ? _a : "unknown",
            label: (_b = d === null || d === void 0 ? void 0 : d.name) !== null && _b !== void 0 ? _b : "Unknown",
            score: Number((_c = d === null || d === void 0 ? void 0 : d.score) !== null && _c !== void 0 ? _c : 0),
            rationale: Array.isArray(d === null || d === void 0 ? void 0 : d.rationale) ? d.rationale : [],
        });
    });
    const tests = detailedTop
        .flatMap((d) => (Array.isArray(d === null || d === void 0 ? void 0 : d.objectiveTests) ? d.objectiveTests : []))
        .filter((x) => typeof x === "string" && x.trim().length > 0);
    return {
        region: "shoulder",
        triage: { level: triage, reasons },
        topDifferentials: top3,
        objectiveTests: Array.from(new Set(tests)),
        narrative: (_c = (_b = raw === null || raw === void 0 ? void 0 : raw.clinicalToDo) === null || _b === void 0 ? void 0 : _b.primary) !== null && _c !== void 0 ? _c : "Patient reports shoulder symptoms consistent with the above findings.",
        // Shoulder scorer doesn’t currently output tables.
        // We keep empty groups for UI consistency.
        tables: {
            safety: [],
            context: [],
            symptoms: [],
            function: [],
            other: [],
        },
    };
}
//# sourceMappingURL=buildShoulderSummary.js.map