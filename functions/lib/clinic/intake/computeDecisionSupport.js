"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.computeDecisionSupport = void 0;
// functions/src/clinic/intake/computeDecisionSupport.ts
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const authz_1 = require("../authz");
const flowRegistry_1 = require("./flowRegistry");
// Engines...
const ankleAdapter_1 = require("./scoring/adapters/ankleAdapter");
const buildAnkleSummary_1 = require("./scoring/builders/buildAnkleSummary");
const processAnkleAssessment_1 = require("../../preassessmentRegion/ankle/processAnkleAssessment");
const cervicalAdapter_1 = require("./scoring/adapters/cervicalAdapter");
const buildCervicalSummary_1 = require("./scoring/builders/buildCervicalSummary");
const processCervicalAssessment_1 = require("../../preassessmentRegion/cervical/processCervicalAssessment");
const elbowAdapter_1 = require("./scoring/adapters/elbowAdapter");
const buildElbowSummary_1 = require("./scoring/builders/buildElbowSummary");
const processElbowAssessment_1 = require("../../preassessmentRegion/elbow/processElbowAssessment");
const hipAdapter_1 = require("./scoring/adapters/hipAdapter");
const buildHipSummary_1 = require("./scoring/builders/buildHipSummary");
const processHipAssessment_1 = require("../../preassessmentRegion/hip/processHipAssessment");
const kneeAdapter_1 = require("./scoring/adapters/kneeAdapter");
const buildKneeSummary_1 = require("./scoring/builders/buildKneeSummary");
const processKneeAssessment_1 = require("../../preassessmentRegion/knee/processKneeAssessment");
const lumbarAdapter_1 = require("./scoring/adapters/lumbarAdapter");
const buildLumbarSummary_1 = require("./scoring/builders/buildLumbarSummary");
const processLumbarAssessment_1 = require("../../preassessmentRegion/lumbar/processLumbarAssessment");
const shoulderAdapter_1 = require("./scoring/adapters/shoulderAdapter");
const buildShoulderSummary_1 = require("./scoring/builders/buildShoulderSummary");
const processShoulderAssessment_1 = require("../../preassessmentRegion/shoulder/processShoulderAssessment");
const thoracicAdapter_1 = require("./scoring/adapters/thoracicAdapter");
const buildThoracicSummary_1 = require("./scoring/builders/buildThoracicSummary");
const processThoracicAssessment_1 = require("../../preassessmentRegion/thoracic/processThoracicAssessment");
const wristAdapter_1 = require("./scoring/adapters/wristAdapter");
const buildWristSummary_1 = require("./scoring/builders/buildWristSummary");
const processWristAssessment_1 = require("../../preassessmentRegion/wrist/processWristAssessment");
function safeStr(v) {
    return v == null ? "" : String(v);
}
function safeNum(v) {
    if (typeof v === "number" && !Number.isNaN(v))
        return v;
    if (typeof v === "string") {
        const n = Number(v);
        if (!Number.isNaN(n))
            return n;
    }
    return 0;
}
function clamp01(x) {
    if (!Number.isFinite(x))
        return 0;
    return Math.max(0, Math.min(1, x));
}
function uniqStrings(items) {
    const out = [];
    const seen = new Set();
    for (const s of items) {
        const v = safeStr(s).trim();
        if (!v)
            continue;
        if (seen.has(v))
            continue;
        seen.add(v);
        out.push(v);
    }
    return out;
}
function normalizeRelativeWeights(items) {
    const positives = items.map((it) => (it.rawScore > 0 ? it.rawScore : 0));
    const sum = positives.reduce((a, b) => a + b, 0);
    if (sum <= 0) {
        const n = items.length;
        if (n === 0)
            return [];
        return items.map(() => 1 / n);
    }
    return positives.map((s) => clamp01(s / sum));
}
function mapSummaryToDecisionSupport(summary) {
    const summaryKeys = summary && typeof summary === "object" ? Object.keys(summary) : [];
    const top = Array.isArray(summary === null || summary === void 0 ? void 0 : summary.topDifferentials)
        ? summary.topDifferentials
        : [];
    const topDifferentialsCount = top.length;
    const testsFromSummary = Array.isArray(summary === null || summary === void 0 ? void 0 : summary.objectiveTests)
        ? summary.objectiveTests.map((x) => safeStr(x))
        : [];
    const testsFromDx = Array.isArray(top)
        ? top
            .flatMap((dx) => Array.isArray(dx === null || dx === void 0 ? void 0 : dx.objectiveTests) ? dx.objectiveTests : [])
            .map((x) => safeStr(x))
        : [];
    const allTests = uniqStrings([...testsFromSummary, ...testsFromDx]);
    const objectiveTestsCount = allTests.length;
    const prelim = top.map((dx) => {
        var _a, _b, _c, _d, _e, _f;
        const rawScore = safeNum((_b = (_a = dx === null || dx === void 0 ? void 0 : dx.score) !== null && _a !== void 0 ? _a : dx === null || dx === void 0 ? void 0 : dx.confidence) !== null && _b !== void 0 ? _b : 0);
        return {
            code: safeStr((_d = (_c = dx === null || dx === void 0 ? void 0 : dx.code) !== null && _c !== void 0 ? _c : dx === null || dx === void 0 ? void 0 : dx.id) !== null && _d !== void 0 ? _d : ""),
            label: safeStr((_f = (_e = dx === null || dx === void 0 ? void 0 : dx.label) !== null && _e !== void 0 ? _e : dx === null || dx === void 0 ? void 0 : dx.name) !== null && _f !== void 0 ? _f : ""),
            rawScore,
            rationale: Array.isArray(dx === null || dx === void 0 ? void 0 : dx.rationale)
                ? dx.rationale.map((r) => safeStr(r)).filter(Boolean)
                : [],
        };
    });
    const weights = normalizeRelativeWeights(prelim);
    const diagnosticHypotheses = prelim.map((h, i) => {
        var _a;
        return ({
            code: h.code,
            label: h.label,
            rawScore: h.rawScore,
            confidence: clamp01((_a = weights[i]) !== null && _a !== void 0 ? _a : 0),
            rationale: h.rationale,
        });
    });
    const recommendedTests = allTests.map((t) => ({
        category: t,
        reason: "",
    }));
    return {
        diagnosticHypotheses,
        recommendedTests,
        summaryKeys,
        topDifferentialsCount,
        objectiveTestsCount,
    };
}
/**
 * Ankle result helper:
 * - await the async ankle engine
 * - Returns raw summary object (or extracts from wrapped response)
 */
async function computeAnkleResult(answers) {
    var _a;
    const legacyAnswers = (0, ankleAdapter_1.buildAnkleLegacyAnswers)(answers);
    const result = await (0, processAnkleAssessment_1.processAnkleAssessmentCore)(legacyAnswers);
    // If wrapped (has clinicianSummary), extract it; otherwise use result directly
    return (_a = result === null || result === void 0 ? void 0 : result.clinicianSummary) !== null && _a !== void 0 ? _a : result;
}
exports.computeDecisionSupport = (0, https_1.onCall)({ region: "europe-west3" }, async (req) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q, _r, _s, _t, _u, _v;
    const db = (0, firestore_1.getFirestore)();
    const clinicId = safeStr((_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId).trim();
    const intakeSessionId = safeStr((_b = req.data) === null || _b === void 0 ? void 0 : _b.intakeSessionId).trim();
    try {
        if (!req.auth) {
            throw new https_1.HttpsError("unauthenticated", "Sign in required.");
        }
        if (!clinicId || !intakeSessionId) {
            throw new https_1.HttpsError("invalid-argument", "clinicId and intakeSessionId are required", { clinicId, intakeSessionId });
        }
        // ✅ clinical read required
        await (0, authz_1.requireActiveMemberWithPerm)(db, clinicId, req.auth.uid, "clinical.read");
        const sessionRef = db
            .collection("clinics")
            .doc(clinicId)
            .collection("intakeSessions")
            .doc(intakeSessionId);
        const snap = await sessionRef.get();
        if (!snap.exists) {
            throw new https_1.HttpsError("not-found", "Intake session not found", {
                clinicId,
                intakeSessionId,
            });
        }
        const intake = snap.data();
        const flow = intake.flow;
        const answers = intake.answers;
        if (!flow || !answers) {
            throw new https_1.HttpsError("failed-precondition", "Invalid intake session data", {
                hasFlow: !!flow,
                hasAnswers: !!answers,
            });
        }
        const flowId = safeStr(flow.flowId);
        const snapshotClinicalProfileId = safeStr(intake.clinicalProfileId);
        const snapshotSupportsDifferential = intake.supportsDifferentialHypothesis === true;
        const legacy = (0, flowRegistry_1.legacyFlowIdToRegistry)(flowId, (_c = intake.flowVersion) !== null && _c !== void 0 ? _c : flow.flowVersion);
        const profile = snapshotClinicalProfileId
            ? (0, flowRegistry_1.getClinicalProfile)(snapshotClinicalProfileId)
            : legacy
                ? (0, flowRegistry_1.getClinicalProfile)(legacy.clinicalProfileId)
                : null;
        const supportsDifferentialHypothesis = profile != null
            ? profile.supportsDifferentialHypothesis
            : (_d = (snapshotSupportsDifferential || (legacy === null || legacy === void 0 ? void 0 : legacy.supportsDifferentialHypothesis))) !== null && _d !== void 0 ? _d : true;
        const summaryEngine = safeStr(intake.summaryEngine) ||
            (legacy === null || legacy === void 0 ? void 0 : legacy.summaryEngine) ||
            (profile === null || profile === void 0 ? void 0 : profile.summaryEngine) ||
            flowId;
        let summary;
        let engineDispatch = summaryEngine;
        switch (summaryEngine) {
            case "ankle": {
                const raw = await computeAnkleResult(answers);
                summary = (0, buildAnkleSummary_1.buildAnkleSummary)(raw, answers);
                engineDispatch = "ankle";
                break;
            }
            case "cervical": {
                const legacyAnswers = (0, cervicalAdapter_1.buildCervicalLegacyAnswers)(answers);
                const rawResult = await (0, processCervicalAssessment_1.processCervicalAssessmentCore)(legacyAnswers);
                // Extract raw summary if wrapped
                const raw = (_e = rawResult === null || rawResult === void 0 ? void 0 : rawResult.clinicianSummary) !== null && _e !== void 0 ? _e : rawResult;
                summary = (0, buildCervicalSummary_1.buildCervicalSummary)(raw, answers);
                engineDispatch = "cervical";
                break;
            }
            case "elbow": {
                const legacyAnswers = (0, elbowAdapter_1.buildElbowLegacyAnswers)(answers);
                const rawResult = await (0, processElbowAssessment_1.processElbowAssessmentCore)(legacyAnswers);
                // Extract raw summary if wrapped
                const raw = (_f = rawResult === null || rawResult === void 0 ? void 0 : rawResult.clinicianSummary) !== null && _f !== void 0 ? _f : rawResult;
                summary = (0, buildElbowSummary_1.buildElbowSummary)(raw, answers);
                engineDispatch = "elbow";
                break;
            }
            case "hip": {
                const legacyAnswers = (0, hipAdapter_1.buildHipLegacyAnswers)(answers);
                const rawResult = await (0, processHipAssessment_1.processHipAssessmentCore)(legacyAnswers);
                // Extract raw summary if wrapped
                const raw = (_g = rawResult === null || rawResult === void 0 ? void 0 : rawResult.clinicianSummary) !== null && _g !== void 0 ? _g : rawResult;
                summary = (0, buildHipSummary_1.buildHipSummary)(raw, answers);
                engineDispatch = "hip";
                break;
            }
            case "knee": {
                const legacyAnswers = (0, kneeAdapter_1.buildKneeLegacyAnswers)(answers);
                const rawResult = await (0, processKneeAssessment_1.processKneeAssessmentCore)(legacyAnswers);
                // Extract raw summary if wrapped
                const raw = (_h = rawResult === null || rawResult === void 0 ? void 0 : rawResult.clinicianSummary) !== null && _h !== void 0 ? _h : rawResult;
                summary = (0, buildKneeSummary_1.buildKneeSummary)(raw, answers);
                engineDispatch = "knee";
                break;
            }
            case "lumbar": {
                const answerMap = (0, lumbarAdapter_1.buildLumbarAnswerMap)(answers);
                const rawResult = (0, processLumbarAssessment_1.processLumbarAssessmentCore)(answerMap);
                summary = (0, buildLumbarSummary_1.buildLumbarSummary)(rawResult, answers);
                engineDispatch = "lumbar";
                break;
            }
            case "shoulder": {
                const rawForScorer = (0, shoulderAdapter_1.buildShoulderRawForScorer)(answers);
                const rawResult = await (0, processShoulderAssessment_1.processShoulderAssessmentCore)(rawForScorer);
                // Extract raw summary if wrapped
                const raw = (_j = rawResult === null || rawResult === void 0 ? void 0 : rawResult.clinicianSummary) !== null && _j !== void 0 ? _j : rawResult;
                summary = (0, buildShoulderSummary_1.buildShoulderSummary)(raw, answers);
                engineDispatch = "shoulder";
                break;
            }
            case "thoracic": {
                const legacyAnswers = (0, thoracicAdapter_1.buildThoracicLegacyAnswers)(answers);
                const rawResult = await (0, processThoracicAssessment_1.processThoracicAssessmentCore)(legacyAnswers);
                // Thoracic returns { ok: true, summary } shape
                const raw = (_k = rawResult === null || rawResult === void 0 ? void 0 : rawResult.summary) !== null && _k !== void 0 ? _k : rawResult;
                summary = (0, buildThoracicSummary_1.buildThoracicSummary)(raw, answers);
                engineDispatch = "thoracic";
                break;
            }
            case "wrist": {
                const legacyAnswers = (0, wristAdapter_1.buildWristLegacyAnswers)(answers);
                const rawResult = await (0, processWristAssessment_1.processWristAssessmentCore)(legacyAnswers);
                // Extract raw summary if wrapped
                const raw = (_l = rawResult === null || rawResult === void 0 ? void 0 : rawResult.clinicianSummary) !== null && _l !== void 0 ? _l : rawResult;
                summary = (0, buildWristSummary_1.buildWristSummary)(raw, answers);
                engineDispatch = "wrist";
                break;
            }
            case "generalVisit": {
                const reason = (_s = (_q = (_p = (_o = (_m = answers === null || answers === void 0 ? void 0 : answers.generalVisit) === null || _m === void 0 ? void 0 : _m.goals) === null || _o === void 0 ? void 0 : _o.reasonForVisit) === null || _p === void 0 ? void 0 : _p.v) !== null && _q !== void 0 ? _q : (_r = answers === null || answers === void 0 ? void 0 : answers["generalVisit.goals.reasonForVisit"]) === null || _r === void 0 ? void 0 : _r.v) !== null && _s !== void 0 ? _s : "";
                const narrative = typeof reason === "string" && reason.trim()
                    ? `Reason for visit: ${reason.trim()}`
                    : "General visit questionnaire completed.";
                summary = {
                    narrative,
                    triage: { status: "green", reasons: [] },
                    topDifferentials: [],
                    objectiveTests: [],
                };
                engineDispatch = "generalVisit";
                break;
            }
            default:
                throw new https_1.HttpsError("invalid-argument", `Unsupported summaryEngine: ${summaryEngine}`, { flowId, summaryEngine });
        }
        const mapped = mapSummaryToDecisionSupport(summary);
        const diagnosticHypotheses = supportsDifferentialHypothesis
            ? mapped.diagnosticHypotheses
            : [];
        const recommendedTests = supportsDifferentialHypothesis
            ? mapped.recommendedTests
            : [];
        const doc = {
            status: "ready",
            engine: `${summaryEngine}_engine`,
            engineDispatch,
            region: flowId,
            rulesetVersion: "layerB_v1",
            generatedAt: firestore_1.FieldValue.serverTimestamp(),
            computedFromAnswerCount: Object.keys(answers !== null && answers !== void 0 ? answers : {}).length,
            summaryKeys: mapped.summaryKeys,
            topDifferentialsCount: supportsDifferentialHypothesis ? mapped.topDifferentialsCount : 0,
            objectiveTestsCount: recommendedTests.length,
            diagnosticHypotheses,
            recommendedTests,
        };
        const dsRef = db
            .collection("clinics")
            .doc(clinicId)
            .collection("decisionSupport")
            .doc(intakeSessionId);
        await dsRef.set(doc, { merge: true });
        return {
            ok: true,
            status: "ready",
            flowId,
            summaryEngine,
            engineDispatch,
            supportsDifferentialHypothesis,
            hypothesesCount: doc.diagnosticHypotheses.length,
            testsCount: doc.recommendedTests.length,
        };
    }
    catch (e) {
        // Best-effort error doc
        try {
            if (clinicId && intakeSessionId) {
                await db
                    .collection("clinics")
                    .doc(clinicId)
                    .collection("decisionSupport")
                    .doc(intakeSessionId)
                    .set({
                    status: "error",
                    error: safeStr((_t = e === null || e === void 0 ? void 0 : e.message) !== null && _t !== void 0 ? _t : "Decision support failed"),
                    generatedAt: firestore_1.FieldValue.serverTimestamp(),
                }, { merge: true });
            }
        }
        catch {
            // ignore
        }
        if (e instanceof https_1.HttpsError)
            throw e;
        throw new https_1.HttpsError("internal", safeStr((_u = e === null || e === void 0 ? void 0 : e.message) !== null && _u !== void 0 ? _u : "Decision support failed"), {
            name: e === null || e === void 0 ? void 0 : e.name,
            stack: safeStr((_v = e === null || e === void 0 ? void 0 : e.stack) !== null && _v !== void 0 ? _v : "").split("\n").slice(0, 12).join("\n"),
        });
    }
});
//# sourceMappingURL=computeDecisionSupport.js.map