# Calendar display — Layout & View

**Added:** 2026-02-28 (CP-P1).  
**Path:** `clinics/{clinicId}/settings/calendarDisplay`. Writes via callable `settingsUpdateCalendarDisplayConfig` only.

---

## 1. Settings (Layout & View card)

In **Settings → Scheduling → Calendar display**, the **Layout & View** card controls:

| Setting | Key | Options | Default |
|--------|-----|---------|---------|
| Default view | `defaultView` | day, 3days, week, month | week |
| Week starts on | `weekStartsOn` | monday, sunday | monday |
| Show weekends | `showWeekends` | toggle | true |
| Show "Closed" label | `showClosedDayLabel` | toggle | true |
| Condensed header | `condensedHeader` | toggle | false |

All are display-only; they do not affect availability or slot generation.

---

## 2. Where it’s used (booking calendar)

- **Default view:** On load, the calendar opens in the clinic’s default view (day / 3 days / 7 days / month) unless the user has already changed view this session.
- **Week start:** Week range (and 5-day week when “Show weekends” is off) respects `weekStartsOn` (Monday or Sunday).
- **Show weekends off:** In 7-day view, only Mon–Fri are shown.
- **Closed label:** The “Closed” label in the multi-day column header is shown only when `showClosedDayLabel` is true.
- **Condensed header:** When true, the main calendar header and day-column header use a reduced height (40px).

---

## 3. Backend

- **Callable:** `settingsUpdateCalendarDisplayConfig`. Patch keys: `defaultView`, `weekStartsOn`, `showWeekends`, `showClosedDayLabel`, `condensedHeader` (plus existing display keys).
- **Validation:** `defaultView` in { day, 3days, week, month }; `weekStartsOn` in { monday, sunday }; booleans as boolean or omitted. Merged start/end validation unchanged.

---

## 4. Manual smoke checklist

1. **Settings → Scheduling → Calendar display** → open **Layout & View**.
2. Set **Default view** to **Month** → Save. Refresh app → open Booking calendar → it should open in Month view (unless you changed view in the same session).
3. Turn **Show weekends** off → in week view the grid shows 5 days (Mon–Fri).
4. Toggle **Condensed header** on → header height should be visibly smaller.
5. Toggle **Show "Closed" label** off → closed days in the header should not show the “Closed” label.

---

## 5. Related fixes (same session)

- **Session during build:** Shell uses `setSessionSilent()` + post-frame `notifySessionListeners()` so the first frame has session and “setState during build” is avoided.
- **Stream caching:** Calendar display and other settings repos cache one stream per `clinicId` so StreamBuilder rebuilds don’t cancel before first snapshot (avoids Firestore “Unexpected state” / LateInitializationError). See BOOKING_GAP_ANALYSIS.md §15.
