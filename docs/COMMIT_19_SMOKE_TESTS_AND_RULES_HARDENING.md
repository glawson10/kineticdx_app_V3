# CP-P1 Commit 19: Smoke tests + rules hardening

## Goal

Lock in "function-authoritative settings", prevent regressions, and prove with tests that:

- All settings mutations are callable-only where intended (calendarDisplay, publicBooking, communication, locations, appointmentTypes, clinic profile).
- No client writes to protected paths (`/public/**`, `clinics/*/locations/*`, `clinics/*/appointmentTypes/*`, and selected settings docs).
- Permission gates behave correctly (read vs write vs members perms).
- Audit logs are written for every settings callable mutation with "changed keys only".

---

## 1. What is guaranteed by rules (deny/allow)

| Path | Read | Write |
|------|------|--------|
| `clinics/{clinicId}/public/**` | Anyone | **Deny** (projection-only) |
| `clinics/{clinicId}/locations/*` | `settings.read` | **Deny** (callable-only) |
| `clinics/{clinicId}/appointmentTypes/*` | `settings.read` | **Deny** (callable-only) |
| `clinics/{clinicId}/settings/calendarDisplay` | `settings.read` | **Deny** (callable-only) |
| `clinics/{clinicId}/settings/publicBooking` | `settings.read` | **Deny** (callable-only) |
| `clinics/{clinicId}/settings/communication` | `settings.read` | **Deny** (callable-only) |
| `clinics/{clinicId}/settings/{other}` | `settings.read` | `settings.write` only (e.g. clinic root profile) |
| `clinics/{clinicId}/members/*` | `members.read` or self | **Deny** (function-only) |

---

## 2. What is guaranteed by functions (auth, permission, validation, audit)

- **Auth**: Every settings callable requires `request.auth.uid` (unauthenticated → error).
- **Permission**: Callables use `requireClinicPermission(db, clinicId, uid, "settings.write")` (or equivalent) before mutating.
- **Validation**: Callables validate payloads (e.g. slotStep in allowlist, duration divisible by 5, email format) and return `invalid-argument` on failure.
- **Audit**: Each settings mutation writes to `clinics/{clinicId}/audit` with **changed keys only** (no full doc dumps); `writeSettingsAuditEvent` is called with the patch/changes object.

---

## 3. Commands to run locally

**Start emulators (Firestore + Functions):**

```bash
firebase emulators:start --only firestore,functions
```

In a second terminal:

**Run Functions unit tests (Jest):**

```bash
cd functions && npm test
```

**Run Flutter unit tests:**

```bash
flutter test
```

**Run Firestore rules tests** (requires emulators running; install deps once):

```bash
cd test/firestore_rules && npm install && npm test
```

**Run Commit 19 smoke script** (runs functions tests + rules tests; emulators must be running for rules):

```bash
# From repo root (requires ts-node: npm install -D ts-node, or use from functions folder)
npx ts-node scripts/smoke/commit19_smoke.ts
```

**Run grep guardrails** (see `docs/COMMIT_19_GREP_GUARDS.md`):

Run the exact `rg` commands listed in that doc from repo root to ensure no client writes to protected paths.

---

## 4. Runbook (what to run to verify Commit 19)

1. Start emulators: `firebase emulators:start --only firestore,functions`
2. In another terminal (from repo root):
   - `cd functions && npm test` → all pass
   - `cd test/firestore_rules && npm install && npm test` → rules tests pass
   - Or run the smoke script: `npx ts-node scripts/smoke/commit19_smoke.ts`
3. `flutter test` → app tests pass
4. Optional: run grep guardrails from `docs/COMMIT_19_GREP_GUARDS.md` and confirm no forbidden client writes.

---

## 5. Suggested commit message

```
CP-P1: Commit 19 — Smoke tests + rules hardening
```
