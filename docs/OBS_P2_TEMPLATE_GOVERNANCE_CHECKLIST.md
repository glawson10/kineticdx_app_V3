# OBS-P2: Template governance checklist

| Item | Status |
|------|--------|
| Template list screen in settings/admin (built-in + clinic, active, patientFacing, category, version, selectable-in-booking) | **Implemented** |
| Lightweight metadata editor for clinic templates (name, description, active, patientFacing, category; non-editable templateId, version, flowDefinitionId, clinicalProfileId) | **Implemented** |
| Validation: prevent invalid save when required metadata missing | **Implemented** |
| Validation: templateId uniqueness for clinic-scoped templates | **Implemented** (updates only; creation deferred; uniqueness guaranteed by doc ID) |
| Clear separation built-in vs clinic in list and editor | **Implemented** |

## Notes

- **List screen:** Settings → Communication → Questionnaire templates. Two sections: "Built-in templates" and "Clinic templates". Each card shows active, patientFacing, category, version, and "In use in Online booking" when the template is in the clinic's public booking questionnaire flow.
- **Metadata editor:** Edit action on clinic template cards opens a dialog with editable name, description, category, active, patientFacing; read-only templateId, version, flowDefinitionId, clinicalProfileId.
- **Validation:** `updateQuestionnaireTemplateFn` requires non-empty label for clinic templates; rejects empty label with `invalid-argument`.
- **templateId uniqueness:** Clinic templates live at `clinics/{clinicId}/questionnaireTemplates/{templateId}`. No create callable in this phase; updates target existing docs. Uniqueness is guaranteed by document ID. If a create path is added later, it must check that no doc exists at that templateId before creating.
