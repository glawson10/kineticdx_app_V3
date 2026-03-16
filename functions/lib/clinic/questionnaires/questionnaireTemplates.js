"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.LEGACY_BOOKING_DEFAULT_FLOW_ID = exports.BUILTIN_GENERAL_VISIT_TEMPLATE_ID = exports.BUILTIN_PREASSESSMENT_BOOKING_TEMPLATE_ID = exports.QUESTIONNAIRE_LAUNCH_KIND_ROUTE = exports.QUESTIONNAIRE_LAUNCH_KIND_INTAKE_LINK = exports.QUESTIONNAIRE_LAUNCH_KIND_BOOKING_PREASSESSMENT = exports.QUESTIONNAIRE_TEMPLATE_SOURCE_CUSTOM = exports.QUESTIONNAIRE_TEMPLATE_SOURCE_BUILT_IN = void 0;
exports.builtInQuestionnaireTemplates = builtInQuestionnaireTemplates;
exports.validateQuestionnaireFlow = validateQuestionnaireFlow;
exports.customQuestionnaireTemplateFromDoc = customQuestionnaireTemplateFromDoc;
exports.loadQuestionnaireTemplateById = loadQuestionnaireTemplateById;
exports.buildPublicQuestionnaireFlow = buildPublicQuestionnaireFlow;
exports.listQuestionnaireTemplates = listQuestionnaireTemplates;
const https_1 = require("firebase-functions/v2/https");
exports.QUESTIONNAIRE_TEMPLATE_SOURCE_BUILT_IN = "builtIn";
exports.QUESTIONNAIRE_TEMPLATE_SOURCE_CUSTOM = "custom";
exports.QUESTIONNAIRE_LAUNCH_KIND_BOOKING_PREASSESSMENT = "bookingPreassessment";
exports.QUESTIONNAIRE_LAUNCH_KIND_INTAKE_LINK = "intakeLink";
exports.QUESTIONNAIRE_LAUNCH_KIND_ROUTE = "route";
exports.BUILTIN_PREASSESSMENT_BOOKING_TEMPLATE_ID = "builtin.preassessment.booking";
exports.BUILTIN_GENERAL_VISIT_TEMPLATE_ID = "builtin.generalVisit";
/** PA-P3.1: Legacy fallback when template has no flowDefinitionId/clinicalProfileId (e.g. old custom templates). */
exports.LEGACY_BOOKING_DEFAULT_FLOW_ID = "ankle";
const VALID_TEMPLATE_SOURCES = new Set([
    exports.QUESTIONNAIRE_TEMPLATE_SOURCE_BUILT_IN,
    exports.QUESTIONNAIRE_TEMPLATE_SOURCE_CUSTOM,
]);
const VALID_LAUNCH_KINDS = new Set([
    exports.QUESTIONNAIRE_LAUNCH_KIND_BOOKING_PREASSESSMENT,
    exports.QUESTIONNAIRE_LAUNCH_KIND_INTAKE_LINK,
    exports.QUESTIONNAIRE_LAUNCH_KIND_ROUTE,
]);
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
}
function safeInt(v, fallback) {
    const n = typeof v === "number" ? v : Number(v);
    return Number.isFinite(n) ? Math.trunc(n) : fallback;
}
function isObj(v) {
    return !!v && typeof v === "object" && !Array.isArray(v);
}
function builtInQuestionnaireTemplates() {
    return [
        {
            templateId: exports.BUILTIN_PREASSESSMENT_BOOKING_TEMPLATE_ID,
            source: exports.QUESTIONNAIRE_TEMPLATE_SOURCE_BUILT_IN,
            label: "Specific issue questionnaire",
            description: "Guides the patient into the specific-issue preassessment flow linked to their booking.",
            active: true,
            patientFacing: true,
            launchKind: exports.QUESTIONNAIRE_LAUNCH_KIND_BOOKING_PREASSESSMENT,
            launchRoute: "/preassessment/consent",
            flowId: exports.LEGACY_BOOKING_DEFAULT_FLOW_ID,
            flowVersion: 1,
            flowCategory: "region",
            flowDefinitionId: "builtin.ankle.v1",
            clinicalProfileId: "builtin.ankle",
        },
        {
            templateId: exports.BUILTIN_GENERAL_VISIT_TEMPLATE_ID,
            source: exports.QUESTIONNAIRE_TEMPLATE_SOURCE_BUILT_IN,
            label: "General questionnaire",
            description: "Captures broad visit goals and context before the appointment.",
            active: true,
            patientFacing: true,
            launchKind: exports.QUESTIONNAIRE_LAUNCH_KIND_INTAKE_LINK,
            launchRoute: "/q/launch",
            flowId: "generalVisit",
            flowVersion: 1,
            flowCategory: "general",
            flowDefinitionId: "builtin.generalVisit.v1",
            clinicalProfileId: "builtin.generalVisit",
        },
    ];
}
function normalizeTemplateSource(raw, templateId) {
    const source = safeStr(raw);
    if (VALID_TEMPLATE_SOURCES.has(source))
        return source;
    if (templateId.startsWith("builtin."))
        return exports.QUESTIONNAIRE_TEMPLATE_SOURCE_BUILT_IN;
    return exports.QUESTIONNAIRE_TEMPLATE_SOURCE_CUSTOM;
}
function normalizeLaunchKind(raw) {
    const launchKind = safeStr(raw);
    if (!VALID_LAUNCH_KINDS.has(launchKind)) {
        throw new https_1.HttpsError("invalid-argument", "questionnaire template launchKind is invalid.");
    }
    return launchKind;
}
function validateQuestionnaireFlow(raw) {
    var _a;
    if (!isObj(raw)) {
        return { enabled: false, templates: [] };
    }
    const enabled = raw.enabled === true;
    const templatesRaw = Array.isArray(raw.templates) ? raw.templates : [];
    const seen = new Set();
    const templates = [];
    for (let i = 0; i < templatesRaw.length; i++) {
        const item = templatesRaw[i];
        if (!isObj(item)) {
            throw new https_1.HttpsError("invalid-argument", `questionnaireFlow.templates[${i}] must be an object.`);
        }
        const templateId = safeStr((_a = item.templateId) !== null && _a !== void 0 ? _a : item.id);
        if (!templateId) {
            throw new https_1.HttpsError("invalid-argument", `questionnaireFlow.templates[${i}].templateId is required.`);
        }
        if (seen.has(templateId))
            continue;
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
function sanitizeDescription(raw) {
    const value = safeStr(raw);
    return value ? value : null;
}
function customQuestionnaireTemplateFromDoc(docId, raw) {
    var _a, _b, _c, _d;
    if (!isObj(raw))
        return null;
    const templateId = safeStr(raw.templateId) || safeStr(docId);
    if (!templateId)
        return null;
    const source = normalizeTemplateSource(raw.source, templateId);
    const label = safeStr((_b = (_a = raw.label) !== null && _a !== void 0 ? _a : raw.name) !== null && _b !== void 0 ? _b : raw.title) || templateId;
    const launchKindRaw = safeStr(raw.launchKind);
    if (!launchKindRaw)
        return null;
    let launchKind;
    try {
        launchKind = normalizeLaunchKind(launchKindRaw);
    }
    catch {
        return null;
    }
    return {
        templateId,
        source,
        label: label,
        name: sanitizeDescription((_d = (_c = raw.name) !== null && _c !== void 0 ? _c : raw.label) !== null && _d !== void 0 ? _d : raw.title) || label,
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
async function loadQuestionnaireTemplateById(db, clinicId, templateId) {
    const builtIn = builtInQuestionnaireTemplates().find((t) => t.templateId === templateId);
    if (builtIn)
        return builtIn;
    const snap = await db
        .collection("clinics")
        .doc(clinicId)
        .collection("questionnaireTemplates")
        .doc(templateId)
        .get();
    if (!snap.exists)
        return null;
    return customQuestionnaireTemplateFromDoc(snap.id, snap.data());
}
async function buildPublicQuestionnaireFlow(db, clinicId, raw) {
    const flow = validateQuestionnaireFlow(raw);
    if (!flow.enabled || flow.templates.length === 0) {
        return { enabled: false, templates: [] };
    }
    const resolved = await Promise.all(flow.templates.map((ref) => loadQuestionnaireTemplateById(db, clinicId, ref.templateId)));
    const refByTemplateId = new Map(flow.templates.map((r) => [r.templateId, r]));
    const templates = resolved
        .filter((t) => !!t)
        .filter((t) => t.active && t.patientFacing)
        .map((t) => {
        var _a, _b;
        const ref = refByTemplateId.get(t.templateId);
        const locationIds = (ref === null || ref === void 0 ? void 0 : ref.locationIds) && ref.locationIds.length > 0 ? ref.locationIds : undefined;
        return {
            templateId: t.templateId,
            source: t.source,
            label: t.label,
            description: (_a = t.description) !== null && _a !== void 0 ? _a : null,
            launchKind: t.launchKind,
            launchRoute: (_b = t.launchRoute) !== null && _b !== void 0 ? _b : null,
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
async function listQuestionnaireTemplates(db, clinicId) {
    const builtIn = builtInQuestionnaireTemplates();
    const customSnap = await db
        .collection("clinics")
        .doc(clinicId)
        .collection("questionnaireTemplates")
        .get();
    const custom = customSnap.docs
        .map((d) => customQuestionnaireTemplateFromDoc(d.id, d.data()))
        .filter((t) => t != null);
    const byId = new Map();
    for (const t of builtIn)
        byId.set(t.templateId, t);
    for (const t of custom)
        byId.set(t.templateId, t);
    return Array.from(byId.values());
}
//# sourceMappingURL=questionnaireTemplates.js.map