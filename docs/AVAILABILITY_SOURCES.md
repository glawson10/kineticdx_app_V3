# Availability: Single Surface and Engine Alignment

## Summary

**Single Availability surface (UI):** One editor for practitioner availability (base + overrides, location-scoped). Reached from:

- **Team → Member → Availability** (tab: “Edit availability” opens canonical editor)
- **Settings → Scheduling → Practitioners → Edit availability**

Both open the same **Availability** screen (location scope, base availability per location, overrides with global/location option).

**Engine (backend):** Public slot generation (`listPublicSlots`) reads base availability from `staffProfiles/{uid}/availability/default` or, when location-scoped, from `practitioners/{id}/availability` filtered by `locationId`. **Override rules are applied:** `listPublicSlots` and `getPublicMonthAvailabilityFn` load `practitioners/{id}/overrides` for the query range; unavailable overrides (e.g. time off) are added to blocked time, and available overrides (one-off extra hours) are treated as bookable. Location-scoped requests only apply overrides whose `locationId` is null (global) or matches the selected location.

---

## 1. General clinic opening times (unchanged)

- **Where:** Settings → Public booking (and/or clinic-level settings).
- **Stored:** e.g. `clinics/{clinicId}/settings/publicBooking` (weekly hours).
- **Meaning:** When the **clinic** is open. Not clinician-specific.

---

## 2. Practitioner availability (single UI, engine not yet wired)

### Canonical data (what the single Availability UI writes)

- **Base availability:** `clinics/{clinicId}/practitioners/{practitionerId}/availability/{availabilityId}`  
  - Per location, date range, recurrence, weekly blocks.
- **Overrides:** `clinics/{clinicId}/practitioners/{practitionerId}/overrides/{overrideId}`  
  - Time-bounded; `locationId` optional (null = global).

### Legacy data (what the slot engine still reads)

- **Where:** `clinics/{clinicId}/staffProfiles/{uid}/availability/default`
- **Shape:** One doc per staff: simple weekly blocks (mon–sun).
- **Used by:** **Yes.** `listPublicSlots` uses **only** this for practitioner availability.

### Next step: wire the engine

To make “edits always matter,” do one of:

1. **Preferred:** Update `listPublicSlots` (and any other slot/availability logic) to:
   - Read base availability from `practitioners/{id}/availability` (filter by `locationId` when the request is location-scoped).
   - Apply `practitioners/{id}/overrides` (overrides win; global overrides apply to all locations).
   - Then deprecate or stop writing `staffProfiles/…/availability/default` for booking.

2. **Transitional:** Keep the engine as-is and add a mirror: when practitioner availability or overrides are written, also update `staffProfiles/{uid}/availability/default` (e.g. merge or pick one location’s hours). Not ideal for multi-location.

---

## 3. Migration / backwards compatibility

- **Existing practitioner availability rules** already have `locationId` (required in the model). No migration needed for that.
- **Legacy `staffProfiles/…/availability/default`** is still used by the engine. Once the engine reads from practitioners, you can leave legacy docs as-is or clear them.
- If you ever need to support **old availability docs without `locationId`**: on read treat as “global”; on first save prompt to assign to locations or “copy to all locations.”

---

## 4. Calendar blocks and public booking

Appointments created from the staff calendar (including **admin blocks** and **patient appointments**) are mirrored into `clinics/{clinicId}/public/availability/blocks` by the Firestore trigger `onAppointmentWrite_toBusyBlock`. The trigger runs on every write to `clinics/{clinicId}/appointments` and creates/updates/deletes the corresponding block. `listPublicSlots` reads these blocks (via `loadBusyBlocks` and `loadClinicWideBusyBlocks`), so when a patient or admin block is created from the calendar, those times are no longer offered as bookable slots on the public booking screen. No separate sync is required.

---

## 5. Data model rule

Availability is authored **per practitioner and per location**. Overrides always win. The UI reflects the computation model: base weekly blocks are stored under a location key; overrides can be location-specific or global.
