# BOOKING GAP ANALYSIS

Version: 1.2  
Last Updated: 2026-03-02  
Scope: App vs [Governance Spec](BOOKING_CALENDAR_GOVERNANCE_SPEC.md), [Data Contract](BOOKING_DATA_CONTRACT.md), [Availability Engine](AVAILABILITY_ENGINE_SPEC.md), [Rendering Engine](CALENDAR_RENDERING_ENGINE_SPEC.md), [Waitlist Spec](WAITLIST_MATCHING_SPEC.md), [Guardrail](BOOKING_EXECUTION_GUARDRAIL.md).

---

# 1. PURPOSE

This document lists what is **implemented**, **partial**, and **missing** in the app relative to the booking calendar specs, so work can be prioritized without architectural drift.

---

# 2. CALENDAR DISPLAY CONFIGURATION

| Contract field / behaviour | Status | Notes |
|---------------------------|--------|--------|
| displayStartHour / displayEndHour | Done | `CalendarDisplaySettings`, stored per clinic |
| slotMinutes (5–30), slotHeightPx | Done | In model and UI |
| timePickerIncrement | Done | In model and settings screen |
| confirmMove | Done | Passed to `DraggableAppointmentBlock` |
| showFinancialIndicators | Done | In model; UI can use for icons |
| showWaitlistMatches | Done | Used on cancel to show waitlist matches |
| clientNameSeparateLine | Done | In model |
| **Layout & View:** defaultView (day/3days/week/month) | Done | Settings screen + booking calendar applies on load |
| **Layout & View:** weekStartsOn (monday/sunday) | Done | `_startOfWeekWith`; week range respects setting |
| **Layout & View:** showWeekends | Done | When false, week view shows Mon–Fri only |
| **Layout & View:** showClosedDayLabel | Done | "Closed" in day header gated by setting |
| **Layout & View:** condensedHeader | Done | Header height 40px when enabled |
| Stored per clinic, no availability logic | Done | Callable-only write; UI-only |

**Verdict:** Aligned with spec.

---

# 3. LOCATION SYSTEM

| Contract / spec | Status | Notes |
|-----------------|--------|--------|
| id, name, type, colorHex | Done | `upsertLocation` + Firestore |
| address, phone, notes | Partial | addressText exists; phone/notes per contract optional |
| Location color drives calendar marker | Partial | Locations used in settings; calendar could show location color on appointments |
| Availability location-scoped | Missing | Staff availability is not yet per-location |
| Overrides location-scoped | Missing | Availability overrides not implemented |

---

# 4. PRACTITIONER SYSTEM

| Contract / spec | Status | Notes |
|-----------------|--------|--------|
| Active flag | Done | Staff profiles / membership |
| Column toggle, reorder | Done | Rail + visibility prefs |
| Dropdown when overflow | Done | Header collapses to dropdown on narrow |
| Role-based availability access | Partial | Permissions exist; availability not yet role-gated by spec |

---

# 5. AVAILABILITY ENGINE

| Contract / spec | Status | Notes |
|-----------------|--------|--------|
| Start date, optional end date | Missing | Current: weekly map only, no date bounds |
| Recurrence rules | Missing | No recurrence on availability (only on appointments for series) |
| Multiple blocks per day, breaks | Done | Weekly map has array of start/end per day |
| Location-specific availability | Missing | No locationId on staff availability |
| Per-block bookableOnline | Missing | No per-block online booking flag |
| Internal description | Missing | No description field on availability |
| Operates in clinic time zone | Done | Public booking and staff use timezone |
| Override precedence | Missing | No availability overrides yet |

---

# 6. AVAILABILITY OVERRIDES

| Contract / spec | Status | Notes |
|-----------------|--------|--------|
| Date-bounded overrides | Missing | No model or backend |
| Available vs unavailable | Missing | — |
| Per-location | Missing | — |
| Overrides take precedence | N/A | No overrides |
| 24-hour explicit | N/A | — |

**Action:** Model added in app for future backend; backend + UI still to implement.

---

# 7. APPOINTMENT MODEL

| Contract field | Status | Notes |
|----------------|--------|--------|
| id, practitionerId, startDateTimeUtc, endDateTimeUtc, status, patientId | Done | Stored; UI uses local time |
| appointmentTypeId | Done | As serviceId |
| locationId | Partial | Added to app model for contract; backend may not write yet |

---

# 8. APPOINTMENT TYPE (SERVICE) MODEL

| Contract field | Status | Notes |
|----------------|--------|--------|
| id, name, defaultDurationMinutes | Done | As Service.id, name, defaultMinutes |
| colorHex | Partial | Added to app model; backend/settings may need to add |
| telehealth | Partial | Added to app model for contract |
| allowedPractitionerIds | Partial | Added to app model for contract |

---

# 9. WAITLIST

| Contract / spec | Status | Notes |
|----------------|--------|--------|
| patientId, preferredPractitionerIds, preferredAppointmentTypeIds | Done | `WaitlistEntry` |
| earliestDate, latestDate, priority | Done | — |
| Add entry (staff UI) | Done | "Add to waitlist" in rail; dialog: patient picker + priority/notes; `WaitlistRepository.addEntry` |
| Match on cancellation | Done | Show matches when cancel and toggle on |
| Match by practitioner/type/date | Done | `_matchWaitlistToFreedSlot` |
| Book immediately / Skip / Remove | Done | Modal actions |
| Drag from waitlist to calendar | Partial | “Book” sets pending entry; tap slot books (no literal drag) |
| Matching <50ms, reuse availability cache | Partial | Uses in-memory list; no formal cache contract |

---

# 10. CALENDAR RENDERING ENGINE

| Spec requirement | Status | Notes |
|------------------|--------|--------|
| Receives resolved data only | Done | Hours from resolver/cache; appointments from stream |
| No availability resolution in UI | Done | Opening hours resolved elsewhere |
| No direct DB read in renderer | Partial | Uses StreamBuilder for appointments/settings (reactive; not “resolve availability” in grid) |
| Multi-practitioner columns | Done | — |
| Overlapping appointments | Done | Stacking in grid |
| Location color on appointments | Partial | Location not on Appointment yet in UI |
| Financial indicator icons | Done | Setting + toggle in Calendar display settings; payments icon on blocks when enabled |
| Current time line | Done | _CurrentTimeIndicator |
| Dynamic slot height / minute increments | Done | From display settings |
| Greyed-out unavailable blocks | Done | Weekly hours / closures |
| Vertical virtualization | Partial | Single scroll; consider ListView.builder for very large ranges |
| Drag & drop, snap to slotMinutes | Done | DraggableAppointmentBlock |
| Confirm move when enabled | Done | confirmAppointmentMoves passed through |

---

# 11. TIME RULES

| Spec | Status | Notes |
|------|--------|--------|
| All times stored UTC | Done | Backend stores UTC |
| Display in clinic time zone | Done | UI converts to local |
| Availability in clinic time zone | Done | Weekly hours in local |
| Overrides resolve before rendering | N/A | No overrides yet |

---

# 12. BUILD ORDER (GOVERNANCE §13)

1. Calendar display config model — **Done**
2. Availability engine — **Partial** (no recurrence, no date bounds, no location, no bookableOnline)
3. Location integration — **Partial** (locations exist; not in availability or overrides)
4. Practitioner filtering — **Done**
5. Appointment type color integration — **Partial** (model extended; UI can use colorHex)
6. Overlap support — **Done**
7. Waitlist matching — **Done**
8. Advanced UX — **Ongoing**

---

# 13. HARD STOPS (GUARDRAIL)

- Availability logic in widgets: **Clear** (no resolution in grid).
- Rendering reads Firestore directly: **Partial** (StreamBuilders for appointments/settings; no raw Firestore in grid).
- UI hardcodes opening hours: **Clear** (uses config / weekly hours).
- Waitlist recomputes availability from scratch: **Clear** (uses cached weekly hours / slot context).
- Scales to 20+ practitioners: **Designed for** (columns + dropdown); stress test recommended.
- UTC / data contract: **Aligned** (backend UTC; app model extended for locationId and appointment type fields).

---

# 14. PUBLIC BOOKING (LOCATION-FIRST FLOW)

| Item | Status | Notes |
|------|--------|--------|
| **Location selector** | Backend ready | Mirror has `locations[]`; `getPublicBookingLocationsFn` returns them. App: add location state + dropdown when location-first UI is enabled. |
| **Appointment type selector** | Done | `getPublicBookingAppointmentTypesFn` returns types from mirror. App: appointment type dropdown (Step 2), `appointmentTypeId` passed to `listPublicSlotsFn` and `getPublicMonthAvailabilityFn`. |
| **Clinician filtered by location** | Backend ready | Practitioner `allowedLocationIds` in mirror; `getPublicBookingPractitionersFn(locationId)` filters. App: use when location selector is added. |
| **Availability includes locationId / appointmentTypeId** | Backend ready | `listPublicSlotsFn` and `getPublicMonthAvailabilityFn` accept optional `locationId` and `appointmentTypeId`. |
| **Gated render (no legacy flash)** | Rule added | See `.cursor/rules/public-booking-gated-render.mdc`. App: show skeleton until config + projection loaded; use `KeyedSubtree(ValueKey(version))`; never render legacy clinician-first branch on first build. |
| **"Any clinician" option** | Missing | Would require backend to return aggregated slots when `practitionerId` is omitted (not yet implemented). |

---

# 15. RECOMMENDED NEXT STEPS

1. **Backend + UI:** Implement availability overrides (model in app ready; add Firestore path, callable, resolution order in availability engine).
2. ~~**Backend:** Add `locationId` to appointment create/update~~ — **Done:** createAppointmentInternal, createAppointmentFn, updateAppointmentFn, and app repository accept/send optional `locationId`.
3. ~~**Rendering:** Use Service colorHex for appointment block~~ — **Done:** `DraggableAppointmentBlock` accepts `serviceIdToColorHex`; calendar builds map from services and passes it; backend/service docs can store `colorHex` (app model + fromFirestore already support it).
4. **App (optional):** Location picker when creating/editing appointment; service settings UI for `colorHex`, `telehealth`, `allowedPractitionerIds` (app writes to `services` with `services.manage`).
5. **Availability engine:** Add date bounds, recurrence, locationId, and bookableOnline per block when scaling requires it.
6. **Performance:** Run 20-practitioner stress test; add vertical virtualization if needed.

---

# 16. STABILITY / RECENT FIXES

- **Booking calendar loading (Firestore "Unexpected state")** — Fixed 2026-02-24. The calendar was stuck on loading due to Firestore web SDK assertion when streams were recreated on every rebuild. **Change:** Firestore streams are now cached by `clinicId`: (1) `booking_calendar_screen` caches `clinicDoc` and `closuresStream` in state; (2) `booking_rail_practitioners_section` caches the staff members stream; (3) `StaffRepository.watchMembershipsWithFallback` returns a cached stream per clinicId; (4) `_PractitionerInlineDropdown` uses `context.read<StaffRepository>()` so it shares the cache. StreamBuilder no longer cancels/resubscribes on rebuild, avoiding the race.

- **setState during build + settings stuck on loading (2026-02-28)** — **1)** Shell was calling `ClinicContext.setSession()` inside `StreamBuilder.build`, causing "setState() or markNeedsBuild() called during build" and broken UI. **Change:** `ClinicContext.setSessionSilent()` sets session without notifying; shell calls it during build so the first frame has session, then schedules `notifySessionListeners()` in a post-frame callback. **2)** Settings screens and calendar were stuck on loading and Firestore threw `LateInitializationError: onSnapshotUnsubscribe has not been initialized` when streams were cancelled before first snapshot. **Change:** Repos now cache one stream per `clinicId` (with `.asBroadcastStream()`) so rebuilds reuse the same stream: `CalendarDisplaySettingsRepository`, `ClinicRepository`, `PublicBookingSettingsRepository`, `AppointmentTypesRepository`, `LocationsRepository`.

- **Settings and calendar load speed + replay (2026-03)** — **1)** All callable-based settings streams now use a **last-value replay** pattern (single subscription, broadcast controller, `Stream.multi` replay) so new listeners get the last value immediately: `ClinicRepository` (watchClinic, watchActiveClosures), `LocationsRepository.watchLocationsViaCallable`, `AppointmentTypesRepository.watchAppointmentTypesViaCallable`, `PublicBookingSettingsRepository.streamSettings`, `PublicBookingRepository.watchPublicBookingConfig`, `CommunicationSettingsRepository.streamSettings`, `CalendarDisplaySettingsRepository.streamSettings`, `StaffRepository.watchMembershipsWithFallback`. **2)** **Pre-warming:** When the user opens Settings, a pre-warmer subscribes to all of these streams (Communication, Team, Locations, Appointment types, Public booking, Calendar display) so by the time they tap any section, data is often already in the replay cache. **3)** **Calendar:** `watchActiveClosures` has replay; weekly hours from `listPublicSlotsFn` are cached by (clinicId, weekStart, practitionerId) and pre-warmed from the home shell so the Calendar tab often loads without waiting for the first callable. **4)** **Cancel hardening:** Firestore snapshot cancel can throw `LateInitializationError` on web; `StaffRepository` switchMap and RxCombineLatest2, and the settings pre-warmer, now swallow cancel errors so rapid tab switching does not crash.

---

# 17. VERSION CONTROL

Changes to this gap analysis or to the specs require version/date update.
