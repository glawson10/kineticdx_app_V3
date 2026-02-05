"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.computeDecisionSupport = void 0;
// functions/src/clinic/intake/computeDecisionSupport.ts
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const authz_1 = require("../authz");
const schemaVersions_1 = require("../../schema/schemaVersions");
const paths_1 = require("../paths");
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
 * - normalize triageStatus -> triage for buildAnkleSummary()
 */
async function computeAnkleResult(answers) {
    const legacyAnswers = (0, ankleAdapter_1.buildAnkleLegacyAnswers)(answers);
    return await (0, processAnkleAssessment_1.processAnkleAssessmentCore)(legacyAnswers);
}
function normalizeAnkleForSummary(raw) {
    var _a;
    return {
        ...raw,
        triage: (_a = raw === null || raw === void 0 ? void 0 : raw.triage) !== null && _a !== void 0 ? _a : raw === null || raw === void 0 ? void 0 : raw.triageStatus,
    };
}
async function ensureAssessmentIdForIntake(params) {
    var _a, _b, _c;
    const { clinicId, intakeSessionId, flowId, answers, intake, uid } = params;
    const existing = intake === null || intake === void 0 ? void 0 : intake.assessmentId;
    const current = typeof existing === "string" ? existing.trim() : "";
    if (current)
        return current;
    const db = (0, firestore_1.getFirestore)();
    const id = db.collection("_").doc().id;
    const ref = (0, paths_1.assessmentRef)(db, clinicId, id);
    const now = firestore_1.FieldValue.serverTimestamp();
    const doc = {
        schemaVersion: (0, schemaVersions_1.schemaVersion)("assessment"),
        clinicId,
        packId: "standard_msk_v1",
        // Optional links if present on intake
        patientId: (_a = intake === null || intake === void 0 ? void 0 : intake.patientId) !== null && _a !== void 0 ? _a : null,
        episodeId: (_b = intake === null || intake === void 0 ? void 0 : intake.episodeId) !== null && _b !== void 0 ? _b : null,
        appointmentId: (_c = intake === null || intake === void 0 ? void 0 : intake.appointmentId) !== null && _c !== void 0 ? _c : null,
        region: flowId,
        consentGiven: true,
        // Snapshot of intake answers at the time we first generated decision support.
        // Phase 3 intake remains immutable; this is a separate assessment document.
        answers: answers !== null && answers !== void 0 ? answers : {},
        triageStatus: null,
        pdf: {
            status: "none",
            storagePath: null,
            url: null,
            updatedAt: now,
        },
        status: "draft",
        createdAt: now,
        updatedAt: now,
        createdByUid: uid !== null && uid !== void 0 ? uid : "system",
        updatedByUid: uid !== null && uid !== void 0 ? uid : "system",
        submittedAt: null,
        finalizedAt: null,
        // Helpful reverse-link
        intakeSessionId,
    };
    await Promise.all([
        ref.set(doc),
        db
            .collection("clinics")
            .doc(clinicId)
            .collection("intakeSessions")
            .doc(intakeSessionId)
            .set({
            assessmentId: id,
            updatedAt: now,
        }, { merge: true }),
    ]);
    return id;
}
exports.computeDecisionSupport = (0, https_1.onCall)({ region: "europe-west3" }, async (req) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p;
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
        const uid = req.auth.uid;
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
        const status = safeStr(intake === null || intake === void 0 ? void 0 : intake.status);
        if (status !== "submitted") {
            throw new https_1.HttpsError("failed-precondition", "Decision support is only available for submitted intakes.", { clinicId, intakeSessionId, status });
        }
        const assessmentId = await ensureAssessmentIdForIntake({
            clinicId,
            intakeSessionId,
            flowId,
            answers,
            intake,
            uid,
        });
        let summary;
        let engineDispatch = flowId;
        switch (flowId) {
            case "ankle": {
                const legacyAnswers = (0, ankleAdapter_1.buildAnkleLegacyAnswers)(answers);
                const raw = await (0, processAnkleAssessment_1.processAnkleAssessmentCore)({
                    assessmentId,
                    answers: legacyAnswers,
                });
                const clinician = (_c = raw === null || raw === void 0 ? void 0 : raw.clinicianSummary) !== null && _c !== void 0 ? _c : raw;
                const rawForSummary = normalizeAnkleForSummary(clinician);
                summary = (0, buildAnkleSummary_1.buildAnkleSummary)(rawForSummary, answers);
                engineDispatch = "ankle";
                break;
            }
            case "cervical": {
                const legacyAnswers = (0, cervicalAdapter_1.buildCervicalLegacyAnswers)(answers);
                const rawResult = await (0, processCervicalAssessment_1.processCervicalAssessmentCore)({
                    assessmentId,
                    answers: legacyAnswers,
                });
                const clinician = (_d = rawResult === null || rawResult === void 0 ? void 0 : rawResult.clinicianSummary) !== null && _d !== void 0 ? _d : rawResult;
                summary = (0, buildCervicalSummary_1.buildCervicalSummary)(clinician, answers);
                engineDispatch = "cervical";
                break;
            }
            case "elbow": {
                const legacyAnswers = (0, elbowAdapter_1.buildElbowLegacyAnswers)(answers);
                const rawResult = await (0, processElbowAssessment_1.processElbowAssessmentCore)({
                    assessmentId,
                    answers: legacyAnswers,
                });
                const clinician = (_e = rawResult === null || rawResult === void 0 ? void 0 : rawResult.clinicianSummary) !== null && _e !== void 0 ? _e : rawResult;
                summary = (0, buildElbowSummary_1.buildElbowSummary)(clinician, answers);
                engineDispatch = "elbow";
                break;
            }
            case "hip": {
                const legacyAnswers = (0, hipAdapter_1.buildHipLegacyAnswers)(answers);
                const rawResult = await (0, processHipAssessment_1.processHipAssessmentCore)({
                    assessmentId,
                    answers: legacyAnswers,
                });
                const clinician = (_f = rawResult === null || rawResult === void 0 ? void 0 : rawResult.clinicianSummary) !== null && _f !== void 0 ? _f : rawResult;
                summary = (0, buildHipSummary_1.buildHipSummary)(clinician, answers);
                engineDispatch = "hip";
                break;
            }
            case "knee": {
                const legacyAnswers = (0, kneeAdapter_1.buildKneeLegacyAnswers)(answers);
                const rawResult = await (0, processKneeAssessment_1.processKneeAssessmentCore)({
                    assessmentId,
                    answers: legacyAnswers,
                });
                const clinician = (_g = rawResult === null || rawResult === void 0 ? void 0 : rawResult.clinicianSummary) !== null && _g !== void 0 ? _g : rawResult;
                summary = (0, buildKneeSummary_1.buildKneeSummary)(clinician, answers);
                engineDispatch = "knee";
                break;
            }
            case "lumbar": {
                const answerMap = (0, lumbarAdapter_1.buildLumbarAnswerMap)(answers);
                const rawResult = await (0, processLumbarAssessment_1.processLumbarAssessmentWriteCore)({
                    assessmentId,
                    answers: answerMap,
                });
                const clinician = (_h = rawResult === null || rawResult === void 0 ? void 0 : rawResult.clinicianSummary) !== null && _h !== void 0 ? _h : rawResult;
                const coreResult = (0, processLumbarAssessment_1.processLumbarAssessmentCore)(answerMap);
                // Prefer explicit coreResult for stability; clinician is stored on assessment.
                summary = (0, buildLumbarSummary_1.buildLumbarSummary)(coreResult, answers);
                engineDispatch = "lumbar";
                break;
            }
            case "shoulder": {
                const rawForScorer = (0, shoulderAdapter_1.buildShoulderRawForScorer)(answers);
                const rawResult = await (0, processShoulderAssessment_1.processShoulderAssessmentCore)({
                    assessmentId,
                    answers: rawForScorer,
                });
                const clinician = (_j = rawResult === null || rawResult === void 0 ? void 0 : rawResult.clinicianSummary) !== null && _j !== void 0 ? _j : rawResult;
                summary = (0, buildShoulderSummary_1.buildShoulderSummary)(clinician, answers);
                engineDispatch = "shoulder";
                break;
            }
            case "thoracic": {
                const legacyAnswers = (0, thoracicAdapter_1.buildThoracicLegacyAnswers)(answers);
                const rawResult = await (0, processThoracicAssessment_1.processThoracicAssessmentCore)({
                    assessmentId,
                    answers: legacyAnswers,
                });
                const clinician = (_k = rawResult === null || rawResult === void 0 ? void 0 : rawResult.clinicianSummary) !== null && _k !== void 0 ? _k : rawResult;
                summary = (0, buildThoracicSummary_1.buildThoracicSummary)(clinician, answers);
                engineDispatch = "thoracic";
                break;
            }
            case "wrist": {
                const legacyAnswers = (0, wristAdapter_1.buildWristLegacyAnswers)(answers);
                const rawResult = await (0, processWristAssessment_1.processWristAssessmentCore)({
                    assessmentId,
                    answers: legacyAnswers,
                });
                const clinician = (_l = rawResult === null || rawResult === void 0 ? void 0 : rawResult.clinicianSummary) !== null && _l !== void 0 ? _l : rawResult;
                summary = (0, buildWristSummary_1.buildWristSummary)(clinician, answers);
                engineDispatch = "wrist";
                break;
            }
            default:
                throw new https_1.HttpsError("invalid-argument", `Unsupported flowId: ${flowId}`, { flowId });
        }
        const mapped = mapSummaryToDecisionSupport(summary);
        const doc = {
            status: "ready",
            engine: `${flowId}_engine`,
            engineDispatch,
            region: flowId,
            rulesetVersion: "layerB_v1",
            generatedAt: firestore_1.FieldValue.serverTimestamp(),
            computedFromAnswerCount: Object.keys(answers !== null && answers !== void 0 ? answers : {}).length,
            summaryKeys: mapped.summaryKeys,
            topDifferentialsCount: mapped.topDifferentialsCount,
            objectiveTestsCount: mapped.objectiveTestsCount,
            diagnosticHypotheses: mapped.diagnosticHypotheses,
            recommendedTests: mapped.recommendedTests,
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
            engineDispatch,
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
                    error: safeStr((_m = e === null || e === void 0 ? void 0 : e.message) !== null && _m !== void 0 ? _m : "Decision support failed"),
                    generatedAt: firestore_1.FieldValue.serverTimestamp(),
                }, { merge: true });
            }
        }
        catch {
            // ignore
        }
        if (e instanceof https_1.HttpsError)
            throw e;
        throw new https_1.HttpsError("internal", safeStr((_o = e === null || e === void 0 ? void 0 : e.message) !== null && _o !== void 0 ? _o : "Decision support failed"), {
            name: e === null || e === void 0 ? void 0 : e.name,
            stack: safeStr((_p = e === null || e === void 0 ? void 0 : e.stack) !== null && _p !== void 0 ? _p : "").split("\n").slice(0, 12).join("\n"),
        });
    }
});
//# sourceMappingURL=computeDecisionSupport.js.map