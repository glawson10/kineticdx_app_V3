// lib/features/booking/ui/calendar_help_dialogs.dart
//
// Help content dialogs: drag/resize tips, repeating appointments, calendar legend.

import 'package:flutter/material.dart';

class CalendarHelpDialogs {
  CalendarHelpDialogs._();

  /// Shows a short guide for dragging and resizing appointments.
  static Future<void> showDragResizeTips(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      useRootNavigator: false,
      builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        title: const Text('Drag and resize tips'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '• Drag an appointment to another time or day to move it.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '• Drag the bottom edge of an appointment to change its duration.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '• These actions update the booking in the calendar.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    },
    );
  }

  /// Shows help for repeating (recurring) appointments.
  static Future<void> showRepeatingHelp(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      useRootNavigator: false,
      builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        title: const Text('Repeating appointments help'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Repeating appointments are created with a recurrence rule (e.g. weekly on Tuesdays).',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Text(
                '• You can edit a single occurrence or the whole series.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '• Changing one occurrence can optionally apply to this and future dates only.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '• Cancelled occurrences may still appear with a cancelled style until the series is updated.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
  }

  /// Shows a short legend for calendar colours and labels.
  static Future<void> showLegend(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      useRootNavigator: false,
      builder: (context) {
        final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      return AlertDialog(
        title: const Text('Calendar legend'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LegendRow(
                  color: scheme.primaryContainer,
                  label: 'Booked / confirmed',
                ),
                const SizedBox(height: 6),
                _LegendRow(
                  color: scheme.tertiaryContainer,
                  label: 'Tentative / pending',
                ),
                const SizedBox(height: 6),
                _LegendRow(
                  color: scheme.errorContainer,
                  label: 'Cancelled',
                ),
                const SizedBox(height: 6),
                Text(
                  'Closed days are shaded and show a "Closed" badge in the header.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendRow({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}
