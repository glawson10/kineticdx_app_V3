"use strict";
/**
 * PA-P3: Registry-driven intake dispatch.
 * Flow definition and clinical profile registries + legacy flowId shim.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.legacyFlowIdToRegistry = legacyFlowIdToRegistry;
exports.getFlowDefinition = getFlowDefinition;
exports.getClinicalProfile = getClinicalProfile;
exports.getFirstScreenRoute = getFirstScreenRoute;
exports.resolveIntakeSnapshot = resolveIntakeSnapshot;
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
];
/** Built-in flow definition registry: flowDefinitionId -> entry */
const FLOW_DEFINITION_REGISTRY = new Map();
/** Built-in clinical profile registry: clinicalProfileId -> entry */
const CLINICAL_PROFILE_REGISTRY = new Map();
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
function legacyFlowIdToRegistry(flowId, flowVersion) {
    const f = (flowId !== null && flowId !== void 0 ? flowId : "").toString().trim().toLowerCase();
    const v = flowVersion !== null && flowVersion !== void 0 ? flowVersion : 1;
    if (f === "generalvisit" || f === "general_visit" || f === "general-visit") {
        const flowDef = FLOW_DEFINITION_REGISTRY.get(GENERAL_FLOW_DEFINITION_ID);
        const profile = CLINICAL_PROFILE_REGISTRY.get(GENERAL_CLINICAL_PROFILE_ID);
        if (!flowDef || !profile)
            return null;
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
    if (!flowDef || !profile)
        return null;
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
function getFlowDefinition(flowDefinitionId) {
    var _a;
    const id = (flowDefinitionId !== null && flowDefinitionId !== void 0 ? flowDefinitionId : "").trim();
    return id ? (_a = FLOW_DEFINITION_REGISTRY.get(id)) !== null && _a !== void 0 ? _a : null : null;
}
/**
 * Resolve clinical profile by clinicalProfileId.
 */
function getClinicalProfile(clinicalProfileId) {
    var _a;
    const id = (clinicalProfileId !== null && clinicalProfileId !== void 0 ? clinicalProfileId : "").trim();
    return id ? (_a = CLINICAL_PROFILE_REGISTRY.get(id)) !== null && _a !== void 0 ? _a : null : null;
}
/**
 * Resolve first screen route for a flow (by flowDefinitionId or legacy flowId).
 */
function getFirstScreenRoute(flowDefinitionId, legacyFlowId) {
    if (flowDefinitionId) {
        const entry = getFlowDefinition(flowDefinitionId);
        if (entry)
            return entry.firstScreenRoute;
    }
    const legacy = legacyFlowId
        ? legacyFlowIdToRegistry(legacyFlowId)
        : null;
    if (legacy) {
        const entry = getFlowDefinition(legacy.flowDefinitionId);
        if (entry)
            return entry.firstScreenRoute;
    }
    return "/region-select";
}
/**
 * Build intake session snapshot from template + optional override flowId (for booking).
 * If template has flowDefinitionId/clinicalProfileId use them; else use legacy shim from flowId.
 */
function resolveIntakeSnapshot(params) {
    var _a, _b, _c, _d;
    const flowId = ((_a = params.flowId) !== null && _a !== void 0 ? _a : "").toString().trim();
    const flowVersion = (_b = params.flowVersion) !== null && _b !== void 0 ? _b : 1;
    const flowDefinitionId = ((_c = params.flowDefinitionId) !== null && _c !== void 0 ? _c : "").toString().trim();
    const clinicalProfileId = ((_d = params.clinicalProfileId) !== null && _d !== void 0 ? _d : "").toString().trim();
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
    const legacy = legacyFlowIdToRegistry(flowId || "ankle", typeof flowVersion === "number" ? flowVersion : 1);
    if (legacy)
        return legacy;
    return legacyFlowIdToRegistry("ankle", 1);
}
//# sourceMappingURL=flowRegistry.js.map