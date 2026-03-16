// lib/features/booking/ui/calendar_help_menu_button.dart
//
// Help dropdown: Keyboard shortcuts, Drag and resize tips, Repeating help, Legend

import 'package:flutter/material.dart';

class CalendarHelpMenuButton extends StatelessWidget {
  const CalendarHelpMenuButton({
    super.key,
    required this.onOpenShortcuts,
    this.onOpenDragResizeTips,
    this.onOpenRepeatingHelp,
    this.onOpenLegend,
  });

  final VoidCallback onOpenShortcuts;
  final VoidCallback? onOpenDragResizeTips;
  final VoidCallback? onOpenRepeatingHelp;
  final VoidCallback? onOpenLegend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopupMenuButton<void>(
      tooltip: 'Help',
      onSelected: (_) {},
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          onTap: () {
            Navigator.of(context).pop();
            onOpenShortcuts();
          },
          child: const ListTile(
            leading: Icon(Icons.keyboard, size: 22),
            title: Text('Keyboard shortcuts'),
          ),
        ),
        if (onOpenDragResizeTips != null)
          PopupMenuItem<void>(
            onTap: () {
              Navigator.of(context).pop();
              onOpenDragResizeTips!();
            },
            child: const ListTile(
              leading: Icon(Icons.open_with, size: 22),
              title: Text('Drag and resize tips'),
            ),
          ),
        if (onOpenRepeatingHelp != null)
          PopupMenuItem<void>(
            onTap: () {
              Navigator.of(context).pop();
              onOpenRepeatingHelp!();
            },
            child: const ListTile(
              leading: Icon(Icons.repeat, size: 22),
              title: Text('Repeating appointments help'),
            ),
          ),
        if (onOpenLegend != null)
          PopupMenuItem<void>(
            onTap: () {
              Navigator.of(context).pop();
              onOpenLegend!();
            },
            child: const ListTile(
              leading: Icon(Icons.legend_toggle, size: 22),
              title: Text('Calendar legend'),
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.help_outline, size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              'Help',
              style: theme.textTheme.labelLarge?.copyWith(
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
