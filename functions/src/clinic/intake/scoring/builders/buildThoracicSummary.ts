export interface ThoracicSummary {
  region: "thoracic";
  triage: {
    level: "red" | "amber" | "green";
    reasons: string[];
  };
  topDifferentials: {
    code: string;
    label: string;
    score: number;
    rationale: string[];
  }[];
  objectiveTests: string[];
  narrative: string;
  tables: {
    safety: { question: string; answer: string }[];
    context: { question: string; answer: string }[];
    symptoms: { question: string; answer: string }[];
    function: { question: string; answer: string }[];
    other: { question: string; answer: string }[];
  };
}

type AnyAnswerValue = { t?: string; v?: any } | any;

// Keep row shape locked to the ThoracicSummary interface
type TableRow = ThoracicSummary["tables"]["safety"][number];

/**
 * Human-friendly formatting for the Phase-3 canonical answers map.
 * Supports:
 * - {t:"single", v:"optionId"}
 * - {t:"multi", v:["optA","optB"]}
 * - {t:"int"/"num", v: number}
 * - booleans / strings / numbers directly
 */
function formatAnswer(av: AnyAnswerValue): string {
  if (av == null) return "—";

  // Canonical AnswerValue-ish shape
  if (typeof av === "object" && av !== null && "v" in av) {
    const v = (av as any).v;
    if (v == null) return "—";
    if (Array.isArray(v)) return v.length ? v.map(String).join(", ") : "—";
    if (typeof v === "boolean") return v ? "yes" : "no";
    return String(v);
  }

  // Raw primitives
  if (Array.isArray(av)) return av.length ? av.map(String).join(", ") : "—";
  if (typeof av === "boolean") return av ? "yes" : "no";
  if (typeof av === "number") return String(av);
  if (typeof av === "string") return av.trim() ? av : "—";

  return String(av);
}

export function buildThoracicSummary(
  raw: any,
  answers: Record<string, any>
): ThoracicSummary {
  const triage = (raw?.triage ?? "green") as "red" | "amber" | "green";
  const reasons: string[] = Array.isArray(raw?.redFlagNotes)
    ? raw.redFlagNotes
    : [];

  const detailedTop = Array.isArray(raw?.detailedTop) ? raw.detailedTop : [];
  const top3 = detailedTop.slice(0, 3).map((d: any) => ({
    code: d?.name ?? "unknown",
    label: d?.name ?? "Unknown",
    score: Number(d?.score ?? 0),
    rationale: Array.isArray(d?.rationale) ? d.rationale : [],
  }));

  const tests = detailedTop
    .flatMap((d: any) =>
      Array.isArray(d?.objectiveTests) ? d.objectiveTests : []
    )
    .filter((x: any) => typeof x === "string" && x.trim().length > 0);

  const row = (qid: string, label: string): TableRow => ({
    question: label,
    answer: formatAnswer(answers?.[qid]),
  });

  // ---------------------------------------------------------------------------
  // Tables: based on thoracic_questions_v1.dart (TS-aligned canonical IDs)
  // ---------------------------------------------------------------------------

  const safety: TableRow[] = [
    row("thoracic.redflags.trauma", "Trauma severity"),
    row("thoracic.redflags.redCluster", "Red cluster symptoms"),
    row("thoracic.redflags.neuro", "Neurological red flags"),
  ];

  const context: TableRow[] = [
    row("thoracic.history.onset", "Onset"),
    row("thoracic.history.additionalInfo", "Additional info"),
  ];

  const symptoms: TableRow[] = [
    row("thoracic.symptoms.restPattern", "Pain at rest / constancy"),
    row("thoracic.symptoms.breathProvocation", "Breathing provocation"),
    row("thoracic.symptoms.location", "Pain location"),
    row("thoracic.symptoms.worse", "Worse with"),
    row("thoracic.symptoms.better", "Better with"),
    row("thoracic.symptoms.irritability", "Irritability"),
    row("thoracic.symptoms.sleep", "Sleep"),
    row("thoracic.symptoms.band", "Band-like distribution"),
  ];

  // Thoracic v1 doesn’t define a separate functional domain beyond sleep;
  // keep this table empty, but typed (avoids implicit any[])
  const functionTable: TableRow[] = [];

  const other: TableRow[] = [
    row("thoracic.pain.now", "Pain now (0–10)"),
  ];

  return {
    region: "thoracic",
    triage: { level: triage, reasons },
    topDifferentials: top3,
    objectiveTests: Array.from(new Set(tests)),
    narrative:
      "Thoracic presentation scored using region-specific rules. Review top differentials, triage, and suggested objective tests.",
    tables: {
      safety,
      context,
      symptoms,
      function: functionTable,
      other,
    },
  };
}
