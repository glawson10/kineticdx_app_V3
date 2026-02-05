Below is a **clean, copy-paste–ready Markdown file** you can store in your repo as:

```
OPENING_HOURS_CONTRACT.md
```

It incorporates **opening hours + corporate days/codes** in a way that is fully V3-compliant, future-proof, and unambiguous.

---

```md
# Opening Hours & Corporate Availability Contract (V3)

## Status
**Authoritative – non-negotiable**

This document defines the canonical contract for:
- Clinic opening hours
- Public and clinic calendar availability
- Corporate-only days and access codes

All scheduling behavior must conform to this contract.

This contract is aligned with the V3 clinic-scoped, function-authoritative architecture.

---

## 1. Core principles

1. **Single source of truth**
   - Opening hours are defined once and only once.
   - All calendars derive availability from the same engine.

2. **Clinic-scoped**
   - Every read and write is scoped under `clinics/{clinicId}`.

3. **Function-authoritative**
   - Clients never compute or invent availability rules.
   - Clients never write to `/public/**`.

4. **Public vs private is absolute**
   - Sensitive configuration (e.g. corporate codes) never appears in public mirrors.

---

## 2. Source of truth

### 2.1 Private, clinician-editable (authoritative)

```

clinics/{clinicId}/settings/publicBooking

```

- Editable by clinic staff with permission.
- Contains the canonical definition of opening hours and corporate programs.

### 2.2 Public mirror (read-only projection)

```

clinics/{clinicId}/public/config/publicBooking

```

- Written by Cloud Functions only.
- Read by:
  - Public booking UI
  - Clinic booking calendar
  - Availability engine

Clients must never read opening hours from any other path.

---

## 3. Canonical opening hours model

### 3.1 Day keys (fixed set)

```

mon, tue, wed, thu, fri, sat, sun

````

These keys are used everywhere (storage, projection, availability engine).

---

### 3.2 Weekly hours shape (canonical)

Opening hours are defined as **weekly recurring intervals**.

```ts
weeklyHours: Record<
  "mon"|"tue"|"wed"|"thu"|"fri"|"sat"|"sun",
  Array<{ start: "HH:mm"; end: "HH:mm" }>
>
````

Rules:

* `start` and `end` use 24h time (`HH:mm`)
* `end` must be strictly after `start`
* Multiple intervals per day are allowed
* A day is **closed** if its array is empty or missing

Example:

```json
"weeklyHours": {
  "mon": [{"start":"08:00","end":"12:00"},{"start":"13:00","end":"18:00"}],
  "tue": [{"start":"08:00","end":"18:00"}],
  "sun": []
}
```

---

### 3.3 Timezone (required)

* Clinic timezone is stored at:

  ```
  clinics/{clinicId}.profile.timezone
  ```
* Opening hours are interpreted in this timezone.
* All stored appointment times remain Firestore `Timestamp` (UTC-neutral).

The public mirror must include a resolved `timezone` field.

---

## 4. Document schemas

### 4.1 Private source document (minimum required)

```
clinics/{clinicId}/settings/publicBooking
```

```json
{
  "timezone": "Europe/Prague",
  "weeklyHours": {
    "mon": [{"start":"08:00","end":"18:00"}],
    "tue": [{"start":"08:00","end":"18:00"}]
  },
  "slotStepMinutes": 15,
  "minNoticeMinutes": 120,
  "maxAdvanceDays": 90,
  "corporatePrograms": [],
  "schemaVersion": 1,
  "updatedAt": "serverTimestamp"
}
```

---

### 4.2 Public mirror document (minimum required)

```
clinics/{clinicId}/public/config/publicBooking
```

```json
{
  "clinicId": "...",
  "timezone": "Europe/Prague",
  "weeklyHours": {
    "mon": [{"start":"08:00","end":"18:00"}],
    "tue": [{"start":"08:00","end":"18:00"}]
  },
  "slotStepMinutes": 15,
  "minNoticeMinutes": 120,
  "maxAdvanceDays": 90,
  "corporatePrograms": [],
  "services": [],
  "bookingRules": {},
  "schemaVersion": 1,
  "updatedAt": "serverTimestamp",
  "updatedBy": "settings-trigger"
}
```

Public mirror constraints:

* No secrets
* No static codes
* No patient or clinician data

---

## 5. Corporate availability (additive layer)

Corporate programs **do not modify opening hours**.

They act as a **secondary filter** applied after opening hours and before slot visibility.

---

### 5.1 Corporate program (private, authoritative)

Stored only in:

```
clinics/{clinicId}/settings/publicBooking
```

```json
{
  "corpSlug": "acme",
  "displayName": "ACME Employees",
  "mode": "CODE_UNLOCK",
  "days": ["2026-01-12", "2026-01-19"],
  "serviceIdsAllowed": ["initial", "followup"],
  "practitionerIdsAllowed": ["p1"],
  "staticCode": "SECRET123"
}
```

Rules:

* `days` are **YYYY-MM-DD in clinic timezone**
* `mode`:

  * `LINK_ONLY`: access granted by URL alone
  * `CODE_UNLOCK`: access requires valid code
* `staticCode` **must never be mirrored publicly**

---

### 5.2 Corporate program (public mirror subset)

Mirrored to:

```
clinics/{clinicId}/public/config/publicBooking
```

```json
{
  "corpSlug": "acme",
  "displayName": "ACME Employees",
  "mode": "CODE_UNLOCK",
  "days": ["2026-01-12", "2026-01-19"],
  "serviceIdsAllowed": ["initial", "followup"],
  "practitionerIdsAllowed": ["p1"]
}
```

Hard rule:

* Public mirror must never contain `staticCode` or equivalent secrets.

---

## 6. Corporate code validation

Corporate codes must **not** be validated using public mirror data.

### Correct pattern

* A dedicated Cloud Function:

  ```
  resolveCorporateAccess(clinicId, corpSlug, corpCode)
  ```
* Reads **private settings**
* Validates `staticCode`
* Returns `{ unlocked: boolean }` or a short-lived access token
* Does not leak the code

The availability engine trusts only server-validated access.

---

## 7. Availability engine contract

Both **public calendar** and **clinic calendar** must use the same availability engine.

### Required inputs

* `clinicId`
* `rangeStartMs`, `rangeEndMs`
* optional `practitionerId`
* optional `corpSlug` + validated access context

### Required reads

* `public/config/publicBooking`
* `clinics/{clinicId}/closures`
* `clinics/{clinicId}/public/availability/blocks`

### Slot inclusion rules (order matters)

A slot is available if all are true:

1. Inside requested range
2. After `now + minNoticeMinutes`
3. Before `now + maxAdvanceDays`
4. Inside `weeklyHours` interval (timezone-aware)
5. Not overlapping a closure
6. Not overlapping a busy block
7. Corporate rules satisfied:

   * Public view excludes LINK_ONLY days
   * Corporate view allows only configured days
   * CODE_UNLOCK requires validated access

No UI may hardcode opening times.

---

## 8. Validation requirements

Enforce at write-time and/or projection-time:

* Time format must be `HH:mm`
* Intervals must not overlap within a day
* Reasonable interval count per day (≤ 3 recommended)
* `slotStepMinutes` divides evenly into 60
* Invalid configs must not silently produce availability

---

## 9. Backward compatibility

If legacy fields exist (e.g. `openingHours`):

* Projection builder may read legacy fields
* Projection builder must always output canonical:

  * `timezone`
  * `weeklyHours`

Breaking semantic changes require:

* `schemaVersion` bump
* documented migration

---

## 10. Definition of Done

This contract is satisfied when:

1. Editing opening hours affects:

   * Public booking availability
   * Clinic calendar availability
2. Corporate days appear only when permitted
3. Corporate codes are never exposed publicly
4. No client writes exist under `/public/**`
5. No calendar hardcodes business hours

---

**End of contract**

```

---

If you want next, I can:
- generate a **short validation checklist** for the settings UI
- add a **diagram showing the availability pipeline**
- or produce a **companion ADR** explaining why this contract exists (useful later)

Just tell me.
```
