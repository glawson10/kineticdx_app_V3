# Phase 3 → Phase 5 Handoff Contract

## Purpose

This document defines the **formal contract** between:

- **Phase 3** – Intake & Pre-assessment
- **Phase 5** – Clinical episodes & notes

It ensures:
- Legal clarity
- Clinical integrity
- Predictable system behaviour
- Safe future AI integration

---

## Design Rule (Non-negotiable)

> Phase 3 data may **inform** Phase 5  
> Phase 3 data must **never become** Phase 5 data

There is no automatic transformation of intake data into clinical conclusions.

---

## When the Handoff Occurs

The handoff occurs **only** when:
- A clinician creates an **initial clinical note**
- The clinician explicitly links an assessment

There is no background or automatic linking.

---

## What Is Allowed to Transfer

### Allowed (read-only, referenced)
- assessmentId
- completedAt
- region / side
- triageStatus
- Selected subjective answers

### Not allowed
- Diagnoses
- Differentials
- Objective findings
- Treatment recommendations
- AI-generated conclusions

These remain confined to the intake PDF.

---

## Where the Data Appears

Phase 3 data is embedded **only** in the initial note, under a clearly labelled section:

```json
subjective: {
  preAssessment: {
    assessmentId: "abc123",
    completedAt: "...",
    region: "lumbar",
    triage: "amber",
    keyAnswers: {
      painNow: 6,
      nightPain: true,
      onset: "gradual"
    }
  }
}
