// functions/src/clinic/intake/generateIntakeSummaryFn.ts
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";

import { requireActiveMemberWithPerm } from "../authz";

// -----------------------------------------------------------------------------
// Engines
// -----------------------------------------------------------------------------
import { buildAnkleLegacyAnswers } from "./scoring/adapters/ankleAdapter";
import { buildAnkleSummary } from "./scoring/builders/buildAnkleSummary";
import { processAnkleAssessmentCore } from "../../preassessmentRegion/ankle/processAnkleAssessment";

import { buildCervicalLegacyAnswers } from "./scoring/adapters/cervicalAdapter";
import { buildCervicalSummary } from "./scoring/builders/buildCervicalSummary";
import { processCervicalAssessmentCore } from "../../preassessmentRegion/cervical/processCervicalAssessment";

import { buildElbowLegacyAnswers } from "./scoring/adapters/elbowAdapter";
import { buildElbowSummary } from "./scoring/builders/buildElbowSummary";
import { processElbowAssessmentCore } from "../../preassessmentRegion/elbow/processElbowAssessment";

import { buildHipLegacyAnswers } from "./scoring/adapters/hipAdapter";
import { buildHipSummary } from "./scoring/builders/buildHipSummary";
import { processHipAssessmentCore } from "../../preassessmentRegion/hip/processHipAssessment";

import { buildKneeLegacyAnswers } from "./scoring/adapters/kneeAdapter";
import { buildKneeSummary } from "./scoring/builders/buildKneeSummary";
import { processKneeAssessmentCore } from "../../preassessmentRegion/knee/processKneeAssessment";

import { buildLumbarAnswerMap } from "./scoring/adapters/lumbarAdapter";
import { buildLumbarSummary } from "./scoring/builders/buildLumbarSummary";
import { processLumbarAssessmentCore } from "../../preassessmentRegion/lumbar/processLumbarAssessment";

import { buildShoulderRawForScorer } from "./scoring/adapters/shoulderAdapter";
import { buildShoulderSummary } from "./scoring/builders/buildShoulderSummary";
import { processShoulderAssessmentCore } from "../../preassessmentRegion/shoulder/processShoulderAssessment";

import { buildThoracicLegacyAnswers } from "./scoring/adapters/thoracicAdapter";
import { buildThoracicSummary } from "./scoring/builders/buildThoracicSummary";
import { processThoracicAssessmentCore } from "../../preassessmentRegion/thoracic/processThoracicAssessment";

import { buildWristLegacyAnswers } from "./scoring/adapters/wristAdapter";
import { buildWristSummary } from "./scoring/builders/buildWristSummary";
import { processWristAssessmentCore } from "../../preassessmentRegion/wrist/processWristAssessment";

/**
 * NOTE:
 * - Your ankle engine returns an async result (Promise) with `triageStatus`.
 * - The summary builder expects `triage`.
 * - So: await + normalize triageStatus -> triage.
 *
 * If `processAnkleAssessmentCore` is actually sync in your codebase,
 * you can remove `async/await` and call it directly.
 */
async function computeAnkleResult(answers: any) {
  const legacyAnswers = buildAnkleLegacyAnswers(answers);
  // Most of your other engines are sync; ankle is the one you said is async.
  // If this is sync, just return processAnkleAssessmentCore(legacyAnswers as any);
  return await processAnkleAssessmentCore(legacyAnswers as any);
}

function normalizeAnkleForSummary(raw: any) {
  return {
    ...raw,
    triage: raw?.triage ?? raw?.triageStatus,
  };
}

export const generateIntakeSummaryFn = onCall(
  { region: "europe-west3" },
  async (req) => {
    if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

    const clinicId = String(req.data?.clinicId ?? "").trim();
    const intakeSessionId = String(req.data?.intakeSessionId ?? "").trim();

    if (!clinicId || !intakeSessionId) {
      throw new HttpsError(
        "invalid-argument",
        "clinicId and intakeSessionId are required",
        { clinicId, intakeSessionId }
      );
    }

    const db = getFirestore();
    const uid = req.auth.uid;

    // ✅ Intakes are clinical content
    await requireActiveMemberWithPerm(db as any, clinicId, uid, "clinical.read");

    const snap = await db
      .collection("clinics")
      .doc(clinicId)
      .collection("intakeSessions")
      .doc(intakeSessionId)
      .get();

    if (!snap.exists) {
      throw new HttpsError("not-found", "Intake session not found.");
    }

    const intake = snap.data() as any;
    const flow = intake?.flow;
    const answers = intake?.answers;

    if (!flow || !answers) {
      throw new HttpsError("failed-precondition", "Invalid intake session data", {
        hasFlow: !!flow,
        hasAnswers: !!answers,
      });
    }

    const flowId = String(flow.flowId ?? "").trim();

    let summary: any;

    switch (flowId) {
      case "ankle": {
        const raw = await computeAnkleResult(answers);
        const rawForSummary = normalizeAnkleForSummary(raw);
        summary = buildAnkleSummary(rawForSummary, answers);
        break;
      }

      case "cervical": {
        const legacyAnswers = buildCervicalLegacyAnswers(answers);
        const rawResult = processCervicalAssessmentCore(legacyAnswers as any);
        summary = buildCervicalSummary(rawResult, answers);
        break;
      }

      case "elbow": {
        const legacyAnswers = buildElbowLegacyAnswers(answers);
        const rawResult = processElbowAssessmentCore(legacyAnswers as any);
        summary = buildElbowSummary(rawResult, answers);
        break;
      }

      case "hip": {
        const legacyAnswers = buildHipLegacyAnswers(answers);
        const rawResult = processHipAssessmentCore(legacyAnswers as any);
        summary = buildHipSummary(rawResult, answers);
        break;
      }

      case "knee": {
        const legacyAnswers = buildKneeLegacyAnswers(answers);
        const rawResult = processKneeAssessmentCore(legacyAnswers as any);
        summary = buildKneeSummary(rawResult, answers);
        break;
      }

      case "lumbar": {
        const answerMap = buildLumbarAnswerMap(answers);
        const rawResult = processLumbarAssessmentCore(answerMap as any);
        summary = buildLumbarSummary(rawResult, answers);
        break;
      }

      case "shoulder": {
        const rawForScorer = buildShoulderRawForScorer(answers);
        const rawResult = processShoulderAssessmentCore(rawForScorer as any);
        summary = buildShoulderSummary(rawResult, answers);
        break;
      }

      case "thoracic": {
        const legacyAnswers = buildThoracicLegacyAnswers(answers);
        const rawResult = processThoracicAssessmentCore(legacyAnswers as any);
        summary = buildThoracicSummary(rawResult, answers);
        break;
      }

      case "wrist": {
        const legacyAnswers = buildWristLegacyAnswers(answers);
        const rawResult = processWristAssessmentCore(legacyAnswers as any);
        summary = buildWristSummary(rawResult, answers);
        break;
      }

      default:
        throw new HttpsError("invalid-argument", `Unsupported flowId: ${flowId}`, {
          flowId,
        });
    }

    return { ok: true, flowId, summary };
  }
);
