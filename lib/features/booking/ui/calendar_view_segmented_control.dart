// lib/features/booking/ui/calendar_view_segmented_control.dart
//
// Connected pill-style segmented control: Day | 3 Days | Week | Month

import 'package:flutter/material.dart';

/// View mode values: 1 = day, 3 = 3 days, 7 = week, 30 = month
const List<int> calendarViewSegmentValues = [1, 3, 7, 30];
const List<String> calendarViewSegmentLabels = ['Day', '3 Days', 'Week', 'Month'];

class CalendarViewSegmentedControl extends StatelessWidget {
  const CalendarViewSegmentedControl({
    super.key,
    required this.value,
    required this.onChanged,
    this.collapseToDropdown = false,
  });

  /// Current view mode: 1, 3, 7, or 30
  final int value;
  final ValueChanged<int> onChanged;

  /// On narrow layouts, show a dropdown instead of segments
  final bool collapseToDropdown;

  static const double _height = 32;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (collapseToDropdown) {
      final effective = calendarViewSegmentValues.contains(value) ? value : 7;
      return _DropdownView(
        value: effective,
        onChanged: onChanged,
        theme: theme,
      );
    }

    return Container(
      height: _height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < calendarViewSegmentValues.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 18,
                margin: const EdgeInsets.symmetric(vertical: 6),
                color: scheme.outline.withValues(alpha: 0.2),
              ),
            _Segment(
              label: calendarViewSegmentLabels[i],
              selected: value == calendarViewSegmentValues[i],
              onTap: () => onChanged(calendarViewSegmentValues[i]),
              theme: theme,
            ),
          ],
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    return Material(
      color: selected ? scheme.surface : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          alignment: Alignment.center,
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _DropdownView extends StatelessWidget {
  const _DropdownView({
    required this.value,
    required this.onChanged,
    required this.theme,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final label = value == 30
        ? 'Month'
        : calendarViewSegmentLabels[calendarViewSegmentValues.indexOf(value)];
    return PopupMenuButton<int>(
      tooltip: 'View',
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (int i = 0; i < calendarViewSegmentValues.length; i++)
          PopupMenuItem<int>(
            value: calendarViewSegmentValues[i],
            child: Row(
              children: [
                if (value == calendarViewSegmentValues[i])
                  Icon(Icons.check, size: 20, color: theme.colorScheme.primary),
                if (value == calendarViewSegmentValues[i]) const SizedBox(width: 8),
                Text(calendarViewSegmentLabels[i]),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 20, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
