# Settings & public booking – which logs to check

When you get a server error saving scheduling or online-booking settings, the **callable that ran** depends on what you clicked. Check the Cloud Function logs for that callable (and any related trigger).

## UI action → callable

| What you did | Callable to check in Cloud Functions logs |
|--------------|--------------------------------------------|
| Toggled **Active** on an appointment type (Scheduling → Appointment types) | **settingsSetAppointmentTypeActive** |
| Saved **Edit appointment type** (name, duration, price, Active, Show in online booking, etc.) | **settingsUpsertAppointmentType** |
| Saved **Online booking** tab (require email/phone, cancellation policy, confirmation message) | **settingsUpdatePublicBookingConfig** |
| Toggled “Allow new patients” or other online-booking enablement | **settingsUpdateOnlineBookingEnablement** (or may be folded into **settingsUpdatePublicBookingConfig** in your build) |
| Saved **Public booking** / “Rebuild public booking mirror” | **rebuildPublicBookingMirrorFn** |
| Saved practitioner availability / overrides (Scheduling → Practitioners) | **settingsUpsertPractitionerAvailability**, **settingsUpsertPractitionerOverride** |
| Deleted availability rule (Recurring availability tab) | **settingsDeletePractitionerAvailability** |
| Deleted override (Overrides tab) | **settingsDeletePractitionerOverride** |
| Toggled **Active** on a location | **settingsSetLocationActive** |

So: **when you selected the Active button on an appointment type**, the backend that ran is **settingsSetAppointmentTypeActive**. If you only checked `settingsUpdatePublicBookingConfig`, that one wouldn’t have been invoked for that click.

## Triggers that matter for public booking

The **public booking mirror** (practitioners, locations, appointment types for the public site) is updated when:

1. **Someone writes** `clinics/{clinicId}/settings/publicBooking`  
   → Firestore trigger **onPublicBookingSettingsWrite** runs and rebuilds the mirror from:
   - `settings/publicBooking`
   - `locations`, `practitioners`, `members`/`memberships`, `appointmentTypes`, etc.

2. **Someone runs “Rebuild”**  
   → Callable **rebuildPublicBookingMirrorFn** (or the projection’s rebuild) runs and does the same.

Toggling **Active** on an appointment type only updates `clinics/{clinicId}/appointmentTypes/{id}`. It does **not** write `settings/publicBooking`, so **onPublicBookingSettingsWrite does not run** for that action. The mirror only gets the new appointment-type state after you:

- Save the **Online booking** / **Public booking** settings once (so the trigger runs), or  
- Run **Rebuild public booking mirror**.

So if scheduling settings “aren’t working” and the public booking screen shows “No practitioners found”, usually:

1. The mirror was never built or is stale → **save Public booking / Online booking once** (or run Rebuild).
2. If **saving** that screen fails → check **settingsUpdatePublicBookingConfig** and the trigger **onPublicBookingSettingsWrite** in the logs (and that the callable actually ran; if you see nothing, the client might be calling a different endpoint or the error might be from another callable).

## Public booking: no clinicians showing

The public booking screen uses the **public mirror** for opening hours, practitioners (and their availability/restrictions), and appointment types. For clinicians to appear and for slots to be offered:

1. **Build the mirror** – Save **Settings → Scheduling → Online booking** once (writes `settings/publicBooking` and triggers **onPublicBookingSettingsWrite**). Or use **Rebuild** on the public booking page (calls **rebuildPublicBookingMirrorFn**).
2. **Show clinicians in public booking** – In **Team**, open each clinician and turn **ON** “Show in online booking”. Only practitioners with `showInPublicBooking: true` and active membership are included.
3. **Availability** – Practitioner availability and restrictions are read from the mirror; **listPublicSlotsFn** uses opening hours and each practitioner’s availability to return bookable times.

### Overlapping availability rules (locations × times)

The app validates that **within a single** availability rule there are no overlapping time blocks on the same day. It does **not** currently validate overlap **across** rules (e.g. one rule at Location A Monday 09:00–12:00 and another at Location B Monday 10:00–11:00). Such overlap is allowed; the mirror merges availability across locations. If you want to avoid the same practitioner being offered at two locations at the same time, keep recurring blocks non-overlapping across locations, or a future change could add a warning/error when saving overlapping rules.

## Logs worth checking (summary)

- **Active on appointment type** → **settingsSetAppointmentTypeActive**
- **Save Online booking / Public booking** → **settingsUpdatePublicBookingConfig** then **onPublicBookingSettingsWrite**
- **Save appointment type (edit form)** → **settingsUpsertAppointmentType**
- **No practitioners on public booking** → **onPublicBookingSettingsWrite** (did it run? any errors?), **rebuildPublicBookingMirrorFn** if you used Rebuild, and **listPublicSlotsFn** / **getPublicBookingAppointmentTypesFn** for the read path.

### Firestore "INTERNAL ASSERTION FAILED: Unexpected state" after saving (web)

If the **browser console** or **Flutter run terminal** shows:

`FIRESTORE (12.9.0) INTERNAL ASSERTION FAILED: Unexpected state (ID: b815)`  
with `TargetState.We` / `WatchChangeAggregator` in the stack:

- This comes from the **Firestore JavaScript SDK** (web) when it processes a snapshot update. It can occur when the settings document is updated (e.g. right after you tap Save) and the snapshot stream emits.
- **Effect:** The stream can break; the settings screen may keep showing a loading spinner and you may be unable to open other screens or the public calendar.
- **Logs to inspect:** **Browser DevTools → Console** (F12) and the **Flutter run terminal**. The stack will mention `onSnapshot`, `startListen`, and Flutter’s `StreamBuilder` / `didUpdateWidget`.
- **Mitigations:**
  1. The app now avoids showing full-screen loading on the settings screen once data has loaded once, so a stream hiccup is less likely to trap you.
  2. Refresh the app (F5 or reload) to get a new Firestore connection; then navigate away from the settings screen.
  3. Upgrade **cloud_firestore** and **Firebase JS** (e.g. in `pubspec.yaml` and web `index.html` script tags) in case a newer version fixes the assertion.
  4. If it recurs, report the Firebase/Firestore web SDK version and the full console stack to Firebase support or the FlutterFire repo.

### Persistent loading or error when saving questionnaire settings

When you **enable/select post-booking questionnaires and tap Save** and the screen shows a persistent loading spinner and/or an error:

1. **Flutter run terminal** – The Dart exception (e.g. timeout, network, or the message returned by the callable) is printed there. Look for lines right after you tapped Save. If you run from an IDE, check the Debug Console / Run view.
2. **Firebase Console** – Go to **Functions** → **Logs**, set region to **europe-west3**, and filter or search for **settingsUpdatePublicBookingConfig**. The failed invocation will show the server-side error (e.g. invalid-argument, permission, or internal). Copy the error message and stack trace from the ERROR entry.

The app shows a short error message on the screen; for internal/server errors it will suggest checking logs for `settingsUpdatePublicBookingConfig`. Use the two places above to get the exact fault to fix or report.

### Rebuild failed (INTERNAL) on the public calendar

When the **Rebuild** button on the public booking page fails with `[firebase_functions/internal] INTERNAL`:

1. In **Firebase Console** go to **Functions** → select **rebuildPublicBookingMirrorFn** → **Logs**.
2. Set the time range to when you clicked Rebuild. Region is **europe-west3**.
3. Copy the **error message** and **stack trace** from the failed invocation (the log entry with severity ERROR). That will show the underlying cause (e.g. Firestore rejecting a value, permission, or missing data).

In Firebase Console: Functions → select the function name → Logs. Filter by time when you clicked.

**If no logs appear:** The app must call Cloud Functions in the same **region** they are deployed. These functions are in **europe-west3**. The app’s settings repos (appointment types, locations, public booking config, calendar display, communication) now use `FirebaseFunctions.instanceFor(region: 'europe-west3')` so requests hit the deployed functions and show up in logs. If you still see no logs, confirm in Firebase Console that the function is deployed to **europe-west3** and that the app is using the same Firebase project.
