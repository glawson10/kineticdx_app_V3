# Public booking projection schema (v1)

Contract between the projection writer (Cloud Function trigger) and the public booking / availability engine. The projection writes from private sources to a read-only public mirror; clients never write to `/public/**`.

## Target document

- **Path:** `clinics/{clinicId}/public/config/publicBooking/config`
- **Written by:** Firestore trigger on `clinics/{clinicId}/settings/publicBooking` (and optional manual rebuild callable).
- **Read by:** Public slot listing, availability, and booking UI (read-only).

## Source documents (private, authoritative)

- `clinics/{clinicId}/settings/publicBooking` — booking rules, weeklyHours
- `clinics/{clinicId}` — timezone, currency (for jurisdiction)
- Opening hours may be taken from `settings/publicBooking.weeklyHours` only in v1.

## Public mirror shape (v1)

Only these keys are written. No PII (no names, emails, internal notes).

```json
{
  "schemaVersion": 1,
  "clinicId": "<string>",
  "updatedAt": "<server timestamp>",
  "source": {
    "publicBookingUpdatedAt": "<timestamp or null>",
    "openingHoursUpdatedAt": "<timestamp or null>",
    "clinicUpdatedAt": "<timestamp or null>"
  },
  "jurisdiction": {
    "timezone": "Europe/Prague",
    "currencyCode": "CZK"
  },
  "bookingRules": {
    "slotStepMinutes": 15,
    "minNoticeMinutes": 0,
    "maxAdvanceDays": 90,
    "allowNewPatients": true,
    "requireEmail": true,
    "requirePhone": false,
    "cancellationPolicyHours": 24
  },
  "weeklyHours": {
    "mon": [{"start": "09:00", "end": "17:00"}],
    "tue": [{"start": "09:00", "end": "17:00"}],
    "wed": [{"start": "09:00", "end": "17:00"}],
    "thu": [{"start": "09:00", "end": "17:00"}],
    "fri": [{"start": "09:00", "end": "17:00"}],
    "sat": [],
    "sun": []
  },
  "hash": "<sha256-of-canonical-json>"
}
```

### Field notes

- **schemaVersion:** Must be `1` for this contract. Bump when breaking the shape.
- **clinicId:** Echoed for convenience.
- **updatedAt:** Server timestamp of last projection write.
- **source:** Optional debug; when each private source was last updated (null if not used).
- **jurisdiction.timezone:** From clinic doc; default `"UTC"`.
- **jurisdiction.currencyCode:** From clinic doc; default `"EUR"` (or project default).
- **bookingRules:** Whitelist from `settings/publicBooking`: slotStepMinutes, minNoticeMinutes, maxAdvanceDays, allowNewPatients, requireEmail, requirePhone, cancellationPolicyHours. Defaults applied when missing.
- **weeklyHours:** All seven day keys always present. Intervals are `{ start: "HH:mm", end: "HH:mm" }`. From `settings/publicBooking.weeklyHours` in v1.
- **hash:** SHA-256 of canonical JSON (sorted keys) of the projection payload (excluding `hash` and `updatedAt`) for caching and no-op detection.

## Deletion handling

If `settings/publicBooking` is deleted, the projection writes a document with **defaults** and `source.publicBookingUpdatedAt: null` so public clients do not crash.

## Idempotency

Same inputs → same hash → same document content. Repeated triggers produce the same output.
