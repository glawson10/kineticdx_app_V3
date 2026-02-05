# Cursor House Rules (KineticDx V3)

## Status
Authoritative for AI-assisted changes.
If any suggestion conflicts with these rules, it is invalid.

## Canonical Architecture (non-negotiable)
- Clinic-first tenancy: all sensitive data under `clinics/{clinicId}/...` (no global patients/appointments/notes).
- Zero trust: client/UI is never trusted.
- Firestore rules are law: if rules don’t allow it, the feature does not exist.
- Public vs private separation is absolute:
  - Public users never touch private collections.
  - `/public/**` is projection-only, written by Cloud Functions only.
- Backend authority:
  - Membership/invites are function-only writes.
  - Scheduling writes (appointments) are function-only writes.
  - Audit logs are append-only and function-only.

## Phase boundaries (non-negotiable)
- Phase 3 intake is patient-reported, immutable after submission.
- Phase 3 may inform Phase 5, but must never become Phase 5 automatically.
- No automatic transformation of intake into diagnoses, objective findings, treatments, or SOAP conclusions.
- Phase 5 linking to intake is explicit clinician action only.

## Time + scheduling rules (non-negotiable)
- Store schedule-critical times as Firestore Timestamp (e.g., startAt/endAt, closures).
- Clinic timezone lives in `clinics/{clinicId}.profile.timezone`.
- Opening hours / corporate availability must follow OPENING_HOURS_CONTRACT.md.
- Clients must not hardcode opening hours or compute authoritative availability.

## Intake questionId rules (non-negotiable)
- Canonical format: `{flowId}.{domain}.{concept}[.{detail}]`
- No UI-step IDs; no meaning changes; no type changes.
- Store stable optionIds (never UI labels).

## What Cursor is allowed to do
✅ Allowed:
- Refactor within a file or feature boundary while preserving contracts.
- Add tests, validation, and guardrails that enforce the rules above.
- Improve readability/structure without changing data model semantics.

## What Cursor is NOT allowed to do
❌ Forbidden:
- Introduce global collections for clinic data.
- Add client writes to function-only collections.
- Add any client writes under `/public/**`.
- Bypass Firestore rules or “secure in UI”.
- Auto-populate Phase 5 from Phase 3 or from decision-support outputs.
- Change schema meaning or questionId meaning without a documented migration + schemaVersion bump.

## Required workflow for any non-trivial change
1) State what files will change.
2) List invariants that must remain true (clinic scoping, function-only writes, phase boundary, etc.).
3) Show the diff or describe changes precisely.
4) Identify any required rule/index updates.
5) Call out any migration impacts (schemaVersion, dual-read, backfill).
