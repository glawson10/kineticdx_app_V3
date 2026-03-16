# CBO-P3.1: Accessibility and final polish — implementation report

**Phase:** CBO-P3.1 (accessibility and final polish)  
**Scope:** Public booking calendar and times panel.

---

## 1. Keyboard day navigation in the booking calendar

**Implemented.**

- **Arrow Left / Right:** Previous / next day (moves focus and updates focused-day index; Enter/Space selects).
- **Arrow Up / Down:** Minus / plus 7 days (week step).
- **Enter / Space:** Select the focused day (calls `onDaySelected` with the focused date).
- **Range:** Selection is clamped to `firstAllowedDay`–`lastAllowedDay`; focus movement stays within the grid.
- **Disabled days:** When `disableDaysWithoutAvailability` is true, keyboard movement skips days without availability (focus moves to the next selectable day). Focus does not land on disabled days for selection; Enter/Space only selects when the focused day is selectable.

**Where:** `lib/features/public/widgets/inline_month_calendar.dart` — `_AccessibleMonthGrid` (replaces `CalendarDatePicker`), `Focus` with `onKeyEvent` handling `LogicalKeyboardKey.arrowLeft/Right/Up/Down`, `enter`, `space`; `_moveFocus`, `_selectFocused`, `_isSelectable`.

---

## 2. Calendar focus management

**Implemented.**

- **Visible focus state:** The focused day cell is drawn with a distinct border (`colorScheme.primary`, width 2.5) and a light box shadow (`colorScheme.primary` with alpha 0.35, spreadRadius 1.5). This is separate from:
  - **Selected:** `primaryContainer` background and `primary` border.
  - **Hover:** No separate hover state on the grid (focus ring is the main affordance for keyboard users).
- **Token-consistent:** Uses `Theme.of(context).colorScheme` (primary, primaryContainer, onPrimaryContainer, outline) and `AppRadius.element` for corners.

**Where:** `inline_month_calendar.dart` — `_CalendarDayCell`: `isFocused` drives border and boxShadow; selected and disabled use colorScheme tokens.

---

## 3. Slot accessibility audit

**Implemented.**

- **Keyboard focusable:** `SlotTile` uses a `Focus` widget with `canRequestFocus: isInteractive` (false when disabled or no `onTap`).
- **Enter / Space activate:** `CallbackShortcuts` with `SingleActivator(LogicalKeyboardKey.enter)` and `SingleActivator(LogicalKeyboardKey.space)` calling `_activate`, which invokes `onTap` when the tile is interactive.
- **Selected state semantics:** `Semantics(selected: widget.selected, label: semanticsLabel + semanticsHint)` so the selected slot is announced (e.g. “10:00, selected”). Label includes optional badge (e.g. “Earliest”).

**Where:** `lib/features/public/ui/patient_booking_simple_screen.dart` — `SlotTile` build: `Semantics`, `CallbackShortcuts`, `Focus`, `InkWell`; `_activate()`.

---

## 4. Semantics audit

**Implemented.**

- **Calendar days:**  
  - Selected: `Semantics(selected: true, label: '$dateStr, selected')`.  
  - Unavailable: `label: '$dateStr, unavailable'`, `button: false` when disabled.  
  - Available: `label: '$dateStr, available'` when `hasAvailability` and not selected.
- **Month navigation:** Previous month button wrapped in `Semantics(label: 'Previous month')`; next month in `Semantics(label: 'Next month')`.
- **Times panel:** The “Available times” header and selected date are wrapped in `Semantics(liveRegion: true, label: 'Available times for $formattedSelectedDate'` (or “Select a date” when none). Selected day is clearly exposed to assistive tech.
- **Calendar grid:** Top-level `Semantics(label: 'Calendar, use arrow keys to move, Enter or Space to select a day')` on the focusable grid.

**Where:** `inline_month_calendar.dart` — `_CalendarDayCell._semanticsLabel`, `_CalendarDayCell` Semantics, month row `Semantics` on IconButtons, `_AccessibleMonthGrid` Semantics; `patient_booking_simple_screen.dart` — `_AvailableTimesPanel` Semantics wrapper.

---

## 5. Contrast / disabled-state audit

**Implemented.**

- **Disabled calendar days:** `colorScheme.onSurface.withValues(alpha: 0.38)` for text (meets WCAG AA for contrast on typical surfaces).
- **Selected day:** `primaryContainer` background, `onPrimaryContainer` text, `primary` border — high contrast.
- **Hover:** Slot tiles use `primary.withValues(alpha: 0.4)` border on hover; calendar day cells do not rely on hover for meaning (focus ring is primary).
- **Times empty state:** “No times available for this day” and “Choose a time” use `onSurface.withValues(alpha: 0.65)` (slightly increased from 0.6 for readability). No change to visual hierarchy.

**Where:** `inline_month_calendar.dart` — `_CalendarDayCell` color logic; `patient_booking_simple_screen.dart` — `_AvailableTimesPanel` bodySmall color, `SlotTile` disabled text color.

---

## 6. Pointer and touch target audit

**Implemented.**

- **Calendar day cells:** `Container` has `const BoxConstraints(minWidth: 44, minHeight: 44)` so tap targets meet a 44×44 minimum.
- **Slot tiles:** Height is fixed at 58 px (`SlotTile.height`); width follows grid (typically well above 44 on mobile). No hover-only information: selection and “Earliest” are visible and exposed via semantics.
- **Month buttons:** Standard `IconButton` (48×48 default hit area). Refresh icon next to calendar is also an `IconButton`.

**Where:** `inline_month_calendar.dart` — `_CalendarDayCell` Container constraints; `patient_booking_simple_screen.dart` — `SlotTile` height, `_AvailableTimesPanel` / month actions use Material IconButtons.

---

## 7. Other changes (overflow and calendar behaviour)

- **Single-column overflow:** `_SingleColumnBookingPanel` now wraps content in `LayoutBuilder` and `SizedBox(height: boundedHeight)` so the scroll view has a bounded height (from constraints or `MediaQuery.sizeOf(context).height` minus padding), preventing the yellow/black overflow bar at the bottom.
- **Calendar implementation:** The public booking calendar no longer uses Material’s `CalendarDatePicker`. It uses a custom `_AccessibleMonthGrid` with:
  - Dots for availability (1–2 slots = 1 dot, 3–5 = 2, 6+ = 3) from `availabilityByYmd`.
  - Bold text for days with availability (and selected day).
  - Month header with “Previous month” / “Next month” buttons and month title.

---

## Summary table

| Item | Status | Notes |
|------|--------|--------|
| 1. Keyboard day navigation | **Implemented** | Left/right day, up/down week, Enter/Space select; range and skip disabled |
| 2. Calendar focus management | **Implemented** | Visible focus ring; distinct from selected; token-consistent |
| 3. Slot accessibility | **Implemented** | Focusable, Enter/Space, semantics for selected |
| 4. Semantics audit | **Implemented** | Days (selected/unavailable/available), month buttons, times panel |
| 5. Contrast / disabled audit | **Implemented** | Disabled, selected, hover, empty state adjusted |
| 6. Pointer / touch targets | **Implemented** | 44×44 min on day cells; slot height 58; no hover-only reliance |

---

## Intentionally deferred

- **Per-cell focus in calendar:** The calendar uses a single focus scope for the grid and an internal “focused day index” for keyboard navigation and focus ring. Individual day cells are not separate focusable widgets (would require many FocusNodes and more complex tab order). Deferred as acceptable for this phase; grid-level focus + arrows + Enter/Space is implemented.
- **Reduced motion / prefers-reduced-motion:** No specific handling for `MediaQuery.accessibleHover` or reduced motion; can be added in a later pass if required.

---

## Files touched

- `lib/features/public/widgets/inline_month_calendar.dart` — New accessible calendar grid, day cells with focus/semantics/dots/bold, month nav, legend unchanged.
- `lib/features/public/ui/patient_booking_simple_screen.dart` — SlotTile (CallbackShortcuts, Semantics, Focus, refactor for clarity), times panel Semantics and empty-state contrast, single-column layout overflow fix.
