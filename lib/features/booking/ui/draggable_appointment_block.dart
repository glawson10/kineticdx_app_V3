import 'package:flutter/material.dart';
import '../../../models/appointment.dart';

typedef AppointmentUpdateRequest = Future<void> Function({
  required String appointmentId,
  required DateTime newStart,
  required DateTime newEnd,
});

typedef AppointmentTap = void Function(Appointment appt);

class DraggableAppointmentBlock extends StatefulWidget {
  const DraggableAppointmentBlock({
    super.key,
    required this.appointment,
    required this.weekStart,
    required this.daysCount,
    required this.dayWidth,
    required this.headerHeight,
    required this.startHour,
    required this.endHour,
    required this.pxPerMinute,
    required this.snapMinutes,
    required this.onRequestUpdate,
    required this.onTap,
  });

  final Appointment appointment;
  final DateTime weekStart;
  final int daysCount;
  final double dayWidth;
  final double headerHeight;
  final int startHour;
  final int endHour;
  final double pxPerMinute;
  final int snapMinutes;

  final AppointmentUpdateRequest onRequestUpdate;
  final AppointmentTap onTap;

  @override
  State<DraggableAppointmentBlock> createState() =>
      _DraggableAppointmentBlockState();
}

enum _GestureMode { none, move, resizeBottom }

class _DraggableAppointmentBlockState extends State<DraggableAppointmentBlock> {
  static const double _bottomHandleHeight = 14;
  static const double _cornerBtnSize = 28;

  _GestureMode _mode = _GestureMode.none;
  bool _editing = false;
  bool _movePressed = false;

  // Draft values reflect the latest committed appointment state.
  late DateTime _draftStart;
  late DateTime _draftEnd;

  // Ghost values are what we preview during a gesture (snapped).
  DateTime? _ghostStart;
  DateTime? _ghostEnd;

  // Gesture baselines
  DateTime? _baseStart;
  DateTime? _baseEnd;
  double _accDx = 0;
  double _accDy = 0;

  @override
  void initState() {
    super.initState();
    _draftStart = widget.appointment.start;
    _draftEnd = widget.appointment.end;
  }

  @override
  void didUpdateWidget(covariant DraggableAppointmentBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If parent updates appointment (after save / stream update), refresh drafts
    if (!_editing) {
      _draftStart = widget.appointment.start;
      _draftEnd = widget.appointment.end;
      _ghostStart = null;
      _ghostEnd = null;
      _mode = _GestureMode.none;
      _movePressed = false;
      _baseStart = null;
      _baseEnd = null;
      _accDx = 0;
      _accDy = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final appt = widget.appointment;

    final gridStartMin = widget.startHour * 60;
    final gridEndMin = widget.endHour * 60;
    final gridSpanMin = gridEndMin - gridStartMin;

    // Day index from the *draft* start (committed) — not ghost.
    final dayIndex = _dayIndex(_draftStart, widget.weekStart);
    if (dayIndex < 0 || dayIndex >= widget.daysCount) return const SizedBox.shrink();

    final startMin = _draftStart.hour * 60 + _draftStart.minute;
    final durationMin = _draftEnd.difference(_draftStart).inMinutes;
    final safeDurationMin = durationMin <= 0 ? _stepMinutes : durationMin;

    final top = widget.headerHeight + (startMin - gridStartMin) * widget.pxPerMinute;
    final height = safeDurationMin * widget.pxPerMinute;

    final maxTop = widget.headerHeight + gridSpanMin * widget.pxPerMinute;
    final clampedTop = top.clamp(widget.headerHeight, maxTop);

    final maxHeight = gridSpanMin * widget.pxPerMinute;
    final clampedHeight = height.clamp(18.0, maxHeight);

    final left = dayIndex * widget.dayWidth + 6;
    final width = widget.dayWidth - 12;

    final details = <String>[
      if (!appt.isAdmin) appt.kindLabel,
      if (!appt.isAdmin && appt.serviceName.trim().isNotEmpty) appt.serviceName.trim(),
      if (!appt.isAdmin && appt.practitionerName.trim().isNotEmpty) appt.practitionerName.trim(),
    ].join(' • ');

    final timeLine = '${_fmt(_draftStart)}–${_fmt(_draftEnd)}';

    final previewLine = (_ghostStart != null && _ghostEnd != null)
        ? '${_fmt(_ghostStart!)}–${_fmt(_ghostEnd!)}  '
            '(${_ghostEnd!.difference(_ghostStart!).inMinutes}m)'
        : null;

    // Ghost overlay (shown while editing)
    final ghostLayout = (_ghostStart != null && _ghostEnd != null)
        ? _computeLayout(
            start: _ghostStart!,
            end: _ghostEnd!,
            gridStartMin: gridStartMin,
            gridSpanMin: gridSpanMin,
          )
        : null;

    return Positioned(
      left: left,
      top: clampedTop,
      width: width,
      height: clampedHeight,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) {},
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Ghost preview (behind the real block)
            if (_editing && ghostLayout != null)
              Positioned(
                left: (ghostLayout.left - left).clamp(-10000.0, 10000.0),
                top: ghostLayout.top - clampedTop,
                width: ghostLayout.width,
                height: ghostLayout.height,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black26, width: 2),
                      color: Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                ),
              ),

            // Real block
            Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(8),
              color: _bgColor(context, appt),
              child: Stack(
                children: [
                  // 🚨 Closure override badge (top-left)
                  if (appt.isClosureOverride)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade700,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 4,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                        child: const Text(
                          'Override',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),

                  // Main tap area
                  Positioned.fill(
                    bottom: _bottomHandleHeight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.onTap(appt),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          10,
                          8,
                          10 + _cornerBtnSize,
                          8,
                        ),
                        child: LayoutBuilder(
                          builder: (_, c) {
                            return _ResponsiveBlockText(
                              height: c.maxHeight,
                              title: appt.displayTitle,
                              details: details,
                              timeLine: timeLine,
                              status: appt.statusLabel,
                            );
                          },
                        ),
                      ),
                    ),
                  ),

                  // Top-right move button
                  Positioned(
                    top: 6,
                    right: 6,
                    width: _cornerBtnSize,
                    height: _cornerBtnSize,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (_) => _beginMove(),
                      onPanUpdate: (d) => _updateMove(d.delta),
                      onPanEnd: (_) => _endGesture(context),
                      onPanCancel: _cancelGesture,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 80),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.black12),
                          boxShadow: _movePressed
                              ? const []
                              : [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.18),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                        ),
                        child: const Icon(Icons.open_with, size: 16),
                      ),
                    ),
                  ),

                  // Bottom resize handle
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: _bottomHandleHeight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (_) => _beginResizeBottom(),
                      onPanUpdate: (d) => _updateResizeBottom(d.delta.dy),
                      onPanEnd: (_) => _endGesture(context),
                      onPanCancel: _cancelGesture,
                      child: Center(
                        child: Container(
                          width: 34,
                          height: 3,
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Preview chip
                  if (_editing && previewLine != null)
                    Positioned(
                      left: 6,
                      right: 40,
                      top: 6,
                      child: _PreviewChip(text: previewLine),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────
  // Gesture begin
  // ─────────────────────────────

  void _beginMove() {
    _baseStart = _draftStart;
    _baseEnd = _draftEnd;
    _accDx = 0;
    _accDy = 0;

    setState(() {
      _editing = true;
      _mode = _GestureMode.move;
      _movePressed = true;
      _ghostStart = _draftStart;
      _ghostEnd = _draftEnd;
    });
  }

  void _beginResizeBottom() {
    _baseStart = _draftStart;
    _baseEnd = _draftEnd;
    _accDx = 0;
    _accDy = 0;

    setState(() {
      _editing = true;
      _mode = _GestureMode.resizeBottom;
      _movePressed = false;
      _ghostStart = _draftStart;
      _ghostEnd = _draftEnd;
    });
  }

  void _cancelGesture() {
    setState(() {
      _editing = false;
      _mode = _GestureMode.none;
      _movePressed = false;
      _ghostStart = null;
      _ghostEnd = null;
      _baseStart = null;
      _baseEnd = null;
      _accDx = 0;
      _accDy = 0;
    });
  }

  // ─────────────────────────────
  // Gesture updates (ghost)
  // ─────────────────────────────

  void _updateMove(Offset delta) {
    if (_mode != _GestureMode.move) return;
    final bs = _baseStart;
    final be = _baseEnd;
    if (bs == null || be == null) return;

    _accDx += delta.dx;
    _accDy += delta.dy;

    // Compute requested day shift (but clamp to visible week)
    final rawDayDelta = (_accDx / widget.dayWidth).round();
    final currentIndex = _dayIndex(bs, widget.weekStart);
    final targetIndex = (currentIndex + rawDayDelta).clamp(0, widget.daysCount - 1);
    final dayDelta = targetIndex - currentIndex;

    final minutesDelta = _snapMinutes(_accDy / widget.pxPerMinute);

    final duration = be.difference(bs);
    final movedStart = bs.add(Duration(days: dayDelta, minutes: minutesDelta));
    final snappedStart = _snapDateTimeToGrid(movedStart);

    // Clamp to grid time bounds while preserving duration.
    final clamped = _clampStartEndToGrid(snappedStart, snappedStart.add(duration));

    setState(() {
      _ghostStart = clamped.$1;
      _ghostEnd = clamped.$2;
    });
  }

  void _updateResizeBottom(double dy) {
    if (_mode != _GestureMode.resizeBottom) return;
    final bs = _baseStart;
    final be = _baseEnd;
    if (bs == null || be == null) return;

    _accDy += dy;

    final minutesDelta = _snapMinutes(_accDy / widget.pxPerMinute);
    final nextEnd = be.add(Duration(minutes: minutesDelta));

    // must remain after start
    if (!nextEnd.isAfter(bs)) return;

    final snappedEnd = _snapDateTimeToGrid(nextEnd);

    // Clamp end to grid
    final clamped = _clampStartEndToGrid(bs, snappedEnd);

    setState(() {
      _ghostStart = clamped.$1;
      _ghostEnd = clamped.$2;
    });
  }

  // ─────────────────────────────
  // Commit
  // ─────────────────────────────

  Future<void> _endGesture(BuildContext context) async {
    final gs = _ghostStart;
    final ge = _ghostEnd;

    setState(() {
      _editing = false;
      _mode = _GestureMode.none;
      _movePressed = false;
      _ghostStart = null;
      _ghostEnd = null;
    });

    _baseStart = null;
    _baseEnd = null;
    _accDx = 0;
    _accDy = 0;

    if (gs == null || ge == null) return;
    if (gs == widget.appointment.start && ge == widget.appointment.end) return;

    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Confirm change'),
            content: Text('${_fmt(gs)} – ${_fmt(ge)}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirm'),
              ),
            ],
          ),
        ) ??
        false;

    if (!ok) return;

    setState(() {
      _draftStart = gs;
      _draftEnd = ge;
    });

    await widget.onRequestUpdate(
      appointmentId: widget.appointment.id,
      newStart: gs,
      newEnd: ge,
    );
  }

  // ─────────────────────────────
  // Helpers
  // ─────────────────────────────

  int get _stepMinutes => widget.snapMinutes <= 0 ? 5 : widget.snapMinutes;

  int _dayIndex(DateTime d, DateTime weekStart) {
    final a = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final b = DateTime(d.year, d.month, d.day);
    return b.difference(a).inDays;
  }

  int _snapMinutes(double rawMinutes) {
    final step = _stepMinutes;
    return (rawMinutes / step).round() * step;
  }

  DateTime _snapDateTimeToGrid(DateTime dt) {
    final step = _stepMinutes;
    final minutes = dt.hour * 60 + dt.minute;
    final snapped = (minutes / step).round() * step;
    final h = snapped ~/ 60;
    final m = snapped % 60;
    return DateTime(dt.year, dt.month, dt.day, h, m);
  }

  /// Clamps start/end to the visible grid window:
  /// - start >= gridStart
  /// - end <= gridEnd
  /// - end > start (at least one step)
  (DateTime, DateTime) _clampStartEndToGrid(DateTime start, DateTime end) {
    final gridStart = DateTime(start.year, start.month, start.day, widget.startHour, 0);
    final gridEnd = DateTime(start.year, start.month, start.day, widget.endHour, 0);

    var s = start;
    var e = end;

    // Minimum duration
    final minDur = Duration(minutes: _stepMinutes);
    if (!e.isAfter(s)) e = s.add(minDur);

    // Clamp end first (for resize)
    if (e.isAfter(gridEnd)) e = gridEnd;

    // Clamp start
    if (s.isBefore(gridStart)) {
      final dur = e.difference(s);
      s = gridStart;
      e = s.add(dur);
      if (e.isAfter(gridEnd)) {
        // If duration can't fit, pin to end
        e = gridEnd;
        s = e.subtract(dur);
        if (s.isBefore(gridStart)) {
          s = gridStart;
          e = s.add(minDur);
        }
      }
    }

    // If end got pinned before start, fix
    if (!e.isAfter(s)) e = s.add(minDur);
    if (e.isAfter(gridEnd)) e = gridEnd;
    if (!e.isAfter(s)) e = s.add(minDur);

    // Final snap to grid minutes again (keeps things tidy)
    s = _snapDateTimeToGrid(s);
    e = _snapDateTimeToGrid(e);
    if (!e.isAfter(s)) e = s.add(minDur);
    if (e.isAfter(gridEnd)) e = gridEnd;
    if (!e.isAfter(s)) e = s.add(minDur);

    return (s, e);
  }

  _Layout _computeLayout({
    required DateTime start,
    required DateTime end,
    required int gridStartMin,
    required int gridSpanMin,
  }) {
    final dayIndex =
        _dayIndex(start, widget.weekStart).clamp(0, widget.daysCount - 1);

    final startMin = start.hour * 60 + start.minute;
    final durationMin = end.difference(start).inMinutes;
    final safeDuration = durationMin <= 0 ? _stepMinutes : durationMin;

    final top = widget.headerHeight + (startMin - gridStartMin) * widget.pxPerMinute;
    final height = safeDuration * widget.pxPerMinute;

    final maxTop = widget.headerHeight + gridSpanMin * widget.pxPerMinute;
    final clampedTop = top.clamp(widget.headerHeight, maxTop);

    final maxHeight = gridSpanMin * widget.pxPerMinute;
    final clampedHeight = height.clamp(18.0, maxHeight);

    final left = dayIndex * widget.dayWidth + 6;
    final width = widget.dayWidth - 12;

    return _Layout(left: left, top: clampedTop, width: width, height: clampedHeight);
  }

  Color _bgColor(BuildContext context, Appointment appt) {
    final scheme = Theme.of(context).colorScheme;
    if (appt.isAdmin) return scheme.secondaryContainer;

    switch (appt.status.toLowerCase()) {
      case 'attended':
        return scheme.tertiaryContainer;
      case 'cancelled':
      case 'missed':
        return scheme.errorContainer;
      case 'booked':
      default:
        return scheme.primaryContainer;
    }
  }

  static String _fmt(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _Layout {
  final double left;
  final double top;
  final double width;
  final double height;
  const _Layout({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}

class _ResponsiveBlockText extends StatelessWidget {
  const _ResponsiveBlockText({
    required this.height,
    required this.title,
    required this.details,
    required this.timeLine,
    required this.status,
  });

  final double height;
  final String title;
  final String details;
  final String timeLine;
  final String status;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    if (height < 22) {
      return Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: t.textTheme.bodySmall
            ?.copyWith(fontWeight: FontWeight.w800, fontSize: 10),
      );
    }

    if (height < 34) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w800, fontSize: 11),
          ),
          Text(
            timeLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w800, fontSize: 10),
          ),
        ],
      );
    }

    final showDetails = height >= 46 && details.trim().isNotEmpty;
    final showStatus = height >= 60;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w800, fontSize: 12),
        ),
        if (showDetails)
          Text(
            details,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w600, fontSize: 10.5),
          ),
        Text(
          timeLine,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.textTheme.bodySmall
              ?.copyWith(fontWeight: FontWeight.w800, fontSize: 10.5),
        ),
        if (showStatus)
          Text(
            status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w700, fontSize: 10.0),
          ),
      ],
    );
  }
}

class _PreviewChip extends StatelessWidget {
  const _PreviewChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black12),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }
}
