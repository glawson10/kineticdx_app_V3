# Settings / Availability Stabilization — Full Implementation Summary

This document is the **Cursor implementation summary** for the Settings / Availability Stabilization Master Implementation Plan. It records what was implemented commit-by-commit, key files, and how to verify.

---

## Non-negotiable rules (preserved)

- All writes are **clinic-scoped** (`clinics/{clinicId}/...`).
- Sensitive writes are **function-authoritative** (callables only where specified).
- **No client writes** to: `/public/**`, `/audit/**`, `/members/**`, `/memberships/**`, `/invites/**`.
- Existing audit helper patterns and callable naming are preserved.
- No new schemas; no refactor of unrelated files. Missing pieces were patched minimally.

---

## Commit 35 — Fix location active toggle completely

**Goal:** Activate/deactivate location works end-to-end and produces audit events.

**Status:** Implemented (verification only; no code change in this pass).

**Key files:**
- `functions/src/clinic/settings/setLocationActive.ts` — callable; updates only `active` and `updatedAt`; audit `settings.location.activated` / `settings.location.deactivated` with `{ active: { before, after } }`.
- `lib/data/repositories/locations_repository.dart` — `setActive()` calls `settingsSetLocationActive`.
- `lib/features/settings/screens/locations_list_screen.dart` — toggle uses `repo.setActive()`; shows success/error snackbar.
- `firestore.rules` — `locations/{locationId}` has `allow write: if false` (callable-only).

**Verification:** Deactivate/activate from UI → success; list reflects state; audit docs under `clinics/{clinicId}/audit` show `settings.location.activated` / `settings.location.deactivated`.

---

## Commit 36 — Fix calendar display settings loading

**Goal:** Saved calendar display settings are read back from backend; no silent fallback when doc exists.

**Status:** Implemented (getter and repo already correct).

**Key files:**
- `functions/src/clinic/settings/getCalendarDisplayConfig.ts` — reads `clinics/{clinicId}/settings/calendarDisplay`; returns canonical shape; normalizes `minutesPerBlock` → `slotMinutes`, `confirmAppointmentMoves` → `confirmMove`; missing doc → in-memory defaults (no Firestore write).
- `lib/data/repositories/calendar_display_settings_repository.dart` — `getSettings()` uses callable `settingsGetCalendarDisplayConfig`.
- `lib/features/booking/ui/calendar_display_settings_screen.dart` — when `initial == null`, calls `_loadSavedSettings()` → `repo.getSettings()`.

**Verification:** Save non-default display settings, reopen screen → values reload; booking calendar uses loaded settings.

---

## Commit 37 — Unify slotMinutes vs minutesPerBlock

**Goal:** `slotMinutes` is the single stored field; backend accepts legacy `minutesPerBlock` on input; getter returns only `slotMinutes`.

**Status:** Implemented.

**Key files:**
- `functions/src/clinic/settings/updateCalendarDisplayConfig.ts` — accepts `slotMinutes` or `minutesPerBlock`; writes only `slotMinutes`; audit uses `slotMinutes`.
- `functions/src/clinic/settings/getCalendarDisplayConfig.ts` — reads `slotMinutes` first, fallback `minutesPerBlock`; response uses only `slotMinutes`.
- `lib/models/calendar_display_settings.dart` — `minutesPerBlock` is getter over `slotMinutes`; `toPatchMap()` sends `slotMinutes`.

**Verification:** Old doc with only `minutesPerBlock` loads correctly; save new config → Firestore has `slotMinutes`; UI persists and grid updates.

---

## Commit 38 — Unify opening hours source of truth

**Goal:** Clinic-level opening hours update only `clinics/{clinicId}/settings/publicBooking.weeklyHours`; no direct write to `/public/**`.

**Status:** Implemented (verified).

**Key files:**
- `functions/src/clinic/settings/updateClinicWeeklyHours.ts` — thin wrapper; delegates to `updatePublicBookingConfig`.
- `functions/src/clinic/settings/updatePublicBookingConfig.ts` — writes only to `clinics/{clinicId}/settings/publicBooking`; no `public/` path; audit `settings.publicBooking.updated`.
- `lib/features/clinic/settings/ui/clinic_opening_hours_screen.dart` — uses `repo.updateClinicWeeklyHours()`.

**Verification:** Save opening hours → only `settings/publicBooking` updated; public booking still works after projection refresh.

---

## Commit 39 — Implement public booking mirror trigger fully

**Goal:** Trigger on `clinics/{clinicId}/settings/publicBooking` runs mirror; public doc has only safe fields; no-op when unchanged.

**Status:** Implemented.

**Key files:**
- `functions/src/public/onPublicBookingConfigMirror.ts` — triggers on `clinics/{clinicId}/settings/publicBooking`; calls `runPublicBookingMirrorForClinic(clinicId)`.
- `functions/src/public/mirrorPublicBooking.ts` — writes to `clinics/{clinicId}/public/config/publicBooking/publicBooking`; comment documents this as the main public booking projection; no-op compare before write; assert writes only under `clinics/{clinicId}/public/**`; payload has only public-safe fields (timezone, weeklyHours, slotStepMinutes, minNoticeMinutes, maxAdvanceDays, schemaVersion, locations, practitioners, appointmentTypes, etc.).

**Verification:** Change `weeklyHours` or `slotStepMinutes` in private config → public mirror doc updates; public doc has no private fields; public booking UI reflects settings.

---

## Commit 40 — Add missing audit for online booking enablement

**Goal:** Global enablement update path writes an audit event.

**Status:** Implemented.

**Key files:**
- `functions/src/clinic/audit/audit.ts` — added `settings.onlineBooking.enablement.updated` to `SettingsAuditEventType`.
- `functions/src/clinic/settings/updateOnlineBookingEnablement.ts` — reads previous value before update; after Firestore update calls `writeSettingsAuditEvent(..., "settings.onlineBooking.enablement.updated", ..., "clinics/{clinicId}/settings/publicBooking", "publicBooking", { onlineBookingEnabled: { before, after } })`.

**Verification:** Toggle global online booking enablement → audit doc exists with correct event type and payload.

---

## Commit 41 — Add missing audit for location weekly hours

**Goal:** Location-level opening hours changes are audited.

**Status:** Implemented.

**Key files:**
- `functions/src/clinic/audit/audit.ts` — added `settings.location.openingHours.updated` to `SettingsAuditEventType`.
- `functions/src/clinic/settings/updateLocationWeeklyHours.ts` — after updating location doc, calls `writeSettingsAuditEvent(..., "settings.location.openingHours.updated", ..., "clinics/{clinicId}/locations", locationId, { weeklyHours })`.

**Verification:** Edit location opening hours, save → audit record in `clinics/{clinicId}/audit`.

---

## Commit 42 — Move location display order to callable + audit

**Goal:** Location display order is no longer client-written; callable-only with audit.

**Status:** Implemented.

**Key files:**
- **New:** `functions/src/clinic/settings/updateLocationDisplayOrder.ts` — input `{ clinicId, locationIds: string[] }`; validation: auth, `settings.write`, `locationIds` array; write `clinics/{clinicId}/settings/locationDisplay` with `locationIds`, `updatedAt`; audit `settings.locationDisplay.updated`.
- `functions/src/index.ts` — exports `settingsUpdateLocationDisplayOrder`.
- `firestore.rules` — `match /settings/{docId}` deny list includes `locationDisplay` (client cannot write).
- `lib/data/repositories/location_display_repository.dart` — `updateSettings()` calls callable `settingsUpdateLocationDisplayOrder` with `clinicId` and `locationIds`; `streamSettings()` still reads from Firestore.

**Verification:** Reorder locations, save, reopen → order preserved; audit event exists; client cannot write `settings/locationDisplay`.

---

## Commit 43 — Add missing appointment type fields

**Goal:** Backend and UI support `telehealth` and `allowedPractitionerIds`; mirror exposes them in public payload if needed.

**Status:** Implemented.

**Key files:**
- `functions/src/clinic/settings/upsertAppointmentType.ts` — added `telehealth` (boolean) and `allowedPractitionerIds` (string[]) to patch keys, validation, create/update, and audit diff.
- `functions/src/public/mirrorPublicBooking.ts` — appointmentTypesList in public payload includes `telehealth` and `allowedPractitionerIds`.
- `lib/models/appointment_type.dart` — added `telehealth` and `allowedPractitionerIds`; `fromFirestore` reads them.
- `lib/features/settings/screens/appointment_type_form_screen.dart` — telehealth switch; allowed practitioners multi-select (via `watchBookableClinicians` + StaffRepository); patch includes `telehealth`, `allowedPractitionerIds`.

**Verification:** Create/edit type with telehealth on and allowed practitioners → save, reload, stored doc and audit contain fields.

---

## Commit 44 — Fill missing General Settings UI fields

**Goal:** Expose and save currency, terminology, admin contact, reply-to email, require2FA; session timeout already present.

**Status:** Implemented.

**Key files:**
- `lib/features/settings/widgets/clinic_general_settings_form.dart` — `_readProfileLike` and sync block include `currency`, `terminology`, `adminContactFirstName`, `adminContactLastName`, `adminContactEmail`, `replyToEmail`, `require2FA`; new controllers and state; new section cards: "Admin contact" (first/last/email with validation), "Policy & billing" (currency, terminology, reply-to email, require2FA with policy-setting label); `_save` patch includes all; session timeout confirmed saved/reloaded.
- Backend already supported in `functions/src/clinic/updateClinicProfile.ts`.

**Verification:** Edit each field, save, reload → persistence; audit includes canonical keys (e.g. `profile.currency`).

---

## Commit 45 — Add missing Location UI fields

**Goal:** Expose colorHex; add phone and notes end-to-end.

**Status:** Implemented.

**Key files:**
- `functions/src/clinic/settings/upsertLocation.ts` — added `phone` and `notes` to `LOCATION_PATCH_KEYS` and validation (string, max length); persist and audit.
- `lib/models/clinic_location.dart` — added `colorHex`, `phone`, `notes`; `fromDoc` and constructor.
- `lib/features/settings/screens/location_form_screen.dart` — color (hex) field with validation; phone and notes text fields; patch includes `colorHex`, `phone`, `notes`.

**Verification:** Edit location color, phone, notes → save/reload; list reflects color if used; audit contains field changes.

---

## Commit 46 — Implement real Online Booking Enablement screen

**Goal:** Replace placeholder with real enablement overview: global state + visible entities summary and links.

**Status:** Implemented.

**Key files:**
- `lib/features/settings/screens/online_booking_enablement_screen.dart` — StreamBuilder for `PublicBookingSettings` (global enabled); sections: Visible locations (LocationsRepository, filter active + showInOnlineBooking), Visible practitioners (StaffRepository.watchPractitionerBookingMetas, filter showInPublicBooking), Visible appointment types (AppointmentTypesRepository.watchAllTypes, filter active + showInOnlineBooking); summary cards with counts and links; tap opens Settings with correct section (scheduling or locations) via `_openSettingsSection`; no placeholder text.

**Verification:** Open screen → no "coming soon"; reflects actual visibility; links open correct settings sections.

---

## Stability follow-up (Settings loading / errors)

**Goal:** Avoid error screen or stuck loading when switching between settings sections.

**Status:** Implemented.

**Key files and changes:**
- `lib/features/settings/home/settings_home_screen.dart` — When `clinicId.trim().isEmpty`, show "No clinic selected." for Clinic, Locations, Scheduling, Communication before building any child that uses clinicId (avoids loading/errors from empty ID).
- `lib/features/settings/widgets/clinic_general_settings_form.dart` — Empty clinicId → "No clinic selected." without subscribing to stream; on stream error show "Could not load clinic settings." + error detail + Retry button (setState to resubscribe).
- `lib/features/settings/screens/location_display_order_screen.dart` — Error handling for both StreamBuilders (display order and locations); `_SettingsStreamError` widget with message and "Switch to another tab and back to retry."
- `lib/features/settings/screens/communication_settings_screen.dart` — Empty clinicId guard; on stream error show "Could not load communication settings." + detail instead of infinite loading.

---

## Global testing checklist (after all commits)

### Settings stability
1. **Clinic → General** — Edit several fields, save, reload; confirm persistence.
2. **Locations** — Create, edit, deactivate, reorder; confirm audit events.
3. **Scheduling → Calendar display** — Edit values, reload; loaded values match saved; calendar reflects settings.
4. **Clinic → Opening hours** — Edit weekly hours; confirm private settings update and public projection updates.
5. **Scheduling → Online booking** — Toggle enablement; confirm audit event.
6. **Appointment types** — Add telehealth / allowed practitioners; save, reload.
7. **Practitioner availability / overrides** — Create/update/delete; confirm audit events.
8. **Public booking UI** — Config loads; no stale publish errors.

### Audit verification
Check `clinics/{clinicId}/audit/{eventId}` for:
- `settings.clinic.updated`
- `settings.location.created` / `updated` / `activated` / `deactivated`
- `settings.location.openingHours.updated`
- `settings.locationDisplay.updated`
- `settings.appointmentType.created` / `updated`
- `settings.calendarDisplay.updated`
- `settings.publicBooking.updated`
- `settings.onlineBooking.enablement.updated`
- `settings.availability.*` / `settings.override.*`

### Rules verification
Confirm client writes **fail** for:
- `/public/**`
- `/audit/**`
- `/members/**`
- `/memberships/**`
- `/invites/**`
- `settings/calendarDisplay`
- `settings/publicBooking`
- `settings/communication`
- `settings/locationDisplay`

---

## File reference summary

| Commit | Key files |
|--------|-----------|
| 35 | `setLocationActive.ts`, `locations_repository.dart`, `locations_list_screen.dart`, `firestore.rules` |
| 36 | `getCalendarDisplayConfig.ts`, `calendar_display_settings_repository.dart`, `calendar_display_settings.dart`, `calendar_display_settings_screen.dart` |
| 37 | `updateCalendarDisplayConfig.ts`, `getCalendarDisplayConfig.ts`, `calendar_display_settings.dart`, `calendar_display_settings_screen.dart` |
| 38 | `updateClinicWeeklyHours.ts`, `updatePublicBookingConfig.ts`, `clinic_opening_hours_screen.dart` |
| 39 | `onPublicBookingConfigMirror.ts`, `mirrorPublicBooking.ts` |
| 40 | `updateOnlineBookingEnablement.ts`, `audit.ts` |
| 41 | `updateLocationWeeklyHours.ts`, `audit.ts` |
| 42 | `updateLocationDisplayOrder.ts` (new), `index.ts`, `firestore.rules`, `location_display_repository.dart` |
| 43 | `upsertAppointmentType.ts`, `appointment_type_form_screen.dart`, `mirrorPublicBooking.ts`, `appointment_type.dart` |
| 44 | `clinic_general_settings_form.dart`, `updateClinicProfile.ts` |
| 45 | `upsertLocation.ts`, `clinic_location.dart`, `location_form_screen.dart` |
| 46 | `online_booking_enablement_screen.dart`, public booking + locations + staff + appointment types repos |
| Stability | `settings_home_screen.dart`, `clinic_general_settings_form.dart`, `location_display_order_screen.dart`, `communication_settings_screen.dart` |

---

*Summary produced from the Settings / Availability Stabilization Master Implementation Plan; commits 35–46 executed in order plus stability follow-up.*
