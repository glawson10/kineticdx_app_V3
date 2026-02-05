import { AnswerValue } from "../types";

type Answer =
  | { id: string; kind: "single"; value: string }
  | { id: string; kind: "multi"; values: string[] };

export function buildThoracicLegacyAnswers(
  answers: Record<string, AnswerValue>
): Answer[] {
  const v = (qid: string) => answers[qid]?.v;

  const single = (id: string, value: unknown): Answer => ({
    id,
    kind: "single",
    value: value == null ? "" : String(value),
  });

  const multi = (id: string, arr: unknown): Answer => ({
    id,
    kind: "multi",
    values: Array.isArray(arr) ? arr.map(String) : [],
  });

  return [
    // Q1–Q3: safety / red flags
    single("Q1_trauma", v("thoracic.redflags.trauma")),
    multi("Q2_redcluster", v("thoracic.redflags.redCluster")),
    multi("Q3_neuro", v("thoracic.redflags.neuro")),

    // Q4: rest / constancy
    single("Q4_rest", v("thoracic.symptoms.restPattern")),

    // Q5–Q6: history / location
    single("Q5_onset", v("thoracic.history.onset")),
    single("Q6_location", v("thoracic.symptoms.location")),

    // Q7–Q8: aggravating / easing
    multi("Q7_worse", v("thoracic.symptoms.worse")),
    multi("Q8_better", v("thoracic.symptoms.better")),

    // Q9: irritability
    single("Q9_irritability", v("thoracic.symptoms.irritability")),

    // Q10: breath provocation
    single("Q10_breathprov", v("thoracic.symptoms.breathProvocation")),

    // Q11–Q12: sleep / band
    single("Q11_sleep", v("thoracic.symptoms.sleep")),
    single("Q12_band", v("thoracic.symptoms.band")),

    // Q13: pain now (numeric → string)
    single("Q13_pain_now", v("thoracic.pain.now")),
  ];
}
