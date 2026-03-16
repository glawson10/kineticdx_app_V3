import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/day_availability.dart';
import '../../../ui/design_tokens.dart';

/// Date-only comparison (year, month, day).
DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Returns 1–3 dots based on slot count for calendar day indicator.
int _dotCountForCount(int count) {
  if (count <= 0) return 0;
  if (count <= 2) return 1;
  if (count <= 5) return 2;
  return 3;
}

/// One day cell in the accessible calendar grid.
class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.date,
    required this.isSelected,
    required this.isFocused,
    required this.isDisabled,
    required this.isToday,
    required this.isCurrentMonth,
    required this.dotCount,
    required this.hasAvailability,
    required this.onTap,
  });

  final DateTime date;
  final bool isSelected;
  final bool isFocused;
  final bool isDisabled;
  final bool isToday;
  final bool isCurrentMonth;
  final int dotCount;
  final bool hasAvailability;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textStyle = theme.textTheme.bodyMedium ?? const TextStyle();

    Color bgColor = Colors.transparent;
    Color borderColor = colorScheme.outline.withValues(alpha: 0.3);
    Color textColor = isCurrentMonth
        ? colorScheme.onSurface
        : colorScheme.onSurface.withValues(alpha: 0.38);
    FontWeight fontWeight = FontWeight.normal;

    if (isDisabled) {
      textColor = colorScheme.onSurface.withValues(alpha: 0.38);
    } else if (isSelected) {
      bgColor = colorScheme.primaryContainer;
      borderColor = colorScheme.primary;
      textColor = colorScheme.onPrimaryContainer;
      fontWeight = FontWeight.w600;
    } else if (hasAvailability && isCurrentMonth) {
      fontWeight = FontWeight.w600;
    }

    if (isToday && !isSelected) {
      borderColor = colorScheme.primary.withValues(alpha: 0.6);
    }

    return Semantics(
      button: !isDisabled,
      enabled: !isDisabled,
      selected: isSelected,
      label: _semanticsLabel(context),
          child: GestureDetector(
          onTap: isDisabled ? null : onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(AppRadius.element),
              border: Border.all(
                color: isFocused ? colorScheme.primary : borderColor,
                width: isFocused ? 2.5 : (isSelected ? 2 : 1),
              ),
              boxShadow: isFocused
                  ? [
                      BoxShadow(
                        color: colorScheme.primary.withValues(alpha: 0.35),
                        blurRadius: 0,
                        spreadRadius: 1.5,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${date.day}',
                  style: textStyle.copyWith(
                    color: textColor,
                    fontWeight: fontWeight,
                    fontSize: (textStyle.fontSize ?? 14).clamp(12.0, 16.0),
                  ),
                ),
                if (dotCount > 0) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      dotCount.clamp(0, 3),
                      (_) => Container(
                        width: 4,
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.primary.withValues(alpha: 0.8),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
    );
  }

  String _semanticsLabel(BuildContext context) {
    final day = date.day;
    final month = date.month;
    final year = date.year;
    final dateStr = '$day $month $year';
    if (isDisabled) return '$dateStr, unavailable';
    if (isSelected) return '$dateStr, selected';
    if (hasAvailability) return '$dateStr, available';
    return dateStr;
  }
}

/// Accessible month calendar with keyboard navigation, focus ring, dots, and semantics.
class _AccessibleMonthGrid extends StatefulWidget {
  const _AccessibleMonthGrid({
    required this.visibleMonth,
    required this.selectedDay,
    required this.firstAllowedDay,
    required this.lastAllowedDay,
    required this.availabilityByYmd,
    required this.disableDaysWithoutAvailability,
    required this.onDaySelected,
  });

  final DateTime visibleMonth;
  final DateTime selectedDay;
  final DateTime firstAllowedDay;
  final DateTime lastAllowedDay;
  final Map<String, DayAvailability> availabilityByYmd;
  final bool disableDaysWithoutAvailability;
  final ValueChanged<DateTime> onDaySelected;

  @override
  State<_AccessibleMonthGrid> createState() => _AccessibleMonthGridState();
}

class _AccessibleMonthGridState extends State<_AccessibleMonthGrid> {
  late int _focusedIndex;
  static const int _daysPerWeek = 7;
  static const int _maxRows = 6;

  List<DateTime?> get _gridDays {
    final month = widget.visibleMonth;
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);
    final firstWeekday = first.weekday;
    final startOffset = firstWeekday - 1;
    final totalCells = _daysPerWeek * _maxRows;
    final list = <DateTime?>[];
    for (int i = 0; i < totalCells; i++) {
      final dayOffset = i - startOffset;
      if (dayOffset < 0) {
        list.add(first.add(Duration(days: dayOffset)));
      } else if (dayOffset <= last.day) {
        list.add(DateTime(month.year, month.month, dayOffset + 1));
      } else {
        list.add(first.add(Duration(days: dayOffset)));
      }
    }
    return list;
  }

  bool _isAllowed(DateTime d) {
    final t = _dateOnly(d);
    final first = _dateOnly(widget.firstAllowedDay);
    final last = _dateOnly(widget.lastAllowedDay);
    return !t.isBefore(first) && !t.isAfter(last);
  }

  bool _isAvailable(DateTime d) {
    final key = _ymd(d);
    final av = widget.availabilityByYmd[key];
    return av != null && av.hasAvailability;
  }

  bool _isSelectable(int index) {
    final d = _gridDays[index];
    if (d == null) return false;
    if (!_isAllowed(d)) return false;
    if (widget.disableDaysWithoutAvailability && !_isAvailable(d)) return false;
    return true;
  }

  DateTime? _dateAt(int index) {
    final d = _gridDays[index];
    return d;
  }

  void _moveFocus(int delta) {
    final grid = _gridDays;
    var next = _focusedIndex + delta;
    if (next < 0) next = 0;
    if (next >= grid.length) next = grid.length - 1;
    if (widget.disableDaysWithoutAvailability) {
      while (next >= 0 && next < grid.length && !_isSelectable(next)) {
        next += delta;
      }
      if (next < 0 || next >= grid.length) return;
    }
    setState(() => _focusedIndex = next);
  }

  void _selectFocused() {
    final d = _dateAt(_focusedIndex);
    if (d == null) return;
    if (!_isSelectable(_focusedIndex)) return;
    widget.onDaySelected(_dateOnly(d));
  }

  @override
  void initState() {
    super.initState();
    _focusedIndex = _indexOf(widget.selectedDay);
  }

  int _indexOf(DateTime day) {
    final grid = _gridDays;
    final target = _dateOnly(day);
    for (int i = 0; i < grid.length; i++) {
      final d = grid[i];
      if (d != null && _dateOnly(d) == target) return i;
    }
    final first = DateTime(widget.visibleMonth.year, widget.visibleMonth.month, 1);
    final diff = target.difference(_dateOnly(first)).inDays;
    final startOffset = first.weekday - 1;
    final index = startOffset + diff;
    if (index >= 0 && index < grid.length) return index;
    return 0;
  }

  @override
  void didUpdateWidget(_AccessibleMonthGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visibleMonth != widget.visibleMonth ||
        oldWidget.selectedDay != widget.selectedDay) {
      _focusedIndex = _indexOf(widget.selectedDay);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Semantics(
      label: 'Calendar, use arrow keys to move, Enter or Space to select a day',
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        switch (event.logicalKey) {
          case LogicalKeyboardKey.arrowLeft:
            _moveFocus(-1);
            return KeyEventResult.handled;
          case LogicalKeyboardKey.arrowRight:
            _moveFocus(1);
            return KeyEventResult.handled;
          case LogicalKeyboardKey.arrowUp:
            _moveFocus(-_daysPerWeek);
            return KeyEventResult.handled;
          case LogicalKeyboardKey.arrowDown:
            _moveFocus(_daysPerWeek);
            return KeyEventResult.handled;
          case LogicalKeyboardKey.enter:
          case LogicalKeyboardKey.space:
            _selectFocused();
            return KeyEventResult.handled;
          default:
            return KeyEventResult.ignored;
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Table(
            columnWidths: {
              for (int i = 0; i < 7; i++) i: const FlexColumnWidth(1),
            },
            children: [
              TableRow(
                children: weekdays
                    .map((w) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Center(
                            child: Text(
                              w,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        ))
                    .toList(),
              ),
              ...List.generate(_maxRows, (row) {
                return TableRow(
                  children: List.generate(_daysPerWeek, (col) {
                    final index = row * _daysPerWeek + col;
                    final d = _dateAt(index);
                    if (d == null) return const SizedBox.shrink();
                    final selected = _dateOnly(widget.selectedDay) == _dateOnly(d);
                    final focused = index == _focusedIndex;
                    final allowed = _isAllowed(d);
                    final available = _isAvailable(d);
                    final disabled = !allowed ||
                        (widget.disableDaysWithoutAvailability && !available);
                    final av = widget.availabilityByYmd[_ymd(d)];
                    final dotCount = av != null ? _dotCountForCount(av.count) : 0;
                    final today = _dateOnly(d) == _dateOnly(DateTime.now());
                    final currentMonth = d.month == widget.visibleMonth.month;

                    return _CalendarDayCell(
                      date: d,
                      isSelected: selected,
                      isFocused: focused,
                      isDisabled: disabled,
                      isToday: today,
                      isCurrentMonth: currentMonth,
                      dotCount: dotCount,
                      hasAvailability: available,
                      onTap: disabled
                          ? null
                          : () => widget.onDaySelected(_dateOnly(d)),
                    );
                  }),
                );
              }),
            ],
          ),
        ],
        ),
      ),
    );
  }
}

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
    final first = firstAllowedDay ?? DateTime(effectiveMonth.year - 1);
    final last = lastAllowedDay ?? DateTime(effectiveMonth.year + 2);
    final selected = selectedDay ?? effectiveMonth;
    final avail = availabilityByYmd ?? {};

    final monthNames = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final monthLabel = '${monthNames[effectiveMonth.month - 1]} ${effectiveMonth.year}';

    final totalHeight = maxHeight ?? 320;
    return SizedBox(
      height: totalHeight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Semantics(
                label: 'Previous month',
                child: IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: loadingAvailability
                      ? null
                      : () {
                          final prev = DateTime(
                              effectiveMonth.year,
                              effectiveMonth.month - 1,
                              effectiveMonth.day.clamp(1, 28),
                          );
                          onMonthChanged?.call(prev);
                        },
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    monthLabel,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ),
              Semantics(
                label: 'Next month',
                child: IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: loadingAvailability
                      ? null
                      : () {
                          final next = DateTime(
                              effectiveMonth.year,
                              effectiveMonth.month + 1,
                              effectiveMonth.day.clamp(1, 28),
                          );
                          onMonthChanged?.call(next);
                        },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: _AccessibleMonthGrid(
                visibleMonth: effectiveMonth,
                selectedDay: selected,
                firstAllowedDay: first,
                lastAllowedDay: last,
                availabilityByYmd: avail,
                disableDaysWithoutAvailability: disableDaysWithoutAvailability,
                onDaySelected: onDaySelected ?? (_) {},
              ),
            ),
          ),
          if (trailingAction != null) trailingAction!,
          if (footer != null) footer!,
        ],
      ),
    );
  }
}

/// Legend explaining availability density: 1 dot = 1–2 slots, 2 dots = 3–5, 3 dots = 6+.
class InlineMonthCalendarLegend extends StatelessWidget {
  const InlineMonthCalendarLegend({super.key});

  static Widget _dot(BuildContext context, {double size = 6}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        shape: BoxShape.circle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme.labelSmall;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dot(context),
              const SizedBox(width: 4),
              Text('1–2 slots', style: theme),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dot(context),
                  const SizedBox(width: 2),
                  _dot(context),
                ],
              ),
              const SizedBox(width: 4),
              Text('3–5 slots', style: theme),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dot(context),
                  const SizedBox(width: 2),
                  _dot(context),
                  const SizedBox(width: 2),
                  _dot(context),
                ],
              ),
              const SizedBox(width: 4),
              Text('6+ slots', style: theme),
            ],
          ),
        ],
      ),
    );
  }
}
