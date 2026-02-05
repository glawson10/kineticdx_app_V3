// functions/src/clinic/intake/computeDecisionSupport.ts
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

import { requireActiveMemberWithPerm } from "../authz";

// Engines...
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

type DecisionSupportDoc = {
  status: "ready" | "error";
  engine: string;
  engineDispatch: string;
  region: string;
  rulesetVersion: string;
  generatedAt: FieldValue;

  computedFromAnswerCount: number;
  summaryKeys: string[];
  topDifferentialsCount: number;
  objectiveTestsCount: number;

  diagnosticHypotheses: Array<{
    code: string;
    label: string;
    confidence: number;
    rawScore: number;
    rationale: string[];
  }>;

  recommendedTests: Array<{
    category: string;
    reason: string;
  }>;

  error?: string;
};

type PrelimHypothesis = {
  code: string;
  label: string;
  rawScore: number;
  rationale: string[];
};

function safeStr(v: any) {
  return v == null ? "" : String(v);
}

function safeNum(v: any): number {
  if (typeof v === "number" && !Number.isNaN(v)) return v;
  if (typeof v === "string") {
    const n = Number(v);
    if (!Number.isNaN(n)) return n;
  }
  return 0;
}

function clamp01(x: number): number {
  if (!Number.isFinite(x)) return 0;
  return Math.max(0, Math.min(1, x));
}

function uniqStrings(items: string[]): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  for (const s of items) {
    const v = safeStr(s).trim();
    if (!v) continue;
    if (seen.has(v)) continue;
    seen.add(v);
    out.push(v);
  }
  return out;
}

function normalizeRelativeWeights(items: Array<{ rawScore: number }>): number[] {
  const positives = items.map((it) => (it.rawScore > 0 ? it.rawScore : 0));
  const sum = positives.reduce((a, b) => a + b, 0);

  if (sum <= 0) {
    const n = items.length;
    if (n === 0) return [];
    return items.map(() => 1 / n);
  }

  return positives.map((s) => clamp01(s / sum));
}

function mapSummaryToDecisionSupport(
  summary: any
): Pick<
  DecisionSupportDoc,
  | "diagnosticHypotheses"
  | "recommendedTests"
  | "summaryKeys"
  | "topDifferentialsCount"
  | "objectiveTestsCount"
> {
  const summaryKeys =
    summary && typeof summary === "object" ? Object.keys(summary) : [];

  const top = Array.isArray(summary?.topDifferentials)
    ? summary.topDifferentials
    : [];
  const topDifferentialsCount = top.length;

  const testsFromSummary = Array.isArray(summary?.objectiveTests)
    ? summary.objectiveTests.map((x: any) => safeStr(x))
    : [];

  const testsFromDx = Array.isArray(top)
    ? top
        .flatMap((dx: any) =>
          Array.isArray(dx?.objectiveTests) ? dx.objectiveTests : []
        )
        .map((x: any) => safeStr(x))
    : [];

  const allTests = uniqStrings([...testsFromSummary, ...testsFromDx]);
  const objectiveTestsCount = allTests.length;

  const prelim: PrelimHypothesis[] = top.map((dx: any): PrelimHypothesis => {
    const rawScore = safeNum(dx?.score ?? dx?.confidence ?? 0);
    return {
      code: safeStr(dx?.code ?? dx?.id ?? ""),
      label: safeStr(dx?.label ?? dx?.name ?? ""),
      rawScore,
      rationale: Array.isArray(dx?.rationale)
        ? dx.rationale.map((r: any) => safeStr(r)).filter(Boolean)
        : [],
    };
  });

  const weights = normalizeRelativeWeights(prelim);

  const diagnosticHypotheses = prelim.map((h, i) => ({
    code: h.code,
    label: h.label,
    rawScore: h.rawScore,
    confidence: clamp01(weights[i] ?? 0),
    rationale: h.rationale,
  }));

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
async function computeAnkleResult(answers: any) {
  const legacyAnswers = buildAnkleLegacyAnswers(answers);
  return await processAnkleAssessmentCore(legacyAnswers as any);
}

function normalizeAnkleForSummary(raw: any) {
  return {
    ...raw,
    triage: raw?.triage ?? raw?.triageStatus,
  };
}

export const computeDecisionSupport = onCall(
  { region: "europe-west3" },
  async (req) => {
    const db = getFirestore();

    const clinicId = safeStr(req.data?.clinicId).trim();
    const intakeSessionId = safeStr(req.data?.intakeSessionId).trim();

    try {
      if (!req.auth) {
        throw new HttpsError("unauthenticated", "Sign in required.");
      }
      if (!clinicId || !intakeSessionId) {
        throw new HttpsError(
          "invalid-argument",
          "clinicId and intakeSessionId are required",
          { clinicId, intakeSessionId }
        );
      }

      // ✅ clinical read required
      await requireActiveMemberWithPerm(
        db as any,
        clinicId,
        req.auth.uid,
        "clinical.read"
      );

      const sessionRef = db
        .collection("clinics")
        .doc(clinicId)
        .collection("intakeSessions")
        .doc(intakeSessionId);

      const snap = await sessionRef.get();
      if (!snap.exists) {
        throw new HttpsError("not-found", "Intake session not found", {
          clinicId,
          intakeSessionId,
        });
      }

      const intake = snap.data()!;
      const flow = (intake as any).flow;
      const answers = (intake as any).answers;

      if (!flow || !answers) {
        throw new HttpsError(
          "failed-precondition",
          "Invalid intake session data",
          {
            hasFlow: !!flow,
            hasAnswers: !!answers,
          }
        );
      }

      const flowId = safeStr(flow.flowId);
      let summary: any;
      let engineDispatch = flowId;

      switch (flowId) {
        case "ankle": {
          const raw = await computeAnkleResult(answers);
          const rawForSummary = normalizeAnkleForSummary(raw);
          summary = buildAnkleSummary(rawForSummary, answers);
          engineDispatch = "ankle";
          break;
        }

        case "cervical": {
          const legacyAnswers = buildCervicalLegacyAnswers(answers);
          const rawResult = processCervicalAssessmentCore(legacyAnswers as any);
          summary = buildCervicalSummary(rawResult, answers);
          engineDispatch = "cervical";
          break;
        }

        case "elbow": {
          const legacyAnswers = buildElbowLegacyAnswers(answers);
          const rawResult = processElbowAssessmentCore(legacyAnswers as any);
          summary = buildElbowSummary(rawResult, answers);
          engineDispatch = "elbow";
          break;
        }

        case "hip": {
          const legacyAnswers = buildHipLegacyAnswers(answers);
          const rawResult = processHipAssessmentCore(legacyAnswers as any);
          summary = buildHipSummary(rawResult, answers);
          engineDispatch = "hip";
          break;
        }

        case "knee": {
          const legacyAnswers = buildKneeLegacyAnswers(answers);
          const rawResult = processKneeAssessmentCore(legacyAnswers as any);
          summary = buildKneeSummary(rawResult, answers);
          engineDispatch = "knee";
          break;
        }

        case "lumbar": {
          const answerMap = buildLumbarAnswerMap(answers);
          const rawResult = processLumbarAssessmentCore(answerMap as any);
          summary = buildLumbarSummary(rawResult, answers);
          engineDispatch = "lumbar";
          break;
        }

        case "shoulder": {
          const rawForScorer = buildShoulderRawForScorer(answers);
          const rawResult = processShoulderAssessmentCore(rawForScorer as any);
          summary = buildShoulderSummary(rawResult, answers);
          engineDispatch = "shoulder";
          break;
        }

        case "thoracic": {
          const legacyAnswers = buildThoracicLegacyAnswers(answers);
          const rawResult = processThoracicAssessmentCore(legacyAnswers as any);
          summary = buildThoracicSummary(rawResult, answers);
          engineDispatch = "thoracic";
          break;
        }

        case "wrist": {
          const legacyAnswers = buildWristLegacyAnswers(answers);
          const rawResult = processWristAssessmentCore(legacyAnswers as any);
          summary = buildWristSummary(rawResult, answers);
          engineDispatch = "wrist";
          break;
        }

        default:
          throw new HttpsError(
            "invalid-argument",
            `Unsupported flowId: ${flowId}`,
            { flowId }
          );
      }

      const mapped = mapSummaryToDecisionSupport(summary);

      const doc: DecisionSupportDoc = {
        status: "ready",
        engine: `${flowId}_engine`,
        engineDispatch,
        region: flowId,
        rulesetVersion: "layerB_v1",
        generatedAt: FieldValue.serverTimestamp(),

        computedFromAnswerCount: Object.keys(answers ?? {}).length,
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
    } catch (e: any) {
      // Best-effort error doc
      try {
        if (clinicId && intakeSessionId) {
          await db
            .collection("clinics")
            .doc(clinicId)
            .collection("decisionSupport")
            .doc(intakeSessionId)
            .set(
              {
                status: "error",
                error: safeStr(e?.message ?? "Decision support failed"),
                generatedAt: FieldValue.serverTimestamp(),
              },
              { merge: true }
            );
        }
      } catch {
        // ignore
      }

      if (e instanceof HttpsError) throw e;

      throw new HttpsError(
        "internal",
        safeStr(e?.message ?? "Decision support failed"),
        {
          name: e?.name,
          stack: safeStr(e?.stack ?? "").split("\n").slice(0, 12).join("\n"),
        }
      );
    }
  }
);
