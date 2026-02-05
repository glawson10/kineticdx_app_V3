import { AnswerValue } from "../types";

/**
 * Legacy answer shapes expected by processKneeAssessment.ts
 */
type LegacyAnswer =
  | { id: string; kind: "single"; value: string }
  | { id: string; kind: "multi"; values: string[] }
  | { id: string; kind: "slider"; value: number };

/**
 * Canonical (Phase-3) → legacy K_* Answer[] mapper.
 *
 * IMPORTANT:
 * - This is a "safe" adapter: it does not invent values.
 * - If knee_questions_v1.dart doesn't capture some K_* inputs the scorer reads,
 *   those fields will be "" / [] / 0 and the scorer should still run.
 *
 * HARD TRUTH (current state):
 * processKneeAssessment.ts reads many K_* IDs that are not yet captured in
 * knee_questions_v1.dart (e.g., K_feltPop, K_rapidSwellingUnder2h, etc.).
 * This adapter maps everything we DO capture, and provides safe defaults for the rest.
 *
 * Authoritative scorer keys: functions/src/knee/processKneeAssessment.ts :contentReference[oaicite:0]{index=0}
 */
export function buildKneeLegacyAnswers(
  answers: Record<string, AnswerValue>
): LegacyAnswer[] {
  const v = (qid: string) => answers[qid]?.v;

  const yesNo = (b: unknown) => (b === true ? "yes" : "no");

  const single = (id: string, value: unknown): LegacyAnswer => ({
    id,
    kind: "single",
    value: value == null ? "" : String(value),
  });

  const multi = (id: string, arr: unknown): LegacyAnswer => ({
    id,
    kind: "multi",
    values: Array.isArray(arr) ? arr.map(String) : [],
  });

  const slider = (id: string, value: unknown): LegacyAnswer => ({
    id,
    kind: "slider",
    value: typeof value === "number" ? value : Number(value ?? 0),
  });

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

  // Map knee.history.onset (onset.*) → scorer’s expected onset tokens
  // scorer expects: pivotSport | twistCatch | directBlow | overuse | gradual | unknown | patellaSlip
  const mapOnsetToScorer = (onsetId: unknown): string => {
    const o = strip(onsetId, "onset.");
    switch (o) {
      case "twist":
        return "twistCatch";
      case "directBlow":
        return "directBlow";
      case "afterLoad":
        return "overuse";
      case "gradual":
        return "gradual";
      case "unsure":
        return "unknown";
      default:
        return "";
    }
  };

  // Map knee.symptoms.painLocation (loc.*) → scorer’s expected location tokens
  // scorer expects: anterior | medial | lateral | posterior | diffuse
  const mapPainLocToScorer = (locId: unknown): string => {
    const l = strip(locId, "loc.");
    switch (l) {
      case "front":
        return "anterior";
      case "inner":
        return "medial";
      case "outer":
        return "lateral";
      case "back":
        return "posterior";
      case "diffuse":
        return "diffuse";
      default:
        return "";
    }
  };

  // Build K_painLocation as multi, even though canonical is singleChoice
  const buildPainLocationMulti = (): string[] => {
    const mapped = mapPainLocToScorer(v("knee.symptoms.painLocation"));
    return mapped ? [mapped] : [];
  };

  return [
    // -------------------------------------------------------------------------
    // TRIAGE / RED FLAGS (IDs read by computeTriage in processKneeAssessment.ts)
    // -------------------------------------------------------------------------

    // canonical: knee.redflags.unableToWeightBear → scorer: K_rf_cantWB_initial
    single("K_rf_cantWB_initial", yesNo(v("knee.redflags.unableToWeightBear"))),

    // canonical: knee.redflags.lockedKnee → scorer: K_rf_lockedNow
    single("K_rf_lockedNow", yesNo(v("knee.redflags.lockedKnee"))),

    // canonical: knee.redflags.highEnergyTrauma → scorer: K_rf_highEnergyTrauma
    single(
      "K_rf_highEnergyTrauma",
      yesNo(v("knee.redflags.highEnergyTrauma"))
    ),

    /**
     * WARNING: canonical has "hotSwollenJoint" but scorer triage key is
     * "K_rf_hotRedFeverish" (hot/red + fever/unwell). We don’t capture fever/unwell yet.
     * We map hotSwollenJoint as the closest proxy (still "safe"—no invention),
     * but it can increase RED triage sensitivity.
     */
    single(
      "K_rf_hotRedFeverish",
      yesNo(v("knee.redflags.hotSwollenJoint"))
    ),

    // Scorer triage also reads these, but canonical does not currently capture them:
    single("K_rf_newNumbFoot", ""), // missing in canonical
    single("K_rf_coldPaleFoot", ""), // missing in canonical

    // -------------------------------------------------------------------------
    // CORE SCORING INPUTS (IDs read by score() in processKneeAssessment.ts)
    // -------------------------------------------------------------------------

    // Onset type
    // canonical: knee.history.onset (onset.*) → scorer: K_onsetType
    single("K_onsetType", mapOnsetToScorer(v("knee.history.onset"))),

    // Pain location (multi)
    // canonical: knee.symptoms.painLocation (loc.*) single → scorer: K_painLocation multi
    multi("K_painLocation", buildPainLocationMulti()),

    // Pain triggers (multi)
    // canonical: knee.function.aggravators (aggs.*) → scorer: K_painTriggers (same tokens without prefix)
    multi(
      "K_painTriggers",
      stripMany(v("knee.function.aggravators"), "aggs.")
    ),

    // Instability / giving way
    // canonical: knee.symptoms.givingWay → scorer: K_currentInstability
    single(
      "K_currentInstability",
      yesNo(v("knee.symptoms.givingWay"))
    ),

    // These are read by scorer but not yet captured canonically:
    single("K_feltPop", ""), // missing in canonical
    single("K_rapidSwellingUnder2h", ""), // missing in canonical (we only have generic swelling)
    single("K_blockedExtension", ""), // missing in canonical (click/lock ≠ true extension block)
    single("K_tendonFocus", ""), // missing in canonical
    single("K_stiffMorning", yesNo(v("knee.symptoms.stiffness"))), // best-available proxy
    single("K_lateralRunPain", ""), // missing in canonical

    // -------------------------------------------------------------------------
    // PAIN SCALES (not read by scorer currently, but keep for completeness)
    // -------------------------------------------------------------------------
    slider("K_painNow", v("knee.pain.now")),
    slider("K_painWorst24h", v("knee.pain.worst24h")),

    // -------------------------------------------------------------------------
    // OTHER LEGACY KEYS (not read by scorer now, but used elsewhere / future-proof)
    // -------------------------------------------------------------------------
    // Keep these aligned with the TS expects header in knee_questions_v1.dart
    single(
      "K_rf_unableWeightBear",
      yesNo(v("knee.redflags.unableToWeightBear"))
    ),
    single("K_rf_lockedKnee", yesNo(v("knee.redflags.lockedKnee"))),
    single(
      "K_rf_traumaHighEnergy",
      yesNo(v("knee.redflags.highEnergyTrauma"))
    ),
    single("K_rf_hotSwollen", yesNo(v("knee.redflags.hotSwollenJoint"))),
    single(
      "K_rf_historyCancer",
      yesNo(v("knee.redflags.historyOfCancer"))
    ),

    single("K_side", strip(v("knee.context.side"), "side.")),
    single("K_ageBand", strip(v("knee.context.ageBand"), "age.")),

    // Symptoms (generic legacy keys some older pipelines may still read)
    single("K_swelling", yesNo(v("knee.symptoms.swelling"))),
    single("K_clickingLocking", yesNo(v("knee.symptoms.clickingLocking"))),
    single("K_stiffness", yesNo(v("knee.symptoms.stiffness"))),

    // Function (older key)
    multi(
      "K_aggs",
      stripMany(v("knee.function.aggravators"), "aggs.")
    ),

    // Impact / free text
    slider("K_dayImpact", v("knee.function.dayImpact")),
    single("K_additionalInfo", v("knee.history.additionalInfo")),
  ];
}
