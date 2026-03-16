// lib/features/booking/ui/calendar_tools_panel.dart
//
// Tools panel with section cards: Date Navigator, Visible Clinicians, Waitlist.

import 'package:flutter/material.dart';

import '../data/booking_calendar_prefs.dart';
import '../data/calendar_ui_state.dart';
import '../../../models/waitlist_entry.dart';
import 'booking_rail_date_navigator.dart';
import 'booking_rail_practitioners_section.dart';
import 'booking_rail_waitlist_section.dart';

class CalendarToolsPanel extends StatelessWidget {
  const CalendarToolsPanel({
    super.key,
    required this.clinicId,
    required this.currentFocus,
    required this.onDateSelected,
    required this.practitionerPrefs,
    required this.onPractitionerPrefsChanged,
    this.onBookWaitlistEntry,
    this.onClose,
    this.activeSection = CalendarToolsSection.overview,
    this.miniCalendarExpanded = true,
    this.onMiniCalendarExpandedChanged,
  });

  final String clinicId;
  final DateTime currentFocus;
  final ValueChanged<DateTime> onDateSelected;
  final PractitionerVisibilityPrefs practitionerPrefs;
  final void Function(PractitionerVisibilityPrefs prefs, List<String> visibleIds, List<String> orderIds) onPractitionerPrefsChanged;
  final void Function(WaitlistEntry entry)? onBookWaitlistEntry;
  final VoidCallback? onClose;
  final CalendarToolsSection activeSection;
  final bool miniCalendarExpanded;
  final ValueChanged<bool>? onMiniCalendarExpandedChanged;

  static const double width = 320;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          right: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(-2, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Calendar tools',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: onClose,
                    tooltip: 'Close panel',
                    style: IconButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      minimumSize: const Size(36, 36),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DateNavigatorCard(
                    currentFocus: currentFocus,
                    onDateSelected: onDateSelected,
                    expanded: miniCalendarExpanded,
                    onExpandedChanged: onMiniCalendarExpandedChanged ?? (_) {},
                  ),
                  const SizedBox(height: 16),
                  VisibleCliniciansCard(
                    clinicId: clinicId,
                    initialPrefs: practitionerPrefs,
                    onPrefsChanged: onPractitionerPrefsChanged,
                  ),
                  const SizedBox(height: 16),
                  WaitlistCard(
                    clinicId: clinicId,
                    onBookEntry: onBookWaitlistEntry,
                    emptyMessage: 'When patients are added to the waitlist, they appear here. '
                        'You can book them into an empty slot with one tap.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DateNavigatorCard extends StatelessWidget {
  const DateNavigatorCard({
    super.key,
    required this.currentFocus,
    required this.onDateSelected,
    this.expanded = true,
    this.onExpandedChanged,
  });

  final DateTime currentFocus;
  final ValueChanged<DateTime> onDateSelected;
  final bool expanded;
  final ValueChanged<bool>? onExpandedChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final nextWeek = today.add(const Duration(days: 7));
    final nextMonth = DateTime(now.year, now.month + 1, 1);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  'Date navigator',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (onExpandedChanged != null) ...[
                  const Spacer(),
                  IconButton(
                    icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                    onPressed: () => onExpandedChanged!(!expanded),
                    style: IconButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      minimumSize: const Size(32, 32),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _QuickJumpChip(label: 'Today', date: today, onDateSelected: onDateSelected),
                _QuickJumpChip(label: 'Tomorrow', date: tomorrow, onDateSelected: onDateSelected),
                _QuickJumpChip(label: 'Next week', date: nextWeek, onDateSelected: onDateSelected),
                _QuickJumpChip(label: 'Next month', date: nextMonth, onDateSelected: onDateSelected),
              ],
            ),
            if (expanded) ...[
              const SizedBox(height: 12),
              BookingRailDateNavigator(
                currentFocus: currentFocus,
                selectedDate: currentFocus,
                expanded: true,
                onDateSelected: onDateSelected,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickJumpChip extends StatelessWidget {
  const _QuickJumpChip({
    required this.label,
    required this.date,
    required this.onDateSelected,
  });

  final String label;
  final DateTime date;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: () => onDateSelected(date),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class VisibleCliniciansCard extends StatelessWidget {
  const VisibleCliniciansCard({
    super.key,
    required this.clinicId,
    required this.initialPrefs,
    required this.onPrefsChanged,
  });

  final String clinicId;
  final PractitionerVisibilityPrefs initialPrefs;
  final void Function(PractitionerVisibilityPrefs prefs, List<String> visibleIds, List<String> orderIds) onPrefsChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Visible clinicians',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            BookingRailPractitionersSection(
              clinicId: clinicId,
              initialPrefs: initialPrefs,
              onPrefsChanged: onPrefsChanged,
              shrinkWrap: true,
            ),
          ],
        ),
      ),
    );
  }
}

class WaitlistCard extends StatelessWidget {
  const WaitlistCard({
    super.key,
    required this.clinicId,
    this.onBookEntry,
    this.emptyMessage = 'When patients are added to the waitlist, they appear here. '
        'You can book them into an empty slot with one tap.',
  });

  final String clinicId;
  final void Function(WaitlistEntry entry)? onBookEntry;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: BookingRailWaitlistSection(
          clinicId: clinicId,
          onBookEntry: onBookEntry,
          emptyMessage: emptyMessage,
        ),
      ),
    );
  }
}
