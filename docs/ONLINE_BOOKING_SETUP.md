# Clinic setup for online booking

Checklist to get a clinic ready so patients can book appointments via the public booking page.

---

## 1. Public booking settings doc (existing clinics only)

**New clinics** get `clinics/{clinicId}/settings/publicBooking` when the clinic is created.

**Existing clinics** that don’t have this doc yet must create it once:

- Call the **`bootstrapPublicBookingSettings`** Cloud Function (e.g. from Firebase Console → Functions, or your own script) with `{ "clinicId": "<your-clinic-id>" }`.
- Requires **settings.write** for that clinic.
- This creates the settings doc with defaults (timezone, weekly hours, booking rules). You can then adjust everything in the app.

---

## 2. Turn online booking on

1. In the app: **Settings** → **Scheduling** → **Online booking**.
2. Turn **“Online booking on”** to **On**.
3. Save.

Until this is on, the public slot list and booking endpoint treat the clinic as unavailable.

---

## 3. Set opening hours

Public bookable slots are derived from **clinic opening hours**.

1. **Settings** → **Clinic** → **Opening hours**.
2. Set **weekly hours** for each day (e.g. Mon–Fri 09:00–17:00). Leave a day empty to mark it closed.
3. Save.  
   *(The UI notes: “Opening hours saved; public booking sync may lag.”)*

If opening hours are empty or all closed, the public page will show no slots.

---

## 4. Have at least one visible location

1. **Settings** → **Locations** → add or edit a location.
2. Ensure the location is **active** and **“Show in online booking”** is enabled.
3. Optionally set **Opening hours** per location (within clinic hours).

The public flow needs at least one location that is visible for online booking.

---

## 5. Have at least one visible practitioner

1. **Settings** → **Scheduling** → **Practitioners** (or **Team** → **Members**).
2. For each clinician who should be bookable online: open their profile → enable **“Show in public booking”** (and any availability/location/service restrictions you use).

At least one practitioner must be visible in public booking for slots to be offered.

---

## 6. Have at least one visible appointment type (service)

1. **Settings** → **Scheduling** → **Appointment types**.
2. Add or edit a type; ensure it’s **active** and **“Show in online booking”** is enabled.

At least one appointment type must be visible for online booking.

---

## 7. Optional: tune booking rules

On **Settings** → **Scheduling** → **Online booking** you can also set:

- **Max advance (days)** – how far ahead patients can book.
- **Minimum notice (minutes)** – e.g. no “next 2 hours” bookings.
- **Slot step** – 15 / 30 / 60 minutes.
- **Allow new patients** – whether first-time patients can book.
- **Require email / Require phone** – required contact fields.
- **Confirmation message** and **Questionnaire flow** (e.g. pre-appointment forms).

Save after any change.

---

## Quick checklist

| Step | Where | What |
|------|--------|------|
| 1 | (Existing clinics only) | Run `bootstrapPublicBookingSettings` if `settings/publicBooking` is missing. |
| 2 | Settings → Scheduling → Online booking | Turn **“Online booking on”** On and Save. |
| 3 | Settings → Clinic → Opening hours | Set weekly hours and Save. |
| 4 | Settings → Locations | At least one location **active** and **Show in online booking**. |
| 5 | Settings → Scheduling → Practitioners | At least one practitioner with **Show in public booking**. |
| 6 | Settings → Scheduling → Appointment types | At least one type **active** and **Show in online booking**. |

---

## How the public page behaves

- **Slots** come from the public config projection (opening hours, locations, practitioners, appointment types). If **“Online booking on”** is false, the slot API returns an error and the page can show “Booking temporarily unavailable”.
- **Creating a booking** uses the HTTPS endpoint that reads `clinics/{clinicId}/settings/publicBooking` and enforces booking rules (notice, horizon, open hours). The doc must exist (step 1) and online booking must be on (step 2).

---

## Summary

To get a clinic set up for online booking:

1. Ensure **`settings/publicBooking`** exists (bootstrap for older clinics).
2. Turn **Online booking on** in Settings → Scheduling → Online booking.
3. Set **Opening hours** in Settings → Clinic → Opening hours.
4. Enable at least one **location**, one **practitioner**, and one **appointment type** for online booking.
5. Optionally adjust booking window, notice, slot step, and patient/contact rules on the same Online booking screen.
