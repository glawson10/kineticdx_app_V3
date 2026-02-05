import { AnswerValue } from "../types";

type LegacyAnswer =
  | { id: string; kind: "single"; value: string }
  | { id: string; kind: "multi"; values: string[] }
  | { id: string; kind: "slider"; value: number };

export function buildHipLegacyAnswers(
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

  // --- Canonical → legacy token helpers ---

  // Side (canonical: side.left/right/both/unsure) → legacy expects raw "left/right/both/unsure"
  const sideToken = (s: unknown) =>
    typeof s === "string" && s.startsWith("side.") ? s.substring("side.".length) : "";

  // Onset (canonical: onset.sudden/gradual/unsure) → legacy expects raw "sudden/gradual/unsure"
  const onsetToken = (s: unknown) =>
    typeof s === "string" && s.startsWith("onset.") ? s.substring("onset.".length) : "";

  // Pain location (canonical single) → legacy H_where is MULTI with scorer tokens.
  const whereTokens = (loc: unknown): string[] => {
    if (typeof loc !== "string") return [];
    switch (loc) {
      case "loc.outer":
        return ["lateral"]; // scorer checks where.includes("lateral")
      case "loc.groin":
        return ["groin"];
      case "loc.buttock":
        return ["buttock"];
      case "loc.diffuse":
        return ["diffuse"];
      default:
        return [];
    }
  };

  // Aggs canonical → legacy tokens the scorer checks
  const aggsTokens = (arr: unknown): string[] => {
    const a = Array.isArray(arr) ? arr.map(String) : [];
    const out: string[] = [];

    for (const opt of a) {
      if (opt === "aggs.stairs") out.push("stairs");
      if (opt === "aggs.sideLying") out.push("side-lying"); // scorer checks "side-lying"
      if (opt === "aggs.standWalk") out.push("stand_walk"); // scorer checks "stand_walk"

      // Back-compat: your older option "aggs.walk" should still contribute to stand_walk
      if (opt === "aggs.walk") out.push("stand_walk");

      // Other aggs can pass through as-is (won't harm; scorer may ignore)
      if (opt.startsWith("aggs.") && !["aggs.walk","aggs.stairs","aggs.sideLying","aggs.standWalk","aggs.none"].includes(opt)) {
        out.push(opt.substring("aggs.".length));
      }
    }

    // If "none" is selected, treat as empty set (clear signal)
    if (a.includes("aggs.none")) return [];

    // De-dupe
    return Array.from(new Set(out));
  };

  // Sleep canonical → legacy token
  const sleepToken = (s: unknown) => {
    if (s === "sleep.wakesSide") return "wakes_side"; // scorer checks sleep === "wakes_side"
    if (s === "sleep.none") return "none";
    if (s === "sleep.wakesOther") return "wakes_other";
    return "";
  };

  // Gait canonical → legacy walk token used in scorer bump logic
  const walkToken = (s: unknown) => {
    if (s === "gait.support") return "support";
    if (s === "gait.limp") return "limp";
    if (s === "gait.cannot") return "cannot";
    if (s === "gait.normal") return "normal";
    return "";
  };

  // Irritability tokens (pass through suffixes; scorer treats as strings)
  const irritOnToken = (s: unknown) =>
    typeof s === "string" && s.startsWith("irritOn.") ? s.substring("irritOn.".length) : "";

  const irritOffToken = (s: unknown) =>
    typeof s === "string" && s.startsWith("irritOff.") ? s.substring("irritOff.".length) : "";

  // Amber risks multi → strip prefix "risks."
  const amberRiskTokens = (arr: unknown) => {
    const a = Array.isArray(arr) ? arr.map(String) : [];
    if (a.includes("risks.none")) return [];
    return a
      .filter((x) => x.startsWith("risks."))
      .map((x) => x.substring("risks.".length));
  };

  return [
    // -------------------------
    // TRIAGE (authoritative keys)
    // -------------------------
    single("H_rf_high_energy", yesNo(v("hip.redflags.highEnergyTrauma"))),
    single("H_rf_fall_impact", yesNo(v("hip.redflags.fallImpact"))),
    single("H_rf_cant_weightbear", yesNo(v("hip.redflags.unableToWeightBear"))),
    single("H_rf_fever", yesNo(v("hip.redflags.feverUnwell"))),
    single("H_rf_tiny_movement_agony", yesNo(v("hip.redflags.tinyMovementAgony"))),
    single("H_rf_under16_new_limp", yesNo(v("hip.redflags.under16NewLimp"))),
    single("H_rf_cancer_history", yesNo(v("hip.redflags.historyOfCancer"))),
    multi("H_rf_amber_risks", amberRiskTokens(v("hip.redflags.amberRisks"))),

    // -------------------------
    // CONTEXT
    // -------------------------
    single("H_side", sideToken(v("hip.context.side"))),

    // -------------------------
    // SCORING DRIVERS
    // -------------------------
    single("H_onset", onsetToken(v("hip.history.onset"))),
    multi("H_where", whereTokens(v("hip.symptoms.painLocation"))),
    multi("H_aggs", aggsTokens(v("hip.symptoms.aggravators"))),
    single("H_sleep", sleepToken(v("hip.symptoms.sleep"))),
    single("H_walk", walkToken(v("hip.function.gaitAbility"))),
    single("H_irrit_on", irritOnToken(v("hip.symptoms.irritabilityOn"))),
    single("H_irrit_off", irritOffToken(v("hip.symptoms.irritabilityOff"))),

    // -------------------------
    // HISTORY / FEATURES used by scorer (explicit bools)
    // -------------------------
    single("H_hx_dysplasia", yesNo(v("hip.history.dysplasiaHistory"))),
    single("H_hx_hypermobility", yesNo(v("hip.history.hypermobilityHistory"))),
    single("H_neuro_pins_needles", yesNo(v("hip.symptoms.pinsNeedles"))),
    single("H_feat_cough_strain", yesNo(v("hip.symptoms.coughStrain"))),
    single("H_feat_reproducible_snap", yesNo(v("hip.symptoms.reproducibleSnapping"))),
    single("H_feat_sitbone", yesNo(v("hip.symptoms.sitBonePain"))),

    // -------------------------
    // Optional: you can keep these for summary UI
    // (not used by the legacy hip scorer)
    // -------------------------
    single("H_additionalInfo", v("hip.history.additionalInfo") ?? ""),
  ];
}
