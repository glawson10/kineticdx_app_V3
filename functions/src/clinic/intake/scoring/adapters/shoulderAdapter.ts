import { AnswerValue } from "../types";

/**
 * Build the raw object shape expected by your existing shoulder scorer:
 * normalizeShoulderAnswers(raw) reads:
 *   raw.answers.* and raw.redFlags.*
 *
 * IMPORTANT:
 * - Reads canonical IDs from shoulder_questions_v1.dart (context.side, history.onset, etc.)
 * - Maps functionLimits to EXACT legacy strings expected by shoulder scorer
 */
export function buildShoulderRawForScorer(
  answers: Record<string, AnswerValue>
): any {
  const v = (qid: string) => answers[qid]?.v;

  const strip = (val: unknown, prefix: string) =>
    typeof val === "string" && val.startsWith(prefix)
      ? val.substring(prefix.length)
      : "";

  const stripMany = (arr: unknown, prefix: string) =>
    Array.isArray(arr)
      ? (arr
          .map((x) =>
            typeof x === "string" && x.startsWith(prefix)
              ? x.substring(prefix.length)
              : null
          )
          .filter(Boolean) as string[])
      : [];

  // ---------------------------------------------------------------------------
  // Canonical IDs (from pasted shoulderQuestionsV1)
  // ---------------------------------------------------------------------------

  // side: optionId like "side.left" | "side.right" | "side.both" | "side.unsure"
  const side = strip(v("shoulder.context.side"), "side.");

  // onset: optionId like "onset.gradual" | "onset.afterOverhead" | ...
  // scorer expects: gradual | afterOverhead | afterLiftPull | minorFallJar | appeared | ""
  const onsetRaw = strip(v("shoulder.history.onset"), "onset.");
  const onset = onsetRaw === "unsure" ? "" : onsetRaw;

  // painArea: optionId like "painArea.top_front" | ...
  const painArea = strip(v("shoulder.symptoms.painArea"), "painArea.");

  // tenderSpot: optionId like "tender.ac_point" | "tender.bicipital_groove" | ...
  const tenderSpot = strip(v("shoulder.symptoms.tenderSpot"), "tender.");

  // function limits: optionIds like "limit.reaching_overhead", includes "limit.none"
  const limitsRaw = stripMany(v("shoulder.function.limits"), "limit.");

  // Legacy strings expected by scorer
  type LegacyFunctionLimit =
    | "Reaching overhead"
    | "Sports/overhead work"
    | "Putting on a jacket"
    | "Sleeping on that side";

  const isNonNull = <T,>(x: T): x is NonNullable<T> => x != null;

  // Map to EXACT legacy strings expected by the shoulder scorer.
  // If "none" is selected, return []
  const functionLimits: LegacyFunctionLimit[] = limitsRaw.includes("none")
    ? []
    : limitsRaw
        .map((k): LegacyFunctionLimit | null => {
          switch (k) {
            case "reaching_overhead":
              return "Reaching overhead";
            case "sports_overhead_work":
              return "Sports/overhead work";
            case "putting_on_jacket":
              return "Putting on a jacket";
            case "sleeping_on_side":
              return "Sleeping on that side";
            default:
              return null;
          }
        })
        .filter(isNonNull);

  // ---------------------------------------------------------------------------
  // Red flags (triage drivers)
  // ---------------------------------------------------------------------------
  const redFlags = {
    feverOrHotRedJoint: v("shoulder.redflags.feverOrHotRedJoint") === true,
    deformityAfterInjury: v("shoulder.redflags.deformityAfterInjury") === true,
    newNeuroSymptoms: v("shoulder.redflags.newNeuroSymptoms") === true,
    constantUnrelentingPain:
      v("shoulder.redflags.constantUnrelentingPain") === true,
    cancerHistoryOrWeightLoss:
      v("shoulder.redflags.cancerHistoryOrWeightLoss") === true,
    traumaHighEnergy: v("shoulder.redflags.traumaHighEnergy") === true,

    // NOTE: scorer interprets "can_active_elevate": yes means CAN elevate
    canActiveElevateToShoulderHeight:
      v("shoulder.redflags.canActiveElevateToShoulderHeight") === true,
  };

  return {
    answers: {
      side,
      onset,
      painArea,

      nightPain: v("shoulder.symptoms.nightPain") === true,
      overheadAggravates: v("shoulder.symptoms.overheadAggravates") === true,
      weakness: v("shoulder.symptoms.weakness") === true,
      stiffness: v("shoulder.symptoms.stiffness") === true,
      clicking: v("shoulder.symptoms.clicking") === true,
      neckInvolved: v("shoulder.symptoms.neckInvolved") === true,
      handNumbness: v("shoulder.symptoms.handNumbness") === true,

      tenderSpot,
      functionLimits,
    },
    redFlags,
  };
}
