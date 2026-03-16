// lib/features/booking/ui/calendar_display_menu_button.dart
//
// Display dropdown: Hide cancelled, Hide admin blocks, Show closed shading,
// Density, Show weekend, Show tools panel, Fullscreen

import 'package:flutter/material.dart';

import '../data/calendar_ui_state.dart';

class CalendarDisplayMenuButton extends StatelessWidget {
  const CalendarDisplayMenuButton({
    super.key,
    required this.hideCancelled,
    required this.onHideCancelledChanged,
    required this.showAdminBlocks,
    required this.onShowAdminBlocksChanged,
    required this.showClosedShading,
    required this.onShowClosedShadingChanged,
    required this.densityMode,
    required this.onDensityChanged,
    required this.showWeekend,
    required this.onShowWeekendChanged,
    required this.showToolsPanel,
    required this.onShowToolsPanelChanged,
    required this.fitWeek,
    required this.onFitWeekChanged,
  });

  final bool hideCancelled;
  final ValueChanged<bool> onHideCancelledChanged;
  final bool showAdminBlocks;
  final ValueChanged<bool> onShowAdminBlocksChanged;
  final bool showClosedShading;
  final ValueChanged<bool> onShowClosedShadingChanged;
  final CalendarDensityMode densityMode;
  final ValueChanged<CalendarDensityMode> onDensityChanged;
  final bool showWeekend;
  final ValueChanged<bool> onShowWeekendChanged;
  final bool showToolsPanel;
  final ValueChanged<bool> onShowToolsPanelChanged;
  final bool fitWeek;
  final ValueChanged<bool> onFitWeekChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopupMenuButton<void>(
      tooltip: 'Display',
      onSelected: (_) {},
      itemBuilder: (context) => [
        _checkboxItem(
          context,
          'Hide cancelled',
          hideCancelled,
          onHideCancelledChanged,
          Icons.visibility_off_outlined,
        ),
        _checkboxItem(
          context,
          'Hide admin blocks',
          !showAdminBlocks,
          (v) => onShowAdminBlocksChanged(!v),
          Icons.block_outlined,
        ),
        _checkboxItem(
          context,
          'Show closed shading',
          showClosedShading,
          onShowClosedShadingChanged,
          Icons.dark_mode_outlined,
        ),
        const PopupMenuDivider(),
        PopupMenuItem<void>(
          enabled: false,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Density',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        PopupMenuItem<void>(
          onTap: () => onDensityChanged(CalendarDensityMode.compact),
          child: ListTile(
            leading: Icon(
              densityMode == CalendarDensityMode.compact ? Icons.check : null,
              size: 22,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Compact'),
          ),
        ),
        PopupMenuItem<void>(
          onTap: () => onDensityChanged(CalendarDensityMode.comfortable),
          child: ListTile(
            leading: Icon(
              densityMode == CalendarDensityMode.comfortable ? Icons.check : null,
              size: 22,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Comfortable'),
          ),
        ),
        PopupMenuItem<void>(
          onTap: () => onDensityChanged(CalendarDensityMode.spacious),
          child: ListTile(
            leading: Icon(
              densityMode == CalendarDensityMode.spacious ? Icons.check : null,
              size: 22,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Spacious'),
          ),
        ),
        const PopupMenuDivider(),
        _checkboxItem(
          context,
          'Show weekend',
          showWeekend,
          onShowWeekendChanged,
          Icons.calendar_view_week_outlined,
        ),
        _checkboxItem(
          context,
          'Show tools panel',
          showToolsPanel,
          onShowToolsPanelChanged,
          Icons.apps_outlined,
        ),
        _checkboxItem(
          context,
          'Fullscreen',
          fitWeek,
          onFitWeekChanged,
          Icons.fullscreen,
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune, size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              'Display',
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

  PopupMenuItem<void> _checkboxItem(
    BuildContext context,
    String label,
    bool value,
    ValueChanged<bool> onChanged,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    return PopupMenuItem<void>(
      onTap: () => onChanged(!value),
      child: ListTile(
        leading: Icon(
          value ? Icons.check_box : Icons.check_box_outline_blank,
          size: 22,
          color: value ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
        ),
        title: Text(label),
        trailing: Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
