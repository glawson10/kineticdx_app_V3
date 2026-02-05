// functions/src/preassessment/keyAnswers/generalVisitV1KeyAnswers.ts
//
// Server-side keyAnswers extraction for generalVisit.v1
// Patient-reported only, whitelisted. :contentReference[oaicite:5]{index=5}

type AnswerMap = Record<string, any>;

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

function readText(answers: AnswerMap, qid: string): string | null {
  const a = answers[qid];
  if (a && typeof a === "object" && a.t === "text") {
    const v = safeStr(a.v);
    return v.length ? v : null;
  }
  return null;
}

function readSingle(answers: AnswerMap, qid: string): string | null {
  const a = answers[qid];
  if (a && typeof a === "object" && a.t === "single") {
    const v = safeStr(a.v);
    return v.length ? v : null;
  }
  return null;
}

function readMulti(answers: AnswerMap, qid: string): string[] | null {
  const a = answers[qid];
  if (a && typeof a === "object" && a.t === "multi" && Array.isArray(a.v)) {
    const vals = a.v.map((x: any) => safeStr(x)).filter(Boolean);
    return vals.length ? vals : null;
  }
  return null;
}

// Label maps (must match your UI maps; safe to compute server-side for previews)
const concernClarityLabels: Record<string, string> = {
  "concern.single": "One main concern",
  "concern.multiple": "Multiple concerns",
  "concern.unsure": "Not sure",
};

const bodyAreaLabels: Record<string, string> = {
  "area.neck": "Neck",
  "area.upperBack": "Upper back",
  "area.lowerBack": "Lower back",
  "area.shoulder": "Shoulder",
  "area.elbow": "Elbow",
  "area.wristHand": "Wrist/Hand",
  "area.hip": "Hip",
  "area.knee": "Knee",
  "area.ankleFoot": "Ankle/Foot",
  "area.multiple": "Multiple areas",
  "area.general": "General / whole body",
};

const durationLabels: Record<string, string> = {
  "duration.days": "Days",
  "duration.weeks": "Weeks",
  "duration.months": "Months",
  "duration.years": "Years",
  "duration.unsure": "Not sure",
};

const impactLabels: Record<string, string> = {
  "impact.work": "Work",
  "impact.sport": "Sport / exercise",
  "impact.sleep": "Sleep",
  "impact.dailyActivities": "Daily activities",
  "impact.generalMovement": "General movement",
  "impact.unclear": "Not sure",
};

function labelSingle(id: string | null, map: Record<string, string>): string {
  if (!id) return "—";
  return map[id] ?? id;
}

function labelsMulti(ids: string[] | null, map: Record<string, string>): string[] {
  if (!ids) return [];
  const out: string[] = [];
  const seen = new Set<string>();
  for (const raw of ids) {
    const id = safeStr(raw);
    if (!id || seen.has(id)) continue;
    seen.add(id);
    out.push(map[id] ?? id);
  }
  return out;
}

function joinOrDash(items: string[]): string {
  return items.length ? items.join(", ") : "—";
}

export function extractGeneralVisitV1KeyAnswers(answers: AnswerMap) {
  // Whitelist (must match the contract you defined)
  const qReason = "generalVisit.goals.reasonForVisit";
  const qClarity = "generalVisit.meta.concernClarity";
  const qAreas = "generalVisit.history.bodyAreas";
  const qImpact = "generalVisit.function.primaryImpact";
  const qDuration = "generalVisit.history.duration";
  const qIntent = "generalVisit.goals.visitIntent";

  const keyAnswers: Record<string, any> = {
    [qReason]: readText(answers, qReason),
    [qClarity]: readSingle(answers, qClarity),
    [qAreas]: readMulti(answers, qAreas),
    [qImpact]: readSingle(answers, qImpact),
    [qDuration]: readSingle(answers, qDuration),
    [qIntent]: readMulti(answers, qIntent),
  };

  // Remove nulls for compact storage
  for (const k of Object.keys(keyAnswers)) {
    if (keyAnswers[k] == null) delete keyAnswers[k];
  }

  // Tiny preview labels for clinician list rows/cards (optional but very helpful)
  const clarityLabel = labelSingle(keyAnswers[qClarity] ?? null, concernClarityLabels);
  const areasLabel = joinOrDash(labelsMulti(keyAnswers[qAreas] ?? null, bodyAreaLabels));
  const durationLabel = labelSingle(keyAnswers[qDuration] ?? null, durationLabels);
  const impactLabel = labelSingle(keyAnswers[qImpact] ?? null, impactLabels);

  const summaryPreview = {
    concernClarityLabel: clarityLabel,
    areasLabel,
    durationLabel,
    impactLabel,
  };

  return {
    keyAnswers,
    keyAnswersVersion: "generalVisit.v1",
    summaryPreview,
  };
}
