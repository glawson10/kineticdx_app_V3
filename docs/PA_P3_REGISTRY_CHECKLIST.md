# PA-P3 Registry-Driven Intake Dispatch – Implementation Checklist

## Post-implementation checklist

| Item | Status |
|------|--------|
| **Fully generalized** | Routing uses `flowDefinitionId` / registry (`getFirstScreenRoute`, `resolveFlowFromRegistry`). Summary uses `summaryEngine` / clinical profile. Decision support uses clinical profile and `supportsDifferentialHypothesis`. |
| **Still hardcoded** | Built-in registry maps (`flowDefinitionId` → flow, `clinicalProfileId` → profile) remain in code ([`flowRegistry.ts`](../functions/src/clinic/intake/flowRegistry.ts), [`flow_registry.dart`](../lib/preassessment/domain/flow_registry.dart)). Only *dispatch* is registry-driven; custom templates point at these built-in ids. |
| **Legacy fallback** | Sessions/drafts without `flowDefinitionId` / `clinicalProfileId` resolve via `legacyFlowIdToRegistry(flowId, flowVersion?)` in TS and `legacyFlowIdToFlowDefinitionId` / `resolveFlowFromRegistry` in Dart. `generateIntakeSummaryFn` and `computeDecisionSupport` use snapshot engine or legacy-derived engine. |

---

## Differential diagnosis after refactor

**Do differential diagnosis hypotheses still work?**  
Yes. Region flows (ankle, cervical, elbow, hip, knee, lumbar, shoulder, thoracic, wrist) still produce `diagnosticHypotheses` in the decision support doc because their clinical profile has `supportsDifferentialHypothesis: true`.

**Controlling metadata**  
The behaviour is controlled by the **clinical profile** field **`supportsDifferentialHypothesis`** (and its snapshot on the intake session):

- **`supportsDifferentialHypothesis: true`** (all built-in region profiles) → summary is run, `mapSummaryToDecisionSupport(summary)` is used, and `diagnosticHypotheses` are written.
- **`supportsDifferentialHypothesis: false`** (e.g. `builtin.generalVisit`) → `diagnosticHypotheses` and `recommendedTests` are forced to `[]` in the decision support doc (summary may still run for narrative).

Defined in:

- [`functions/src/clinic/intake/flowRegistry.ts`](../functions/src/clinic/intake/flowRegistry.ts): `ClinicalProfileRegistryEntry.supportsDifferentialHypothesis`; region profiles `true`, general visit `false`.
- [`functions/src/clinic/intake/computeDecisionSupport.ts`](../functions/src/clinic/intake/computeDecisionSupport.ts): `supportsDifferentialHypothesis` is read from session snapshot or profile and used to decide whether to populate `diagnosticHypotheses` and `recommendedTests`.
