// lib/features/booking/ui/calendar_settings_sheet.dart
//
// Calendar settings: General, Display defaults, Interaction, Help.
// Persisted via booking_calendar_prefs (local); TODO: optional backend sync.

import 'package:flutter/material.dart';

import '../data/booking_calendar_prefs.dart';
import '../data/calendar_ui_state.dart';

class CalendarSettingsSheet extends StatefulWidget {
  const CalendarSettingsSheet({
    super.key,
    this.onOpenShortcuts,
    this.onOpenInteractionGuide,
    this.onOpenDisplaySettings,
  });

  final VoidCallback? onOpenShortcuts;
  final VoidCallback? onOpenInteractionGuide;
  final VoidCallback? onOpenDisplaySettings;

  /// Show as modal bottom sheet (narrow) or dialog (wide).
  static Future<void> show(
    BuildContext context, {
    VoidCallback? onOpenShortcuts,
    VoidCallback? onOpenInteractionGuide,
    VoidCallback? onOpenDisplaySettings,
  }) async {
    final isWide = MediaQuery.sizeOf(context).width >= 600;
    if (isWide) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Calendar settings'),
          content: SizedBox(
            width: 420,
            child: CalendarSettingsSheet(
              onOpenShortcuts: onOpenShortcuts,
              onOpenInteractionGuide: onOpenInteractionGuide,
              onOpenDisplaySettings: onOpenDisplaySettings,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) => SingleChildScrollView(
            controller: scrollController,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewPadding.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Calendar settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  CalendarSettingsSheet(
                    onOpenShortcuts: () {
                      Navigator.of(context).pop();
                      onOpenShortcuts?.call();
                    },
                    onOpenInteractionGuide: () {
                      Navigator.of(context).pop();
                      onOpenInteractionGuide?.call();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }

  @override
  State<CalendarSettingsSheet> createState() => _CalendarSettingsSheetState();
}

class _CalendarSettingsSheetState extends State<CalendarSettingsSheet> {
  bool _rememberLastView = true;
  int _defaultViewMode = 7;
  int _defaultDensity = 1;
  bool _startOnCurrentDay = true;
  bool _hideCancelledByDefault = false;
  bool _showWeekendByDefault = true;
  bool _showClosedShadingByDefault = true;
  bool _showToolsPanelByDefault = false;
  bool _enableHoverQuickActions = true;
  bool _enableKeyboardShortcuts = true;
  bool _showShortcutHints = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final remember = await loadRememberLastView();
    final viewMode = await loadLastViewMode();
    final density = await loadDensityMode();
    final startCurrent = await loadStartOnCurrentDay();
    final hideCancelled = await loadHideCancelledByDefault();
    final showWeekend = await loadShowWeekend();
    final showClosed = await loadShowClosedShading();
    final showTools = await loadShowToolsPanelByDefault();
    final hover = await loadEnableHoverQuickActions();
    final shortcuts = await loadEnableKeyboardShortcuts();
    final hints = await loadShowShortcutHints();
    if (mounted) {
      setState(() {
        _rememberLastView = remember;
        _defaultViewMode = viewMode;
        _defaultDensity = density;
        _startOnCurrentDay = startCurrent;
        _hideCancelledByDefault = hideCancelled;
        _showWeekendByDefault = showWeekend;
        _showClosedShadingByDefault = showClosed;
        _showToolsPanelByDefault = showTools;
        _enableHoverQuickActions = hover;
        _enableKeyboardShortcuts = shortcuts;
        _showShortcutHints = hints;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _sectionTitle(theme, 'General'),
        _switch('Remember last view', _rememberLastView, (v) async {
          await saveRememberLastView(v);
          setState(() => _rememberLastView = v);
        }),
        _viewDropdown(theme),
        _densityDropdown(theme),
        _switch('Start on current day/week', _startOnCurrentDay, (v) async {
          await saveStartOnCurrentDay(v);
          setState(() => _startOnCurrentDay = v);
        }),
        const SizedBox(height: 20),
        _sectionTitle(theme, 'Display defaults'),
        _switch('Hide cancelled by default', _hideCancelledByDefault, (v) async {
          await saveHideCancelledByDefault(v);
          setState(() => _hideCancelledByDefault = v);
        }),
        _switch('Show weekend by default', _showWeekendByDefault, (v) async {
          await saveShowWeekend(v);
          setState(() => _showWeekendByDefault = v);
        }),
        _switch('Show closed shading by default', _showClosedShadingByDefault, (v) async {
          await saveShowClosedShading(v);
          setState(() => _showClosedShadingByDefault = v);
        }),
        _switch('Show tools panel by default', _showToolsPanelByDefault, (v) async {
          await saveShowToolsPanelByDefault(v);
          setState(() => _showToolsPanelByDefault = v);
        }),
        const SizedBox(height: 20),
        _sectionTitle(theme, 'Interaction'),
        _switch('Enable hover quick actions', _enableHoverQuickActions, (v) async {
          await saveEnableHoverQuickActions(v);
          setState(() => _enableHoverQuickActions = v);
        }),
        _switch('Enable keyboard shortcuts', _enableKeyboardShortcuts, (v) async {
          await saveEnableKeyboardShortcuts(v);
          setState(() => _enableKeyboardShortcuts = v);
        }),
        _switch('Show shortcut hints', _showShortcutHints, (v) async {
          await saveShowShortcutHints(v);
          setState(() => _showShortcutHints = v);
        }),
        const SizedBox(height: 20),
        _sectionTitle(theme, 'Help'),
        ListTile(
          leading: const Icon(Icons.keyboard),
          title: const Text('Open shortcuts help'),
          onTap: () => widget.onOpenShortcuts?.call(),
        ),
        ListTile(
          leading: const Icon(Icons.touch_app),
          title: const Text('Open interaction guide'),
          onTap: () => widget.onOpenInteractionGuide?.call(),
        ),
        if (widget.onOpenDisplaySettings != null) ...[
          const SizedBox(height: 12),
          _sectionTitle(theme, 'Display'),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Calendar display settings'),
            subtitle: const Text('Time grid, slot height, view defaults'),
            onTap: () => widget.onOpenDisplaySettings?.call(),
          ),
        ],
      ],
    );
  }

  Widget _sectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(label),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _viewDropdown(ThemeData theme) {
    const options = {1: 'Day', 3: '3 Days', 7: 'Week', 30: 'Month'};
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('Default opening view', style: theme.textTheme.bodyLarge),
          const SizedBox(width: 16),
          DropdownButton<int>(
            value: _defaultViewMode,
            items: options.entries
                .map((e) => DropdownMenuItem<int>(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) async {
              if (v == null) return;
              await saveLastViewMode(v);
              setState(() => _defaultViewMode = v);
            },
          ),
        ],
      ),
    );
  }

  Widget _densityDropdown(ThemeData theme) {
    const options = {0: 'Compact', 1: 'Comfortable', 2: 'Spacious'};
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('Default density', style: theme.textTheme.bodyLarge),
          const SizedBox(width: 16),
          DropdownButton<int>(
            value: _defaultDensity.clamp(0, 2),
            items: options.entries
                .map((e) => DropdownMenuItem<int>(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) async {
              if (v == null) return;
              await saveDensityMode(v);
              setState(() => _defaultDensity = v);
            },
          ),
        ],
      ),
    );
  }
}
