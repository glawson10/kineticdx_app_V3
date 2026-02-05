# Change Checklist

This checklist is used to prevent architectural drift when accepting
Cursor (or any AI-assisted) changes.

There are two passes:
- **Quick accept (30 seconds)** — run before accepting Cursor output
- **Before merge / deploy** — run before committing or deploying

If a check fails, stop and redesign using Cloud Functions, Firestore rules,
or a schema-compatible approach.

---

## Quick accept (30 seconds)

Run this immediately after Cursor proposes a change.

- [ ] Does every **private** read/write remain clinic-scoped  
      (`clinics/{clinicId}/...`)?
- [ ] Did Cursor accidentally add **client writes** to:
  - appointments
  - memberships / invites
  - audit logs
  - anything under `/public/**`?
- [ ] Did the change blur **Phase 3 → Phase 5** boundaries  
      (auto-import, auto-conclusions, auto-populated notes)?
- [ ] Did the UI hardcode **opening hours, availability, or business rules**?

If **any** answer is “yes” → stop and redesign via **Cloud Functions + rules**.

---

## Before merge / deploy (must pass)

### 1) Security & tenancy

- [ ] All private reads and writes are scoped under  
      `clinics/{clinicId}/...`
- [ ] No new global collections for clinical or business data  
      (e.g. `/patients`, `/appointments`, `/notes`)
- [ ] Function-authoritative collections remain function-only:
  - appointments
  - memberships
  - invites
  - audit logs
  - public mirrors
- [ ] Firestore rules still enforce all access  
      (nothing relies on “trusted UI”)

---

### 2) Function-only write enforcement

- [ ] Flutter/client code does **not** write directly to:
  - appointments
  - memberships or invites
  - audit logs
  - `/public/**`
- [ ] Sensitive writes occur only via Cloud Functions
- [ ] Functions validate:
  - membership
  - permissions
  - clinic ownership
  - input shape

---

### 3) Phase boundaries (legal & clinical safety)

- [ ] Phase 3 intake remains **immutable after submission**
- [ ] Phase 3 data may inform Phase 5, but **never becomes it**
- [ ] No automatic transformation of:
  - intake answers
  - summaries
  - decision support
  into diagnoses, SOAP sections, or treatment plans
- [ ] Any Phase 3 → Phase 5 linkage is an **explicit clinician action**

---

### 4) Scheduling & time rules

- [ ] Schedule-critical times are stored as Firestore `Timestamp`
  - `startAt`, `endAt`
  - closures
  - expiry times
- [ ] UI does not compute or hardcode opening hours or availability
- [ ] Public booking reads from **public mirrors only**
- [ ] Public mirrors are written by **Cloud Functions only**

---

### 5) Compatibility & schema discipline

- [ ] No existing `questionId` meaning has changed
- [ ] No existing `questionId` type has changed
- [ ] New questions use new IDs + (if needed) `flowVersion` bump
- [ ] No silent schema changes
- [ ] Any breaking change:
  - increments `schemaVersion`
  - documents a migration strategy
  - preserves backward-compatible reads

---

## Definition of done

A change is safe to merge/deploy only if:

- Quick accept passes
- All sections above pass
- The system remains:
  - clinic-scoped
  - rules-enforced
  - function-authoritative
  - phase-boundary safe
