/**
 * PA-P3: Registry-driven intake dispatch.
 * Flow definition and clinical profile registries + legacy flowId shim.
 */

export type FlowDefinitionRegistryEntry = {
  flowDefinitionId: string;
  flowId: string;
  flowVersion: number;
  firstScreenRoute: string;
  /** Optional: for region flows, body area id (ankle, knee, etc.) */
  regionBodyArea?: string;
};

export type ClinicalProfileRegistryEntry = {
  clinicalProfileId: string;
  summaryEngine: string;
  decisionSupportProfile: string;
  supportsDifferentialHypothesis: boolean;
};

export type LegacyRegistryResult = {
  flowDefinitionId: string;
  clinicalProfileId: string;
  flowId: string;
  flowVersion: number;
  summaryEngine: string;
  decisionSupportProfile: string;
  supportsDifferentialHypothesis: boolean;
};

const REGION_FLOW_IDS = [
  "ankle",
  "cervical",
  "elbow",
  "hip",
  "knee",
  "lumbar",
  "shoulder",
  "thoracic",
  "wrist",
] as const;

/** Built-in flow definition registry: flowDefinitionId -> entry */
const FLOW_DEFINITION_REGISTRY = new Map<string, FlowDefinitionRegistryEntry>();

/** Built-in clinical profile registry: clinicalProfileId -> entry */
const CLINICAL_PROFILE_REGISTRY = new Map<string, ClinicalProfileRegistryEntry>();

// Register region flows
for (const region of REGION_FLOW_IDS) {
  const flowDefinitionId = `builtin.${region}.v1`;
  const clinicalProfileId = `builtin.${region}`;
  FLOW_DEFINITION_REGISTRY.set(flowDefinitionId, {
    flowDefinitionId,
    flowId: region,
    flowVersion: 1,
    firstScreenRoute: "/region-select",
    regionBodyArea: region,
  });
  CLINICAL_PROFILE_REGISTRY.set(clinicalProfileId, {
    clinicalProfileId,
    summaryEngine: region,
    decisionSupportProfile: "region",
    supportsDifferentialHypothesis: true,
  });
}

// General visit
const GENERAL_FLOW_DEFINITION_ID = "builtin.generalVisit.v1";
const GENERAL_CLINICAL_PROFILE_ID = "builtin.generalVisit";
FLOW_DEFINITION_REGISTRY.set(GENERAL_FLOW_DEFINITION_ID, {
  flowDefinitionId: GENERAL_FLOW_DEFINITION_ID,
  flowId: "generalVisit",
  flowVersion: 1,
  firstScreenRoute: "/general-visit-start",
});
CLINICAL_PROFILE_REGISTRY.set(GENERAL_CLINICAL_PROFILE_ID, {
  clinicalProfileId: GENERAL_CLINICAL_PROFILE_ID,
  summaryEngine: "generalVisit",
  decisionSupportProfile: "general",
  supportsDifferentialHypothesis: false,
});

/**
 * Legacy shim: map flowId (and optional flowVersion) to flowDefinitionId + clinicalProfileId.
 * Used when session/draft has no flowDefinitionId/clinicalProfileId (e.g. old docs).
 */
export function legacyFlowIdToRegistry(
  flowId: string,
  flowVersion?: number
): LegacyRegistryResult | null {
  const f = (flowId ?? "").toString().trim().toLowerCase();
  const v = flowVersion ?? 1;

  if (f === "generalvisit" || f === "general_visit" || f === "general-visit") {
    const flowDef = FLOW_DEFINITION_REGISTRY.get(GENERAL_FLOW_DEFINITION_ID);
    const profile = CLINICAL_PROFILE_REGISTRY.get(GENERAL_CLINICAL_PROFILE_ID);
    if (!flowDef || !profile) return null;
    return {
      flowDefinitionId: flowDef.flowDefinitionId,
      clinicalProfileId: profile.clinicalProfileId,
      flowId: flowDef.flowId,
      flowVersion: flowDef.flowVersion,
      summaryEngine: profile.summaryEngine,
      decisionSupportProfile: profile.decisionSupportProfile,
      supportsDifferentialHypothesis: profile.supportsDifferentialHypothesis,
    };
  }

  const flowDefinitionId = `builtin.${f}.v1`;
  const clinicalProfileId = `builtin.${f}`;
  const flowDef = FLOW_DEFINITION_REGISTRY.get(flowDefinitionId);
  const profile = CLINICAL_PROFILE_REGISTRY.get(clinicalProfileId);
  if (!flowDef || !profile) return null;

  return {
    flowDefinitionId: flowDef.flowDefinitionId,
    clinicalProfileId: profile.clinicalProfileId,
    flowId: flowDef.flowId,
    flowVersion: flowDef.flowVersion,
    summaryEngine: profile.summaryEngine,
    decisionSupportProfile: profile.decisionSupportProfile,
    supportsDifferentialHypothesis: profile.supportsDifferentialHypothesis,
  };
}

/**
 * Resolve flow definition by flowDefinitionId.
 */
export function getFlowDefinition(
  flowDefinitionId: string
): FlowDefinitionRegistryEntry | null {
  const id = (flowDefinitionId ?? "").trim();
  return id ? FLOW_DEFINITION_REGISTRY.get(id) ?? null : null;
}

/**
 * Resolve clinical profile by clinicalProfileId.
 */
export function getClinicalProfile(
  clinicalProfileId: string
): ClinicalProfileRegistryEntry | null {
  const id = (clinicalProfileId ?? "").trim();
  return id ? CLINICAL_PROFILE_REGISTRY.get(id) ?? null : null;
}

/**
 * Resolve first screen route for a flow (by flowDefinitionId or legacy flowId).
 */
export function getFirstScreenRoute(
  flowDefinitionId: string | null,
  legacyFlowId?: string
): string {
  if (flowDefinitionId) {
    const entry = getFlowDefinition(flowDefinitionId);
    if (entry) return entry.firstScreenRoute;
  }
  const legacy = legacyFlowId
    ? legacyFlowIdToRegistry(legacyFlowId)
    : null;
  if (legacy) {
    const entry = getFlowDefinition(legacy.flowDefinitionId);
    if (entry) return entry.firstScreenRoute;
  }
  return "/region-select";
}

/**
 * Build intake session snapshot from template + optional override flowId (for booking).
 * If template has flowDefinitionId/clinicalProfileId use them; else use legacy shim from flowId.
 */
export function resolveIntakeSnapshot(params: {
  templateId: string;
  flowDefinitionId?: string | null;
  clinicalProfileId?: string | null;
  flowId?: string | null;
  flowVersion?: number | null;
}): LegacyRegistryResult {
  const flowId = (params.flowId ?? "").toString().trim();
  const flowVersion = params.flowVersion ?? 1;
  const flowDefinitionId = (params.flowDefinitionId ?? "").toString().trim();
  const clinicalProfileId = (params.clinicalProfileId ?? "").toString().trim();

  if (flowDefinitionId && clinicalProfileId) {
    const flowDef = getFlowDefinition(flowDefinitionId);
    const profile = getClinicalProfile(clinicalProfileId);
    if (flowDef && profile) {
      return {
        flowDefinitionId: flowDef.flowDefinitionId,
        clinicalProfileId: profile.clinicalProfileId,
        flowId: flowDef.flowId,
        flowVersion: flowDef.flowVersion,
        summaryEngine: profile.summaryEngine,
        decisionSupportProfile: profile.decisionSupportProfile,
        supportsDifferentialHypothesis: profile.supportsDifferentialHypothesis,
      };
    }
  }

  const legacy = legacyFlowIdToRegistry(
    flowId || "ankle",
    typeof flowVersion === "number" ? flowVersion : 1
  );
  if (legacy) return legacy;

  return legacyFlowIdToRegistry("ankle", 1)!;
}
