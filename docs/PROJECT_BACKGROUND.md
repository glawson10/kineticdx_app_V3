# Project Background – KineticDx V3

## What this is
A multi-tenant, clinic-scoped, security-first clinical platform built on:
- Firebase Auth
- Firestore
- Cloud Functions
- Flutter (client)

This system handles patient intake, scheduling, and clinical documentation.
Mistakes can have legal and clinical consequences.

## Non-negotiables
- Clinic-first tenancy (no global patient data)
- Firestore rules are law
- Function-authoritative writes for sensitive data
- Public vs private separation is absolute
- Phase 3 intake is immutable after submission
- Phase 3 may inform Phase 5 but never becomes it

## Authoritative documents
Read these before making changes:

1) ARCHITECTURE_V3.md  
2) CURSOR_HOUSE_RULES.md  
3) PHASE_3_INTAKE.md  
4) PHASE_3_TO_5_HANDOFF.md  
5) OPENING_HOURS_CONTRACT.md  
6) QUESTION_ID_RULES.md

If a suggestion conflicts with these documents, it is invalid.
