import 'package:flutter/material.dart';
import '../models/day_availability.dart';

class InlineMonthCalendar extends StatelessWidget {
  const InlineMonthCalendar({
    super.key,
    this.month,
    this.selectedDay,
    this.onDaySelected,
    this.onMonthChanged,
    this.dayBuilder,
    this.availableDays = const {},
    this.visibleMonth,
    this.firstAllowedDay,
    this.lastAllowedDay,
    this.availabilityByYmd,
    this.loadingAvailability = false,
    this.disableDaysWithoutAvailability = false,
    this.maxHeight,
    this.footer,
    this.trailingAction,
  });

  final DateTime? month;
  final DateTime? selectedDay;
  final ValueChanged<DateTime>? onDaySelected;
  final ValueChanged<DateTime>? onMonthChanged;
  final Widget Function(BuildContext, DateTime)? dayBuilder;
  final Set<DateTime> availableDays;
  final DateTime? visibleMonth;
  final DateTime? firstAllowedDay;
  final DateTime? lastAllowedDay;
  final Map<String, DayAvailability>? availabilityByYmd;
  final bool loadingAvailability;
  final bool disableDaysWithoutAvailability;
  final double? maxHeight;
  final Widget? footer;
  final Widget? trailingAction;

  @override
  Widget build(BuildContext context) {
    final effectiveMonth = visibleMonth ?? month ?? DateTime.now();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: maxHeight ?? 320,
          child: CalendarDatePicker(
            initialDate: selectedDay ?? effectiveMonth,
            firstDate: firstAllowedDay ?? DateTime(effectiveMonth.year - 1),
            lastDate: lastAllowedDay ?? DateTime(effectiveMonth.year + 2),
            onDateChanged: onDaySelected ?? (_) {},
          ),
        ),
        if (trailingAction != null) trailingAction!,
        if (footer != null) footer!,
      ],
    );
  }
}

class InlineMonthCalendarLegend extends StatelessWidget {
  const InlineMonthCalendarLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            shape: BoxShape.circle,
          )),
          const SizedBox(width: 4),
          Text('Available', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
