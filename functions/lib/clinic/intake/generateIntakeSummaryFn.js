"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateIntakeSummaryFn = void 0;
// functions/src/clinic/intake/generateIntakeSummaryFn.ts
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const authz_1 = require("../authz");
// -----------------------------------------------------------------------------
// Engines
// -----------------------------------------------------------------------------
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
/**
 * NOTE:
 * - Your ankle engine returns an async result (Promise) with `triageStatus`.
 * - The summary builder expects `triage`.
 * - So: await + normalize triageStatus -> triage.
 *
 * If `processAnkleAssessmentCore` is actually sync in your codebase,
 * you can remove `async/await` and call it directly.
 */
async function computeAnkleResult(answers) {
    const legacyAnswers = (0, ankleAdapter_1.buildAnkleLegacyAnswers)(answers);
    // Most of your other engines are sync; ankle is the one you said is async.
    // If this is sync, just return processAnkleAssessmentCore(legacyAnswers as any);
    return await (0, processAnkleAssessment_1.processAnkleAssessmentCore)(legacyAnswers);
}
function normalizeAnkleForSummary(raw) {
    var _a;
    return {
        ...raw,
        triage: (_a = raw === null || raw === void 0 ? void 0 : raw.triage) !== null && _a !== void 0 ? _a : raw === null || raw === void 0 ? void 0 : raw.triageStatus,
    };
}
exports.generateIntakeSummaryFn = (0, https_1.onCall)({ region: "europe-west3" }, async (req) => {
    var _a, _b, _c, _d, _e;
    if (!req.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const clinicId = String((_b = (_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId) !== null && _b !== void 0 ? _b : "").trim();
    const intakeSessionId = String((_d = (_c = req.data) === null || _c === void 0 ? void 0 : _c.intakeSessionId) !== null && _d !== void 0 ? _d : "").trim();
    if (!clinicId || !intakeSessionId) {
        throw new https_1.HttpsError("invalid-argument", "clinicId and intakeSessionId are required", { clinicId, intakeSessionId });
    }
    const db = (0, firestore_1.getFirestore)();
    const uid = req.auth.uid;
    // ✅ Intakes are clinical content
    await (0, authz_1.requireActiveMemberWithPerm)(db, clinicId, uid, "clinical.read");
    const snap = await db
        .collection("clinics")
        .doc(clinicId)
        .collection("intakeSessions")
        .doc(intakeSessionId)
        .get();
    if (!snap.exists) {
        throw new https_1.HttpsError("not-found", "Intake session not found.");
    }
    const intake = snap.data();
    const flow = intake === null || intake === void 0 ? void 0 : intake.flow;
    const answers = intake === null || intake === void 0 ? void 0 : intake.answers;
    if (!flow || !answers) {
        throw new https_1.HttpsError("failed-precondition", "Invalid intake session data", {
            hasFlow: !!flow,
            hasAnswers: !!answers,
        });
    }
    const flowId = String((_e = flow.flowId) !== null && _e !== void 0 ? _e : "").trim();
    let summary;
    switch (flowId) {
        case "ankle": {
            const raw = await computeAnkleResult(answers);
            const rawForSummary = normalizeAnkleForSummary(raw);
            summary = (0, buildAnkleSummary_1.buildAnkleSummary)(rawForSummary, answers);
            break;
        }
        case "cervical": {
            const legacyAnswers = (0, cervicalAdapter_1.buildCervicalLegacyAnswers)(answers);
            const rawResult = (0, processCervicalAssessment_1.processCervicalAssessmentCore)(legacyAnswers);
            summary = (0, buildCervicalSummary_1.buildCervicalSummary)(rawResult, answers);
            break;
        }
        case "elbow": {
            const legacyAnswers = (0, elbowAdapter_1.buildElbowLegacyAnswers)(answers);
            const rawResult = (0, processElbowAssessment_1.processElbowAssessmentCore)(legacyAnswers);
            summary = (0, buildElbowSummary_1.buildElbowSummary)(rawResult, answers);
            break;
        }
        case "hip": {
            const legacyAnswers = (0, hipAdapter_1.buildHipLegacyAnswers)(answers);
            const rawResult = (0, processHipAssessment_1.processHipAssessmentCore)(legacyAnswers);
            summary = (0, buildHipSummary_1.buildHipSummary)(rawResult, answers);
            break;
        }
        case "knee": {
            const legacyAnswers = (0, kneeAdapter_1.buildKneeLegacyAnswers)(answers);
            const rawResult = (0, processKneeAssessment_1.processKneeAssessmentCore)(legacyAnswers);
            summary = (0, buildKneeSummary_1.buildKneeSummary)(rawResult, answers);
            break;
        }
        case "lumbar": {
            const answerMap = (0, lumbarAdapter_1.buildLumbarAnswerMap)(answers);
            const rawResult = (0, processLumbarAssessment_1.processLumbarAssessmentCore)(answerMap);
            summary = (0, buildLumbarSummary_1.buildLumbarSummary)(rawResult, answers);
            break;
        }
        case "shoulder": {
            const rawForScorer = (0, shoulderAdapter_1.buildShoulderRawForScorer)(answers);
            const rawResult = (0, processShoulderAssessment_1.processShoulderAssessmentCore)(rawForScorer);
            summary = (0, buildShoulderSummary_1.buildShoulderSummary)(rawResult, answers);
            break;
        }
        case "thoracic": {
            const legacyAnswers = (0, thoracicAdapter_1.buildThoracicLegacyAnswers)(answers);
            const rawResult = (0, processThoracicAssessment_1.processThoracicAssessmentCore)(legacyAnswers);
            summary = (0, buildThoracicSummary_1.buildThoracicSummary)(rawResult, answers);
            break;
        }
        case "wrist": {
            const legacyAnswers = (0, wristAdapter_1.buildWristLegacyAnswers)(answers);
            const rawResult = (0, processWristAssessment_1.processWristAssessmentCore)(legacyAnswers);
            summary = (0, buildWristSummary_1.buildWristSummary)(rawResult, answers);
            break;
        }
        default:
            throw new https_1.HttpsError("invalid-argument", `Unsupported flowId: ${flowId}`, {
                flowId,
            });
    }
    return { ok: true, flowId, summary };
});
//# sourceMappingURL=generateIntakeSummaryFn.js.map