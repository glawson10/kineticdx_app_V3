// lib/features/booking/ui/calendar_shortcuts_dialog.dart
//
// Dialog listing calendar keyboard shortcuts. Opened from Help menu or "?" key.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CalendarShortcutsDialog extends StatelessWidget {
  const CalendarShortcutsDialog({super.key});

  static const List<({String key, String description})> _shortcuts = [
    (key: 'N', description: 'New booking'),
    (key: 'T', description: 'Go to today'),
    (key: '←', description: 'Previous period'),
    (key: '→', description: 'Next period'),
    (key: '1', description: 'Day view'),
    (key: '3', description: '3 days view'),
    (key: '7', description: 'Week view'),
    (key: 'M', description: 'Month view'),
    (key: 'F', description: 'Focus clinician / filter'),
    (key: '?', description: 'Open this shortcuts dialog'),
  ];

  static Future<void> show(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      useRootNavigator: false,
      builder: (context) => const CalendarShortcutsDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMac = Theme.of(context).platform == TargetPlatform.macOS;

    return AlertDialog(
      title: const Text('Keyboard shortcuts'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Use these shortcuts when the calendar is focused and no text field is active.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            ..._shortcuts.map((s) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 56,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            s.key,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontFamily: isMac ? null : 'monospace',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            s.description,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
