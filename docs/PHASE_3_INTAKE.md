# Phase 3 – Intake & Pre-assessment

## Purpose

Phase 3 is the **patient-facing intake and pre-assessment phase** of the platform.

Its purpose is to:
- Collect structured, patient-reported information **before** any clinical reasoning
- Identify safety concerns and triage level
- Prepare clinicians for an initial assessment
- Create a legally defensible, immutable intake record

Phase 3 **does not contain clinical decisions**.

---

## Core Principles

1. **Patient-reported only**
   - All data originates from the patient (or proxy)
   - No clinician interpretation is recorded here

2. **Read-only after submission**
   - Once finalised, assessments cannot be edited
   - Corrections require a new assessment

3. **No clinical reasoning**
   - No diagnoses
   - No treatment plans
   - No SOAP structure

4. **Legally preserved**
   - Every completed assessment generates a PDF snapshot
   - PDFs are immutable and retained per data retention policy

---

## Scope of Data

### Allowed content
- Demographics (limited)
- Region / side selection
- Symptom descriptors
- Pain scales
- Red / amber flag screening
- Functional impact
- Patient goals (free text)
- Triage outcome (green / amber / red)
- Suggested **objective test categories** (not diagnoses)

### Explicitly excluded
- Diagnoses (confirmed or suspected)
- Differential diagnoses
- Clinical impressions
- Objective findings
- Treatment recommendations

---

## Data Model (Conceptual)


Core fields:
- patientId
- region
- answers (structured)
- triageStatus
- completedAt
- pdfUrl
- schemaVersion

---

## Permissions & Security

- Patients: write once, no read after submission
- Clinicians: read-only
- Managers/Admin: read-only
- Writes: **Cloud Functions only**
- Reads: governed by `clinical.read`

---

## Relationship to Later Phases

Phase 3 **informs** clinical care but is **not clinical care**.

It feeds into:
- Phase 5.2 (Episodes) indirectly
- Phase 5.3 (Initial clinical note) selectively

The intake record itself is never modified by later phases.

---

## Summary

Phase 3 creates:
- A frozen intake snapshot
- A medico-legal artefact
- Context for safe assessment

Clinical reasoning begins **only after Phase 3 is complete**.
