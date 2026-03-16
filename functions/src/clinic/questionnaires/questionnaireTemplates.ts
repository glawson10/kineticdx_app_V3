import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";

type AnyMap = Record<string, unknown>;

export const QUESTIONNAIRE_TEMPLATE_SOURCE_BUILT_IN = "builtIn";
export const QUESTIONNAIRE_TEMPLATE_SOURCE_CUSTOM = "custom";

export const QUESTIONNAIRE_LAUNCH_KIND_BOOKING_PREASSESSMENT = "bookingPreassessment";
export const QUESTIONNAIRE_LAUNCH_KIND_INTAKE_LINK = "intakeLink";
export const QUESTIONNAIRE_LAUNCH_KIND_ROUTE = "route";

export const BUILTIN_PREASSESSMENT_BOOKING_TEMPLATE_ID = "builtin.preassessment.booking";
export const BUILTIN_GENERAL_VISIT_TEMPLATE_ID = "builtin.generalVisit";

/** PA-P3.1: Legacy fallback when template has no flowDefinitionId/clinicalProfileId (e.g. old custom templates). */
export const LEGACY_BOOKING_DEFAULT_FLOW_ID = "ankle";

const VALID_TEMPLATE_SOURCES = new Set([
  QUESTIONNAIRE_TEMPLATE_SOURCE_BUILT_IN,
  QUESTIONNAIRE_TEMPLATE_SOURCE_CUSTOM,
]);

const VALID_LAUNCH_KINDS = new Set([
  QUESTIONNAIRE_LAUNCH_KIND_BOOKING_PREASSESSMENT,
  QUESTIONNAIRE_LAUNCH_KIND_INTAKE_LINK,
  QUESTIONNAIRE_LAUNCH_KIND_ROUTE,
]);

export type QuestionnaireFlowTemplateRef = {
  templateId: string;
  source: string;
  /** Optional. When present and non-empty, this template is only offered at these location IDs. Empty or absent = all locations. */
  locationIds?: string[];
};

export type QuestionnaireFlowConfig = {
  enabled: boolean;
  templates: QuestionnaireFlowTemplateRef[];
};

export type QuestionnaireTemplateSummary = {
  templateId: string;
  source: string;
  /** Display name (alias: use label when name not set). */
  label: string;
  name?: string | null;
  description?: string | null;
  active: boolean;
  patientFacing: boolean;
  launchKind: string;
  launchRoute?: string | null;
  flowId?: string | null;
  flowVersion?: number | null;
  flowCategory?: string | null;
  /** Optional template version (distinct from flowVersion). */
  version?: number | null;
  /** Optional category for grouping. */
  category?: string | null;
  /** PA-P3: required for registry-driven dispatch. Built-ins may set defaults. */
  flowDefinitionId?: string | null;
  /** PA-P3: required for registry-driven dispatch. Built-ins may set defaults. */
  clinicalProfileId?: string | null;
};

export type PublicQuestionnaireTemplateSummary = {
  templateId: string;
  source: string;
  label: string;
  description?: string | null;
  launchKind: string;
  launchRoute?: string | null;
  /** Optional. When present and non-empty, show this template only when booking at one of these location IDs. Empty or absent = all locations. */
  locationIds?: string[];
};

export type PublicQuestionnaireFlowConfig = {
  enabled: boolean;
  templates: PublicQuestionnaireTemplateSummary[];
};

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

function safeInt(v: unknown, fallback: number): number {
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? Math.trunc(n) : fallback;
}

function isObj(v: unknown): v is AnyMap {
  return !!v && typeof v === "object" && !Array.isArray(v);
}

export function builtInQuestionnaireTemplates(): QuestionnaireTemplateSummary[] {
  return [
    {
      templateId: BUILTIN_PREASSESSMENT_BOOKING_TEMPLATE_ID,
      source: QUESTIONNAIRE_TEMPLATE_SOURCE_BUILT_IN,
      label: "Specific issue questionnaire",
      description:
        "Guides the patient into the specific-issue preassessment flow linked to their booking.",
      active: true,
      patientFacing: true,
      launchKind: QUESTIONNAIRE_LAUNCH_KIND_BOOKING_PREASSESSMENT,
      launchRoute: "/preassessment/consent",
      flowId: LEGACY_BOOKING_DEFAULT_FLOW_ID,
      flowVersion: 1,
      flowCategory: "region",
      flowDefinitionId: "builtin.ankle.v1",
      clinicalProfileId: "builtin.ankle",
    },
    {
      templateId: BUILTIN_GENERAL_VISIT_TEMPLATE_ID,
      source: QUESTIONNAIRE_TEMPLATE_SOURCE_BUILT_IN,
      label: "General questionnaire",
      description:
        "Captures broad visit goals and context before the appointment.",
      active: true,
      patientFacing: true,
      launchKind: QUESTIONNAIRE_LAUNCH_KIND_INTAKE_LINK,
      launchRoute: "/q/launch",
      flowId: "generalVisit",
      flowVersion: 1,
      flowCategory: "general",
      flowDefinitionId: "builtin.generalVisit.v1",
      clinicalProfileId: "builtin.generalVisit",
    },
  ];
}

function normalizeTemplateSource(raw: unknown, templateId: string): string {
  const source = safeStr(raw);
  if (VALID_TEMPLATE_SOURCES.has(source)) return source;
  if (templateId.startsWith("builtin.")) return QUESTIONNAIRE_TEMPLATE_SOURCE_BUILT_IN;
  return QUESTIONNAIRE_TEMPLATE_SOURCE_CUSTOM;
}

function normalizeLaunchKind(raw: unknown): string {
  const launchKind = safeStr(raw);
  if (!VALID_LAUNCH_KINDS.has(launchKind)) {
    throw new HttpsError("invalid-argument", "questionnaire template launchKind is invalid.");
  }
  return launchKind;
}

export function validateQuestionnaireFlow(raw: unknown): QuestionnaireFlowConfig {
  if (!isObj(raw)) {
    return { enabled: false, templates: [] };
  }
  const enabled = raw.enabled === true;
  const templatesRaw = Array.isArray(raw.templates) ? raw.templates : [];
  const seen = new Set<string>();
  const templates: QuestionnaireFlowTemplateRef[] = [];

  for (let i = 0; i < templatesRaw.length; i++) {
    const item = templatesRaw[i];
    if (!isObj(item)) {
      throw new HttpsError("invalid-argument", `questionnaireFlow.templates[${i}] must be an object.`);
    }
    const templateId = safeStr(item.templateId ?? item.id);
    if (!templateId) {
      throw new HttpsError("invalid-argument", `questionnaireFlow.templates[${i}].templateId is required.`);
    }
    if (seen.has(templateId)) continue;
    seen.add(templateId);
    const locationIdsRaw = item.locationIds;
    const locationIds = Array.isArray(locationIdsRaw)
      ? locationIdsRaw.map((x) => safeStr(x)).filter((s) => s.length > 0)
      : undefined;
    templates.push({
      templateId,
      source: normalizeTemplateSource(item.source, templateId),
      ...(locationIds && locationIds.length > 0 ? { locationIds } : {}),
    });
  }

  return { enabled, templates };
}

function sanitizeDescription(raw: unknown): string | null {
  const value = safeStr(raw);
  return value ? value : null;
}

export function customQuestionnaireTemplateFromDoc(
  docId: string,
  raw: unknown
): QuestionnaireTemplateSummary | null {
  if (!isObj(raw)) return null;
  const templateId = safeStr(raw.templateId) || safeStr(docId);
  if (!templateId) return null;
  const source = normalizeTemplateSource(raw.source, templateId);
  const label = safeStr(raw.label ?? raw.name ?? raw.title) || templateId;
  const launchKindRaw = safeStr(raw.launchKind);
  if (!launchKindRaw) return null;

  let launchKind: string;
  try {
    launchKind = normalizeLaunchKind(launchKindRaw);
  } catch {
    return null;
  }

  return {
    templateId,
    source,
    label: label,
    name: sanitizeDescription(raw.name ?? raw.label ?? raw.title) || label,
    description: sanitizeDescription(raw.description),
    active: raw.active !== false,
    patientFacing: raw.patientFacing !== false,
    launchKind,
    launchRoute: sanitizeDescription(raw.launchRoute),
    flowId: sanitizeDescription(raw.flowId),
    flowVersion: raw.flowVersion === undefined ? null : safeInt(raw.flowVersion, 1),
    flowCategory: sanitizeDescription(raw.flowCategory),
    version: raw.version === undefined ? null : safeInt(raw.version, 1),
    category: sanitizeDescription(raw.category),
    flowDefinitionId: sanitizeDescription(raw.flowDefinitionId),
    clinicalProfileId: sanitizeDescription(raw.clinicalProfileId),
  };
}

export async function loadQuestionnaireTemplateById(
  db: admin.firestore.Firestore,
  clinicId: string,
  templateId: string
): Promise<QuestionnaireTemplateSummary | null> {
  const builtIn = builtInQuestionnaireTemplates().find((t) => t.templateId === templateId);
  if (builtIn) return builtIn;

  const snap = await db
    .collection("clinics")
    .doc(clinicId)
    .collection("questionnaireTemplates")
    .doc(templateId)
    .get();
  if (!snap.exists) return null;
  return customQuestionnaireTemplateFromDoc(snap.id, snap.data());
}

export async function buildPublicQuestionnaireFlow(
  db: admin.firestore.Firestore,
  clinicId: string,
  raw: unknown
): Promise<PublicQuestionnaireFlowConfig> {
  const flow = validateQuestionnaireFlow(raw);
  if (!flow.enabled || flow.templates.length === 0) {
    return { enabled: false, templates: [] };
  }

  const resolved = await Promise.all(
    flow.templates.map((ref) => loadQuestionnaireTemplateById(db, clinicId, ref.templateId))
  );

  const refByTemplateId = new Map(flow.templates.map((r) => [r.templateId, r]));
  const templates = resolved
    .filter((t): t is QuestionnaireTemplateSummary => !!t)
    .filter((t) => t.active && t.patientFacing)
    .map<PublicQuestionnaireTemplateSummary>((t) => {
      const ref = refByTemplateId.get(t.templateId);
      const locationIds =
        ref?.locationIds && ref.locationIds.length > 0 ? ref.locationIds : undefined;
      return {
        templateId: t.templateId,
        source: t.source,
        label: t.label,
        description: t.description ?? null,
        launchKind: t.launchKind,
        launchRoute: t.launchRoute ?? null,
        ...(locationIds ? { locationIds } : {}),
      };
    });

  return {
    enabled: templates.length > 0,
    templates,
  };
}

/**
 * OBS-P2: List all templates for a clinic (built-in + custom from clinics/{clinicId}/questionnaireTemplates).
 * Clinic-scoped source: custom templates read from clinics/{clinicId}/questionnaireTemplates/{templateId}.
 */
export async function listQuestionnaireTemplates(
  db: admin.firestore.Firestore,
  clinicId: string
): Promise<QuestionnaireTemplateSummary[]> {
  const builtIn = builtInQuestionnaireTemplates();
  const customSnap = await db
    .collection("clinics")
    .doc(clinicId)
    .collection("questionnaireTemplates")
    .get();
  const custom = customSnap.docs
    .map((d) => customQuestionnaireTemplateFromDoc(d.id, d.data()))
    .filter((t): t is QuestionnaireTemplateSummary => t != null);
  const byId = new Map<string, QuestionnaireTemplateSummary>();
  for (const t of builtIn) byId.set(t.templateId, t);
  for (const t of custom) byId.set(t.templateId, t);
  return Array.from(byId.values());
}

