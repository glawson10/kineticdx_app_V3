"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildWristSummary = buildWristSummary;
function buildWristSummary(raw, _answers) {
    var _a;
    const triage = ((_a = raw === null || raw === void 0 ? void 0 : raw.triage) !== null && _a !== void 0 ? _a : "green");
    const reasons = Array.isArray(raw === null || raw === void 0 ? void 0 : raw.redFlagNotes) ? raw.redFlagNotes : [];
    const top = Array.isArray(raw === null || raw === void 0 ? void 0 : raw.topDifferentials) ? raw.topDifferentials : [];
    const top3 = top.slice(0, 3).map((d) => {
        var _a, _b, _c, _d;
        return ({
            code: (_b = (_a = d === null || d === void 0 ? void 0 : d.key) !== null && _a !== void 0 ? _a : d === null || d === void 0 ? void 0 : d.name) !== null && _b !== void 0 ? _b : "unknown",
            label: (_c = d === null || d === void 0 ? void 0 : d.name) !== null && _c !== void 0 ? _c : "Unknown",
            score: Number((_d = d === null || d === void 0 ? void 0 : d.score) !== null && _d !== void 0 ? _d : 0),
            rationale: Array.isArray(d === null || d === void 0 ? void 0 : d.rationale) ? d.rationale : [],
        });
    });
    const tests = top
        .flatMap((d) => (Array.isArray(d === null || d === void 0 ? void 0 : d.objectiveTests) ? d.objectiveTests : []))
        .filter((x) => typeof x === "string" && x.trim().length > 0);
    return {
        region: "wrist",
        triage: { level: triage, reasons },
        topDifferentials: top3,
        objectiveTests: Array.from(new Set(tests)),
        narrative: "Wrist presentation scored using region-specific rules. Review top differentials, triage, and suggested objective tests.",
        tables: { safety: [], context: [], symptoms: [], function: [], other: [] },
    };
}
//# sourceMappingURL=buildWristSummary.js.map