# Commit 17: No private settings reads in availability / public booking

The availability engine and public booking flow must read **only** from the public mirror:

- `clinics/{clinicId}/public/config/publicBooking/config`

They must **not** read from private settings:

- `clinics/{clinicId}/settings/publicBooking`
- `clinics/{clinicId}/settings/calendarDisplay`
- Any other private settings docs

## Grep guards (run from repo root)

Run these and ensure results match the expected policy.

### 1. settings/publicBooking path

```bash
grep -R "settings/publicBooking" lib/
```

**Expected:** No matches in code that drives availability or public booking.  
**Allowed:** References inside **admin-only** code (e.g. Settings screens, Commit 15 UI) are OK.  
Typical allowed locations: `lib/features/settings/`, `lib/features/clinic/settings/` (admin screens that edit private settings).

### 2. doc('publicBooking') under settings

```bash
grep -R "doc('publicBooking')" lib/
```

**Expected:** Only in:
- `lib/data/repositories/public_booking_settings_repository.dart` (private repo used by **admin** Settings UI only)
- Admin screens that use that repo (e.g. `PublicBookingSettingsScreen`, `PublicBookingWeekendHoursScreen`, `clinic_opening_hours_screen`)

No references in:
- `lib/features/booking/` (availability / calendar)
- `lib/features/public/` (public booking UI) — these must use mirror or callables only

### 3. PublicBookingSettings in booking / public

```bash
grep -R "PublicBookingSettings" lib/features/booking lib/features/public
```

**Expected:** No use of `PublicBookingSettings` (private model) in `lib/features/booking` or `lib/features/public`.  
Public booking and availability use `PublicBookingConfigV1` and `PublicBookingMirrorRepository` (mirror) or server callables.

### 4. PublicBookingSettingsRepository in booking / public

```bash
grep -R "PublicBookingSettingsRepository" lib/features/booking lib/features/public
```

**Expected:** No use of `PublicBookingSettingsRepository` in booking or public features.  
Those features use `PublicBookingMirrorRepository` and/or `PublicBookingConfigResolver` for config.

## Summary

| Area                         | Allowed to read private settings? | Must use                          |
|-----------------------------|------------------------------------|-----------------------------------|
| Admin Settings (Commit 15 UI) | Yes (edit/save via callable)      | PublicBookingSettingsRepository   |
| Availability engine (server) | No                               | Mirror config doc only            |
| Availability / booking (Flutter) | No                            | PublicBookingMirrorRepository, resolver |
| Public booking UI          | No                                | Mirror + callables (e.g. listPublicSlotsFn) |
