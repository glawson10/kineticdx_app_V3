# PA-P3.1, CBO-P3, OBS-P2 Implementation Report

## 1. PA-P3.1 — Registry-driven intake cleanup

### Implemented
- **Task 1.1 — intake_flow_host fully flow-definition-driven:** Route graph is built from the registry. `flow_registry.dart` now exports `getAllIntakeHostRouteNames()`, `getPostPatientDetailsRouteNames()`, and `getScreenKeyForPostDetailsRoute(routeName)`. `intake_flow_host.dart` builds a static map of route → `WidgetBuilder` from these; `onGenerateRoute` does a single map lookup. No hardcoded `/general-visit-start` or fixed route list in the host.
- **Task 1.2 — Remove hardcoded flowId "ankle" default:** Built-in preassessment booking template now has `flowDefinitionId: "builtin.ankle.v1"` and `clinicalProfileId: "builtin.ankle"`. `createIntakeSessionForAppointment` accepts `templateId` only, loads the template via `loadQuestionnaireTemplateById`, and resolves the snapshot from template `flowDefinitionId`/`clinicalProfileId`; legacy fallback uses the named constant `LEGACY_BOOKING_DEFAULT_FLOW_ID` only when the template has no registry ids. Call site no longer passes any `flowId`.
- **Task 1.3 — Isolate dual-link generation:** `shouldCreateDualLinksForBooking(clinicId, templateId)` and `createLegacyDualBookingLinks(...)` were added. The main flow loads the template, creates the session, then either calls `createLegacyDualBookingLinks` (when `shouldCreateDualLinksForBooking` is true) or creates only the link(s) implied by the template’s `launchKind` (preassessment and/or general questionnaire).
- **Task 1.4 — Snapshot completeness:** Confirmed. Session write in `createIntakeSessionForAppointment` already sets `templateId`, `flowDefinitionId`, `clinicalProfileId`, `flowId`, `flowVersion`, `flowCategory`, `summaryEngine`, `decisionSupportProfile`, `supportsDifferentialHypothesis`. Consumers use the snapshot with legacy fallback when fields are missing; no reader re-resolves from template when the snapshot is present.

### Partially implemented
- None.

### Not implemented
- None.

### Remaining legacy fallbacks
- **Dual-link:** When `shouldCreateDualLinksForBooking(clinicId, templateId)` returns `true` (currently always), both preassessment invite and general questionnaire link are created via `createLegacyDualBookingLinks`. Set to `false` and use template `launchKind` when you want template-only link creation.
- **Snapshot:** In `resolveIntakeSnapshot` (flowRegistry.ts), when the template has no `flowDefinitionId`/`clinicalProfileId`, the legacy path uses `LEGACY_BOOKING_DEFAULT_FLOW_ID` ("ankle") and `legacyFlowIdToRegistry`. Same fallback remains for existing sessions/drafts that lack registry ids.

---

## 2. CBO-P3 — Premium booking polish

### Implemented
- **Task 2.1 — Stale request protection:** Already present. `_requestToken` is used in both `_loadSlots` and `_loadMonthAvailability`; responses are ignored when `token != _requestToken`.
- **Task 2.2 — Animated slot transitions:** The entire times panel body (no clinician, loading, error, empty, slot grid) is wrapped in a single `AnimatedSwitcher` (200 ms, fade + slide). Key includes `selectedDay`, `practitionerId`, `loadingSlots`, and `slotsError` so all state changes animate.
- **Task 2.3 — Loading placeholders:** Already present. `_LoadingPlaceholderGrid` uses the same grid layout and `SlotTile` dimensions as the real slot grid; no layout jump.
- **Task 2.4 — Selected day anchoring:** Under “Available times” and the formatted selected date, a second line was added: “Choose a time” when slots exist, “No times available for this day” when the day has no slots (and not loading, no error).
- **Task 2.5 — Hover/focus polish:** `SlotTile` already has `MouseRegion`, `Focus`/`FocusNode`, and border/emphasis on hover and focus. No change. Calendar uses Material `CalendarDatePicker`; no custom day builder or extra hover/focus added.
- **Task 2.6 — Legend clarity:** `InlineMonthCalendarLegend` was upgraded to three density levels: 1 dot = 1–2 slots, 2 dots = 3–5 slots, 3 dots = 6+ slots. The calendar itself still does not render dots in day cells (would require a custom calendar or `TableCalendar`).

### Partially implemented
- None.

### Not implemented
- None.

### Deferred items
- **Task 2.7 — Keyboard navigation (days):** Arrow keys to change selected day and Enter to select were not implemented. `CalendarDatePicker` does not expose a focusable day list; adding this would require a custom calendar or a separate focusable control. Marked as **Deferred**.

---

## 3. OBS-P2 — Template governance

### Implemented
- **Task 3.1 — Registry contract completeness:** Template model now supports optional `name` (alias for label), `version`, and `category`. `QuestionnaireTemplateSummary` and `customQuestionnaireTemplateFromDoc` include them; built-ins use `label` (name derived where needed).
- **Task 3.2 — Clinic-scoped template source:** Confirmed. Custom templates are read from `clinics/{clinicId}/questionnaireTemplates/{templateId}` in `loadQuestionnaireTemplateById` and in `listQuestionnaireTemplates`. Documented in code and in this report.
- **Task 3.3 — Template list screen scaffold:** Added `listQuestionnaireTemplatesFn` and `updateQuestionnaireTemplateFn` (callables). Added `QuestionnaireTemplatesListScreen` under Settings → Communication → “Questionnaire templates”. The screen lists templates (built-in + custom), shows templateId, label, description, active, patientFacing, flowDefinitionId, clinicalProfileId. Active and patient-facing toggles are shown; for custom templates, toggles call `updateQuestionnaireTemplateFn` (built-in templates are read-only in the UI).

### Partially implemented
- None.

### Not implemented
- None.

### Deferred items
- None. Full template editor was out of scope; list + toggles only as planned.

---

## 4. Confirmations

- **Intake hosting is now fully flow-definition-driven:** Yes. The host’s route set is derived from `getAllIntakeHostRouteNames()` and `getPostPatientDetailsRouteNames()`; screen resolution uses `getScreenKeyForPostDetailsRoute(routeName)` and a fixed map of screen key → builder. No hardcoded route path list or `/general-visit-start` literal in routing logic.
- **Any hardcoded flowId defaults still remain:** Only in the **named compatibility layer**. The booking-linked intake creation path no longer passes `flowId`. The constant `LEGACY_BOOKING_DEFAULT_FLOW_ID` ("ankle") is used only inside `createIntakeSessionForAppointment` when the loaded template has no `flowDefinitionId`/`clinicalProfileId`, and inside `resolveIntakeSnapshot` (flowRegistry.ts) when resolving from legacy flowId. No call site passes `flowId: "ankle"` or any other literal.
- **Differential hypothesis behavior is controlled by profile metadata:** Yes. `supportsDifferentialHypothesis` (and snapshot/profile) controls whether differential hypotheses and recommended tests are produced; no route or flow-id switch in the host or in decision-support logic.
