import 'package:flutter/material.dart';

class BookingRailDateNavigator extends StatelessWidget {
  const BookingRailDateNavigator({
    super.key,
    this.selectedDate,
    this.onDateChanged,
    this.expanded = true,
    this.currentFocus,
    this.isExpanded,
    this.onExpandedChanged,
    this.onDateSelected,
  });

  final DateTime? selectedDate;
  final ValueChanged<DateTime>? onDateChanged;
  final bool expanded;
  final DateTime? currentFocus;
  final bool? isExpanded;
  final ValueChanged<bool>? onExpandedChanged;
  final ValueChanged<DateTime>? onDateSelected;

  @override
  Widget build(BuildContext context) {
    final show = isExpanded ?? expanded;
    if (!show) return const SizedBox.shrink();
    final focus = currentFocus ?? selectedDate ?? DateTime.now();
    // Key so the picker resyncs to the focused month when navigating (e.g. prev/next or date tap).
    return CalendarDatePicker(
      key: ValueKey('${focus.year}-${focus.month}'),
      initialDate: focus,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      onDateChanged: onDateSelected ?? onDateChanged ?? (_) {},
    );
  }
}
