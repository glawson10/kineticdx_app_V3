// lib/features/booking/ui/calendar_tool_rail.dart
//
// Vertical tool rail: Tools overview, Mini calendar, Clinician visibility, Waitlist.
// Attached to the left of the calendar content; clicking an item opens the panel and switches section.

import 'package:flutter/material.dart';

import '../data/calendar_ui_state.dart';

class CalendarToolRail extends StatelessWidget {
  const CalendarToolRail({
    super.key,
    required this.isPanelOpen,
    required this.activeSection,
    required this.onSectionSelected,
  });

  final bool isPanelOpen;
  final CalendarToolsSection activeSection;
  final ValueChanged<CalendarToolsSection> onSectionSelected;

  static const double width = 52;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(
          right: BorderSide(color: scheme.outline.withValues(alpha: 0.2)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RailItem(
            icon: Icons.dashboard_outlined,
            activeIcon: Icons.dashboard,
            label: 'Tools overview',
            active: activeSection == CalendarToolsSection.overview,
            onTap: () {
              onSectionSelected(CalendarToolsSection.overview);
            },
            theme: theme,
          ),
          _RailItem(
            icon: Icons.calendar_month_outlined,
            activeIcon: Icons.calendar_month,
            label: 'Mini calendar',
            active: activeSection == CalendarToolsSection.dateNavigator,
            onTap: () {
              onSectionSelected(CalendarToolsSection.dateNavigator);
            },
            theme: theme,
          ),
          _RailItem(
            icon: Icons.people_outline,
            activeIcon: Icons.people,
            label: 'Clinician visibility',
            active: activeSection == CalendarToolsSection.clinicians,
            onTap: () {
              onSectionSelected(CalendarToolsSection.clinicians);
            },
            theme: theme,
          ),
          _RailItem(
            icon: Icons.list_alt_outlined,
            activeIcon: Icons.list_alt,
            label: 'Waitlist',
            active: activeSection == CalendarToolsSection.waitlist,
            onTap: () {
              onSectionSelected(CalendarToolsSection.waitlist);
            },
            theme: theme,
          ),
        ],
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
    required this.theme,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = widget.theme.colorScheme;

    return Tooltip(
      message: widget.label,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: widget.active
              ? scheme.primaryContainer.withValues(alpha: 0.5)
              : (_hovered ? scheme.surfaceContainerHighest : Colors.transparent),
          child: InkWell(
            onTap: widget.onTap,
            child: SizedBox(
              width: CalendarToolRail.width,
              height: 48,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.active ? widget.activeIcon : widget.icon,
                    size: 24,
                    color: widget.active
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
