# PA-P3 Registry-Driven Intake Dispatch – Verification Checklist

Each item is marked as **Implemented**, **Partially implemented**, or **Not implemented** based on codebase verification.

---

## Registry

| Item | Status | Notes |
|------|--------|--------|
| Questionnaire templates resolve by templateId | **Implemented** | `loadQuestionnaireTemplateById(db, clinicId, templateId)` in `questionnaireTemplates.ts`; built-ins matched by `templateId`, custom from `clinics/{clinicId}/questionnaireTemplates/{templateId}`. |
| Flow definitions resolve by flowDefinitionId | **Implemented** | `getFlowDefinition(flowDefinitionId)` in `flowRegistry.ts`; built-in map `FLOW_DEFINITION_REGISTRY` keyed by `flowDefinitionId`. Dart: `getFlowDefinitionByRegistryId(flowDefinitionId)` in `flow_registry.dart`. |
| Clinical profiles resolve by clinicalProfileId | **Implemented** | `getClinicalProfile(clinicalProfileId)` in `flowRegistry.ts`; built-in map `CLINICAL_PROFILE_REGISTRY` keyed by `clinicalProfileId`. |
| Intake session snapshot stores template + flow + clinical profile metadata | **Implemented** | `IntakeFlowSnapshot` in `intake_schema.dart` and session docs hold `templateId`, `flowDefinitionId`, `clinicalProfileId`, `flowId`, `flowVersion`, `summaryEngine`, `decisionSupportProfile`, `supportsDifferentialHypothesis`. Snapshot written in `resolveIntakeLinkTokenFn`, `createIntakeSessionForAppointment`, and `submitIntakeSession`. Plan’s “hypothesisProfile” / “clinicalMode” are represented by `supportsDifferentialHypothesis` and `decisionSupportProfile`. |

---

## Routing

| Item | Status | Notes |
|------|--------|--------|
| _nextRouteForFlow replaced by flow-definition-based routing | **Implemented** | `patient_details_screen.dart`: `_nextRouteForFlow` now uses `getFirstScreenRoute(flowDefinitionId: ..., legacyFlowId: ...)` from `flow_registry.dart`; no hardcoded string branch. |
| _flowForBodyArea replaced by flow-definition/profile resolution | **Implemented** | `review_screen.dart`: `_flowForBodyArea` removed; flow resolution is via `resolveFlowFromRegistry(flowDefinitionId, legacyFlowId, bodyArea)`. |
| _resolveFlow replaced by registry lookup | **Implemented** | `review_screen.dart`: `_resolveFlow(draft)` calls `resolveFlowFromRegistry(...)` with `draft.session.flowSnapshot.flowDefinitionId` and legacy `meta.flowId` / `bodyArea`. |
| intake_flow_host.dart uses flow-definition-driven route graph | **Partially implemented** | Route *list* is still a fixed `switch (settings.name)` with `/consent`, `/patient-details`, `/region-select`, `/general-visit-start`. The *choice* of next route (patient-details → region-select vs general-visit-start) is registry-driven in `PatientDetailsScreen`. Full route graph from flow definitions (e.g. dynamic routes) is not implemented. |
| No hardcoded /general-visit-start assumptions remain | **Implemented** | The path `/general-visit-start` is the value of `firstScreenRoute` for `builtin.generalVisit.v1` in the registry (`flow_registry.dart`, `flowRegistry.ts`). Branching logic uses `getFirstScreenRoute()`; no literal “if generalVisit then /general-visit-start” in routing code. |

---

## Booking-linked intake creation

| Item | Status | Notes |
|------|--------|--------|
| onBookingRequestCreate.ts no longer hardcodes flowId: "ankle" | **Partially implemented** | `createIntakeSessionForAppointment` is called with `flowId: "ankle"` at the single call site (default for booking). The *session document* is no longer only `flowId: "ankle"`: it gets a full registry snapshot via `resolveIntakeSnapshot(...)`, so stored fields are `flowDefinitionId`, `clinicalProfileId`, `summaryEngine`, etc. The default *input* for booking-created sessions remains “ankle”; the session content is registry-driven. |
| Session creation copies template/flow/profile snapshot fields | **Implemented** | `createIntakeSessionForAppointment` writes `flowDefinitionId`, `clinicalProfileId`, `templateId`, `summaryEngine`, `decisionSupportProfile`, `supportsDifferentialHypothesis` (and `flowId`, `flowVersion`, `flowCategory`) from `resolveIntakeSnapshot`. |
| Launch URLs/tokens derive from template metadata | **Implemented** | `createQuestionnaireLaunchLinkFn` stores `flowDefinitionId`, `clinicalProfileId` on the link from the template. `resolveIntakeLinkTokenFn` builds snapshot from link/template and returns `flowDefinitionId`, `clinicalProfileId`, `summaryEngine`, etc.; draft payload and response include snapshot fields. |
| Unconditional generation of preassessment/general links is removed or isolated as legacy fallback | **Not implemented** | Preassessment invite and general questionnaire link are still created unconditionally on booking approval (`createIntakeInvite`, `createGeneralQuestionnaireLink`). No change to this behaviour; plan explicitly said “Do NOT change booking UX/config logic” and to limit changes to intake session creation and PA flow/summary/DS. |

---

## Clinical interpretation

| Item | Status | Notes |
|------|--------|--------|
| generateIntakeSummaryFn.ts no longer switches on flowId | **Implemented** | Dispatches on `summaryEngine` (from snapshot or `legacyFlowIdToRegistry(flowId)`). `switch (summaryEngine)` with cases for region engines and `generalVisit`. |
| computeDecisionSupport.ts no longer switches on flowId | **Implemented** | Dispatches on `summaryEngine` (from snapshot or legacy/profile). `switch (summaryEngine)`; profile/snapshot used for `supportsDifferentialHypothesis`. |
| Summary resolution is profile-driven | **Implemented** | Summary engine comes from session `summaryEngine` or from legacy/profile (`legacyFlowIdToRegistry` / `getClinicalProfile`). |
| Decision support resolution is profile-driven | **Implemented** | Clinical profile (from snapshot `clinicalProfileId` or legacy) supplies `supportsDifferentialHypothesis`; engine dispatch uses `summaryEngine`. |
| Differential hypothesis is only generated when clinicalMode / profile supports it | **Implemented** | `computeDecisionSupport.ts`: `diagnosticHypotheses` and `recommendedTests` are set to `[]` when `supportsDifferentialHypothesis === false`; otherwise from `mapSummaryToDecisionSupport(summary)`. Profile field `supportsDifferentialHypothesis` (and snapshot) controls this. |

---

## Safety

| Item | Status | Notes |
|------|--------|--------|
| Phase 3 intake remains immutable | **Implemented** | `submitIntakeSession.ts` idempotency: if `submittedAt` or `status === "submitted"`, transaction returns without changes. No code path allows editing a submitted intake. |
| Canonical question ID contract is preserved | **Implemented** | No schema or questionId changes in PA-P3; flow definitions and registry reference existing flows and question IDs. |
| Layer B remains non-diagnostic and clinician-facing only | **Implemented** | Decision support and summary are unchanged in role: informational, clinician-facing; no auto-diagnosis or Phase 5 write from intake. |
| No decision support output is auto-written into Phase 5 | **Implemented** | Decision support is written to `decisionSupport` subcollection; no logic writes DS into Phase 5 (episode/clinical note) documents. |

---

## Backward compatibility

| Item | Status | Notes |
|------|--------|--------|
| Legacy flowId values still resolve through compatibility mapping | **Implemented** | `legacyFlowIdToRegistry(flowId, flowVersion?)` in `flowRegistry.ts`; `legacyFlowIdToFlowDefinitionId(flowId)` and `resolveFlowFromRegistry(..., legacyFlowId, bodyArea)` in `flow_registry.dart`. Used when session/draft lacks `flowDefinitionId`/`clinicalProfileId`. |
| Existing built-in templates still work without data loss | **Implemented** | Built-ins have default `flowDefinitionId`/`clinicalProfileId` (e.g. general visit). Legacy sessions with only `flowId`/`flowVersion` are resolved via shim in summary and decision support. |
| New custom templates can become first-class without new hardcoded switches | **Implemented** | Custom templates with `flowDefinitionId` and `clinicalProfileId` are supported; routing and summary/DS dispatch by registry/snapshot. Adding a new template that points at an existing built-in profile does not require new switch cases. New *engine* types would still require new cases in the summaryEngine switch (by design). |

---

## Summary

- **Implemented:** 22 items  
- **Partially implemented:** 2 items (intake_flow_host route graph; onBookingRequestCreate call-site default)  
- **Not implemented:** 1 item (unconditional preassessment/general link generation; left unchanged per plan scope)
