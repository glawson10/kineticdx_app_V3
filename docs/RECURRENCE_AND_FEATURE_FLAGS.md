# Recurrence (series) appointments and feature flags

## Recurrence feature (implemented, UI off by default)

Recurring (series) appointments are fully implemented in backend and Flutter but **the recurrence UI is turned off by default** because it was considered messy and not ready for production presentation.

### What exists

- **Backend (Cloud Functions)**  
  - `createAppointmentSeriesFn` – create a weekly series (with count or horizon).  
  - `updateAppointmentOccurrenceFn` – update one occurrence (optionally mark as series exception).  
  - `updateAppointmentSeriesFn` – change time/duration/rule for entire series from a given date.  
  - `splitAppointmentSeriesFn` – “this and following”: end old series, start new from split date.  
  - Recurrence helpers: `recurrence.ts` (e.g. `occurrenceKeyLocalFromMs`, `generateOccurrences`), `seriesHelpers.ts`.

- **Firestore**  
  - `clinics/{clinicId}/appointmentSeries/{seriesId}` – series metadata (rule, startTimeLocal, durationMinutes, etc.).  
  - Appointments: `seriesId`, `seriesIndex`, `seriesRevision`, `isSeriesException`, `originalStartAt`, `occurrenceKeyLocal`.  
  - Composite index: `seriesId` + `startAt` for queries.

- **Flutter**  
  - Booking calendar: “Repeat?” dialog, “How many appointments?” step, series badge (⟳) on blocks, scope picker (“This appointment only” / “This and following” / “Entire series”) when editing or dragging a series occurrence.  
  - Repo: `createAppointmentSeries`, `updateAppointmentOccurrence`, `updateAppointmentSeries`, `splitAppointmentSeries`.  
  - Model: `RecurrenceDraft`, `Appointment.isSeriesOccurrence`.

### How to turn recurrence UI on

In **`lib/features/booking/ui/booking_calendar_screen.dart`**, set:

```dart
static const bool showRecurrenceUI = true;
```

When `true`:

- After confirming a new booking, the **“Repeat?”** dialog appears; choosing **Yes** shows **“How many appointments?”** and creates a series via `createAppointmentSeriesFn`.
- Appointment blocks that are part of a series show a **repeat icon**.
- When **editing** or **dragging** a series occurrence, the **scope dialog** is shown (this only / this and following / entire series), and the correct API is called.

When `false` (default):

- No Repeat dialog; every new booking is a single appointment.
- No series badge; no scope dialog; editing/dragging a series occurrence is treated as “this occurrence only” (uses `updateAppointmentOccurrence` with “this only” behaviour).

### Running recurrence tests (Functions)

```bash
cd functions && npm test -- --testPathPattern=recurrence
```

---

## Other notes from this session

- **Create appointment errors**  
  Create-series and related callables surface real error messages to the user (and log full details). If you see a generic “INTERNAL” again, check Firebase Functions logs for the thrown message.

- **Deploy quota (429)**  
  Full `firebase deploy --only functions` can hit “Per project mutation requests per minute per region”. Wait a couple of minutes and re-run; retries usually succeed. Appointment-series functions deploy with the rest.

- **Node 20 / firebase-functions**  
  Firebase may warn about Node 20 deprecation and an outdated `firebase-functions` version. Consider upgrading the runtime and `firebase-functions` when convenient (see Firebase docs).
