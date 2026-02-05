// lib/features/booking/ui/booking_calendar_screen.dart
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/clinic_context.dart';
import '../../../data/repositories/appointments_repository.dart'
    show AppointmentsRepository, ClinicClosureConflictException;
import '../../../data/repositories/services_repository.dart';
import '../../../models/appointment.dart';
import '../../../models/service.dart';
import 'draggable_appointment_block.dart';

import '../../patients/patient_details_screen.dart';

class BookingCalendarScreen extends StatefulWidget {
  /// If provided (e.g. from Audit), the calendar opens on that week/time.
  final DateTime? initialFocus;

  /// Optional: from Audit - will jump to that appointment if present in week stream.
  final String? initialAppointmentId;

  /// If you ever want to use this screen OUTSIDE the ClinicianShell,
  /// set this to true and it will render its own Scaffold/AppBar.
  final bool standaloneScaffold;

  const BookingCalendarScreen({
    super.key,
    this.initialFocus,
    this.initialAppointmentId,
    this.standaloneScaffold = false,
  });

  static Route<void> route({
    DateTime? focus,
    String? appointmentId,
    bool standaloneScaffold = true,
  }) {
    return MaterialPageRoute(
      builder: (_) => BookingCalendarScreen(
        initialFocus: focus,
        initialAppointmentId: appointmentId,
        standaloneScaffold: standaloneScaffold,
      ),
    );
  }

  @override
  State<BookingCalendarScreen> createState() => _BookingCalendarScreenState();
}

class _BookingCalendarScreenState extends State<BookingCalendarScreen>
    with SingleTickerProviderStateMixin {
  late DateTime _weekStart; // Monday
  bool _fitWeek = false;

  // ✅ Practitioner filter
  String? _selectedPractitionerId; // null = all

  static const double _timeGutterWidth = 64;
  static const double _headerHeight = 48;

  /// Defaults if no opening-hours are configured yet.
  static const int _fallbackStartHour = 7;
  static const int _fallbackEndHour = 20;

  // Drag snap
  static const int _dragSnapMinutes = 5;

  // Audit jump
  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();
  bool _didInitialAutoJump = false;

  // Highlight (audit)
  DateTime? _highlightStart;
  DateTime? _highlightEnd;
  int _highlightDayIndex = -1;

  late final AnimationController _pulseCtrl;

  // ───────────────────────────────────────────────────────────────────────────
  // ✅ Unified opening-hours source: Cloud Function listPublicSlotsFn
  // ───────────────────────────────────────────────────────────────────────────
  static const String _tz = 'Europe/Prague';

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'europe-west3');

  @override
  void initState() {
    super.initState();
    _weekStart = _startOfWeek(widget.initialFocus ?? DateTime.now());

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<_WeeklyHours> _weeklyHoursFromListPublicSlots({
    required String clinicId,
    required DateTime weekStartLocal,
    required String? practitionerId,
  }) async {
    final fromLocal = DateTime(
      weekStartLocal.year,
      weekStartLocal.month,
      weekStartLocal.day,
      0,
      0,
    );
    final toLocal = fromLocal.add(const Duration(days: 7));

    final payload = <String, dynamic>{
      'clinicId': clinicId,
      'purpose': 'openingWindows',
      'serviceId': '',
      'practitionerId': (practitionerId ?? '').trim(),
      'fromUtc': fromLocal.toUtc().toIso8601String(),
      'toUtc': toLocal.toUtc().toIso8601String(),
      'tz': _tz,
    };

    final callable = _functions.httpsCallable('listPublicSlotsFn');
    final callResult = await callable.call(payload);
    final data = callResult.data;

    if (data is! Map) {
      throw StateError(
        'listPublicSlots returned unexpected payload (not a map): $data',
      );
    }

    // ✅ Preferred: server-provided weeklyHours (authoritative)
    final rawWeekly = data['weeklyHours'];
    if (rawWeekly is Map) {
      return _WeeklyHours.fromServerWeeklyHours(
        Map<String, dynamic>.from(rawWeekly),
      );
    }

    // Fallback: older function shape -> derive windows from slots
    final rawSlots = (data['slots'] as List?) ?? const [];
    final ranges = rawSlots
        .whereType<Map>()
        .map((m) => _UtcRange(
              startUtc: DateTime.fromMillisecondsSinceEpoch(
                (m['startMs'] as num).toInt(),
                isUtc: true,
              ),
              endUtc: DateTime.fromMillisecondsSinceEpoch(
                (m['endMs'] as num).toInt(),
                isUtc: true,
              ),
            ))
        .toList();

    return _WeeklyHours.fromUtcOpenWindows(ranges);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // ✅ Closure override permission + dialog
  // ───────────────────────────────────────────────────────────────────────────

  bool _canOverrideClosures(BuildContext context) {
    final clinicCtx = context.read<ClinicContext>();
    if (!clinicCtx.hasClinic) return false;
    return clinicCtx.session.permissions.has('settings.write');
  }

  Future<bool> _confirmClosedOverrideDialog() async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Clinic is closed'),
            content: const Text(
              'This time is marked as closed.\n\nSave anyway?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save anyway'),
              ),
            ],
          ),
        ) ??
        false;

    return ok;
  }

  void _showClosedSnack(
      {String message = 'Clinic is closed during this time.'}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Week navigation
  // ───────────────────────────────────────────────────────────────────────────

  void _prevWeek() => setState(() {
        _weekStart = _weekStart.subtract(const Duration(days: 7));
        _didInitialAutoJump = true;
      });

  void _nextWeek() => setState(() {
        _weekStart = _weekStart.add(const Duration(days: 7));
        _didInitialAutoJump = true;
      });

  void _goCurrentWeek() => setState(() {
        _weekStart = _startOfWeek(DateTime.now());
        _didInitialAutoJump = true;
      });

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _weekStart,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (!mounted) return;
    if (picked == null) return;
    setState(() {
      _weekStart = _startOfWeek(picked);
      _didInitialAutoJump = true;
    });
  }

  void _toggleFitWeek() {
    setState(() => _fitWeek = !_fitWeek);

    if (!_fitWeek) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_horizontalController.hasClients) _horizontalController.jumpTo(0);
      if (_verticalController.hasClients) _verticalController.jumpTo(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final clinicId = context.watch<ClinicContext>().clinicId;
    final body = _buildBody(context, clinicId);

    if (!widget.standaloneScaffold) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Booking calendar')),
      body: body,
    );
  }

  Widget _buildBody(BuildContext context, String clinicId) {
    final clinicCtx = context.watch<ClinicContext>();

    if (!clinicCtx.hasClinic) {
      return const _FatalPanel(
        title: 'No clinic selected',
        message: 'Go back to clinic picker and select a clinic.',
      );
    }

    if (!clinicCtx.hasSession) {
      return const Center(child: CircularProgressIndicator());
    }

    final perms = clinicCtx.session.permissions;
    final canReadSchedule = perms.has('schedule.read');
    final canWriteSchedule = perms.has('schedule.write');

    if (!canReadSchedule) {
      return const _FatalPanel(
        title: 'No access',
        message:
            'You do not have permission to view the schedule (schedule.read).',
      );
    }

    final apptRepo = context.read<AppointmentsRepository>();
    final servicesRepo = context.read<ServicesRepository>();

    final clinicDoc = FirebaseFirestore.instance
        .collection('clinics')
        .doc(clinicId)
        .snapshots();

    final closuresStream = FirebaseFirestore.instance
        .collection('clinics')
        .doc(clinicId)
        .collection('closures')
        .where('active', isEqualTo: true)
        .orderBy('fromAt')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => _ClinicClosure.fromFirestore(d.id, d.data()))
            .toList());

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: clinicDoc,
      builder: (context, clinicSnap) {
        if (clinicSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (clinicSnap.hasError) {
          return _FatalPanel(
            title: 'Failed to load clinic settings',
            message: clinicSnap.error.toString(),
          );
        }

        final clinicData = clinicSnap.data?.data() ?? const <String, dynamic>{};

        final settings = (clinicData['settings'] is Map)
            ? Map<String, dynamic>.from(clinicData['settings'] as Map)
            : <String, dynamic>{};

        final appearance = (settings['appearance'] is Map)
            ? Map<String, dynamic>.from(settings['appearance'] as Map)
            : <String, dynamic>{};

        final bookingStructure = (settings['bookingStructure'] is Map)
            ? Map<String, dynamic>.from(settings['bookingStructure'] as Map)
            : <String, dynamic>{};

        final double baseSlotHeight =
            (appearance['slotHeight'] as num?)?.toDouble() ?? 48.0;

        final int adminGridMinutes =
            (bookingStructure['adminGridMinutes'] as num?)?.toInt() ?? 15;
        final int defaultSlotMinutes =
            (bookingStructure['defaultSlotMinutes'] as num?)?.toInt() ?? 20;

        return FutureBuilder<_WeeklyHours>(
          future: _weeklyHoursFromListPublicSlots(
            clinicId: clinicId,
            weekStartLocal: _weekStart,
            practitionerId: _selectedPractitionerId,
          ),
          builder: (context, hoursSnap) {
            if (hoursSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (hoursSnap.hasError) {
              return _FatalPanel(
                title: 'Failed to load opening hours (listPublicSlotsFn)',
                message: '${hoursSnap.error}\n\n'
                    'Check that Cloud Function "listPublicSlotsFn" exists in region europe-west3, '
                    'and that the current user has permission to call it.',
              );
            }

            final weeklyHours =
                hoursSnap.data ?? _WeeklyHours.fromFirestore(null);

            const int daysCount = 7;
            final List<DateTime> days = List.generate(
              daysCount,
              (i) => _weekStart.add(Duration(days: i)),
            );
            final weekEnd = _weekStart.add(const Duration(days: 6));

            final bounds = _computeGridBoundsForWeek(
              days: days,
              weeklyHours: weeklyHours,
              fallbackStartHour: _fallbackStartHour,
              fallbackEndHour: _fallbackEndHour,
            );
            final int gridStartHour = bounds.startHour;
            final int gridEndHour = bounds.endHour;

            return StreamBuilder<List<_ClinicClosure>>(
              stream: closuresStream,
              builder: (context, closureSnap) {
                if (closureSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (closureSnap.hasError) {
                  return _FatalPanel(
                    title: 'Failed to load clinic closures',
                    message: '${closureSnap.error}\n\n'
                        'Confirm your Firestore rules allow clinicians to read closures.\n'
                        'Path: clinics/{clinicId}/closures',
                  );
                }

                final closures = closureSnap.data ?? const <_ClinicClosure>[];

                bool isClosedAt(DateTime tLocal) {
                  final t = tLocal.toUtc();
                  for (final c in closures) {
                    if (!c.active) continue;
                    if (t.isBefore(c.fromAtUtc)) continue;
                    if (t.isAtSameMomentAs(c.toAtUtc) || t.isAfter(c.toAtUtc)) {
                      continue;
                    }
                    return true;
                  }
                  return false;
                }

                bool overlapsClosure(DateTime startLocal, DateTime endLocal) {
                  final start = startLocal.toUtc();
                  final end = endLocal.toUtc();
                  for (final c in closures) {
                    if (!c.active) continue;
                    if (start.isBefore(c.toAtUtc) && end.isAfter(c.fromAtUtc)) {
                      return true;
                    }
                  }
                  return false;
                }

                return StreamBuilder<List<Appointment>>(
                  stream: apptRepo.watchAppointmentsForWeek(
                    clinicId: clinicId,
                    weekStart: _weekStart,
                    practitionerId: _selectedPractitionerId,
                  ),
                  builder: (context, apptSnap) {
                    if (apptSnap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (apptSnap.hasError) {
                      return _FatalPanel(
                        title: 'Failed to load appointments',
                        message: '${apptSnap.error}\n\n'
                            'Check Firestore appointment fields:\n'
                            '• appointments.startAt and appointments.endAt must be Timestamp\n'
                            '• migration may also include legacy fields start/end.\n\n'
                            'Also confirm your Firestore rules allow schedule.read for this user.',
                      );
                    }

                    final appts = apptSnap.data ?? const <Appointment>[];

                    return LayoutBuilder(
                      builder: (context, c) {
                        final isWide = c.maxWidth >= 900;
                        final availableWidth = c.maxWidth;
                        final availableHeight = c.maxHeight;

                        final baseDayWidth = isWide ? 220.0 : 160.0;

                        final fitDayWidth =
                            ((availableWidth - _timeGutterWidth) / daysCount)
                                .clamp(90.0, 420.0);

                        final dayWidth = _fitWeek ? fitDayWidth : baseDayWidth;

                        final rows = (((gridEndHour - gridStartHour) * 60) /
                                adminGridMinutes)
                            .ceil();

                        const approxTopChrome = 110.0;

                        final fitViewportHeight =
                            (availableHeight - approxTopChrome)
                                .clamp(200.0, double.infinity);

                        final fitSlotHeight =
                            ((fitViewportHeight - _headerHeight) / rows)
                                .clamp(18.0, 96.0);

                        final effectiveSlotHeight =
                            _fitWeek ? fitSlotHeight : baseSlotHeight;

                        final double pxPerMinute =
                            effectiveSlotHeight / adminGridMinutes;

                        final gridHeight =
                            _headerHeight + rows * effectiveSlotHeight;

                        _maybeAutoJumpAndPrimeHighlight(
                          days: days,
                          dayWidth: dayWidth,
                          adminGridMinutes: adminGridMinutes,
                          slotHeight: effectiveSlotHeight,
                          appts: appts,
                          startHour: gridStartHour,
                          endHour: gridEndHour,
                        );

                        return Column(
                          children: [
                            // ✅ Top bar WITH inline dropdown
                            _TopBarWithPractitioner(
                              clinicId: clinicId,
                              rangeText:
                                  '${_fmtShort(_weekStart)} → ${_fmtShort(weekEnd)}',
                              value: _selectedPractitionerId,
                              onChanged: (v) {
                                setState(() {
                                  _selectedPractitionerId = v;
                                  _didInitialAutoJump = true;
                                });
                              },
                              onPrev: _prevWeek,
                              onNext: _nextWeek,
                              onPickDate: _pickDate,
                              onCurrentWeek: _goCurrentWeek,
                              fitWeek: _fitWeek,
                              onToggleFit: _toggleFitWeek,
                            ),

                            const Divider(height: 1),
                            const _DevPermissionHintBanner(),

                            Expanded(
                              child: SingleChildScrollView(
                                controller: _verticalController,
                                physics: _fitWeek
                                    ? const NeverScrollableScrollPhysics()
                                    : null,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _TimeGutter(
                                      startHour: gridStartHour,
                                      endHour: gridEndHour,
                                      slotMinutes: adminGridMinutes,
                                      headerHeight: _headerHeight,
                                      slotHeight: effectiveSlotHeight,
                                    ),
                                    Expanded(
                                      child: SingleChildScrollView(
                                        controller: _horizontalController,
                                        physics: _fitWeek
                                            ? const NeverScrollableScrollPhysics()
                                            : null,
                                        scrollDirection: Axis.horizontal,
                                        child: SizedBox(
                                          width: dayWidth * daysCount,
                                          height: gridHeight,
                                          child: Stack(
                                            children: [
                                              _WeekGrid(
                                                days: days,
                                                dayWidth: dayWidth,
                                                headerHeight: _headerHeight,
                                                startHour: gridStartHour,
                                                endHour: gridEndHour,
                                                slotMinutes: adminGridMinutes,
                                                slotHeight: effectiveSlotHeight,
                                                weeklyHours: weeklyHours,
                                                onTapSlot: (slotStart) {
                                                  if (!canWriteSchedule) {
                                                    _showClosedSnack(
                                                      message:
                                                          'Read-only: schedule.write required to create bookings.',
                                                    );
                                                    return;
                                                  }

                                                  if (!weeklyHours
                                                      .isWithinOpeningHours(
                                                          slotStart)) {
                                                    _showClosedSnack();
                                                    return;
                                                  }

                                                  if (isClosedAt(slotStart)) {
                                                    _showClosedSnack(
                                                      message:
                                                          'Clinic is closed (closure) during this time.',
                                                    );
                                                    return;
                                                  }

                                                  _startBookingFlowDialog(
                                                    clinicId: clinicId,
                                                    apptRepo: apptRepo,
                                                    servicesRepo: servicesRepo,
                                                    slotStart: slotStart,
                                                    adminGridMinutes:
                                                        adminGridMinutes,
                                                    defaultSlotMinutes:
                                                        defaultSlotMinutes,
                                                  );
                                                },
                                              ),
                                              _ClosureOverlayLayer(
                                                closures: closures,
                                                days: days,
                                                dayWidth: dayWidth,
                                                headerHeight: _headerHeight,
                                                startHour: gridStartHour,
                                                endHour: gridEndHour,
                                                pxPerMinute: pxPerMinute,
                                              ),
                                              _AuditHighlightOverlay(
                                                pulse: _pulseCtrl,
                                                dayWidth: dayWidth,
                                                headerHeight: _headerHeight,
                                                startHour: gridStartHour,
                                                pxPerMinute: pxPerMinute,
                                                dayIndex: _highlightDayIndex,
                                                startLocal: _highlightStart,
                                                endLocal: _highlightEnd,
                                              ),
                                              for (final a in appts)
                                                DraggableAppointmentBlock(
                                                  key: ValueKey('appt_${a.id}'),
                                                  appointment: a,
                                                  weekStart: _weekStart,
                                                  daysCount: daysCount,
                                                  dayWidth: dayWidth,
                                                  headerHeight: _headerHeight,
                                                  startHour: gridStartHour,
                                                  endHour: gridEndHour,
                                                  pxPerMinute: pxPerMinute,
                                                  snapMinutes: _dragSnapMinutes,
                                                  onRequestUpdate: ({
                                                    required String
                                                        appointmentId,
                                                    required DateTime newStart,
                                                    required DateTime newEnd,
                                                  }) async {
                                                    if (!canWriteSchedule) {
                                                      _showClosedSnack(
                                                        message:
                                                            'Read-only: schedule.write required to move bookings.',
                                                      );
                                                      return;
                                                    }

                                                    final okHours = weeklyHours
                                                            .isWithinOpeningHours(
                                                          newStart,
                                                        ) &&
                                                        weeklyHours
                                                            .isWithinOpeningHours(
                                                          newEnd.subtract(
                                                            const Duration(
                                                                minutes: 1),
                                                          ),
                                                        );

                                                    if (!okHours) {
                                                      _showClosedSnack();
                                                      return;
                                                    }

                                                    final isOverlap =
                                                        overlapsClosure(
                                                            newStart, newEnd);

                                                    if (!isOverlap) {
                                                      try {
                                                        await _updateAppointment(
                                                          apptRepo: apptRepo,
                                                          clinicId: clinicId,
                                                          appointmentId:
                                                              appointmentId,
                                                          start: newStart,
                                                          end: newEnd,
                                                          allowClosedOverride:
                                                              false,
                                                        );
                                                      } on ClinicClosureConflictException {
                                                        _showClosedSnack(
                                                          message:
                                                              'Clinic closure conflict.',
                                                        );
                                                      }
                                                      return;
                                                    }

                                                    if (!_canOverrideClosures(
                                                        context)) {
                                                      _showClosedSnack();
                                                      return;
                                                    }

                                                    final ok =
                                                        await _confirmClosedOverrideDialog();
                                                    if (!mounted || !ok) return;

                                                    try {
                                                      await _updateAppointment(
                                                        apptRepo: apptRepo,
                                                        clinicId: clinicId,
                                                        appointmentId:
                                                            appointmentId,
                                                        start: newStart,
                                                        end: newEnd,
                                                        allowClosedOverride:
                                                            true,
                                                      );
                                                    } on ClinicClosureConflictException {
                                                      _showClosedSnack(
                                                        message:
                                                            'Clinic closure conflict.',
                                                      );
                                                    }
                                                  },
                                                  onTap: (appt) =>
                                                      _onTapAppointment(
                                                    clinicId: clinicId,
                                                    appt: appt,
                                                    apptRepo: apptRepo,
                                                    servicesRepo: servicesRepo,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  void _maybeAutoJumpAndPrimeHighlight({
    required List<DateTime> days,
    required double dayWidth,
    required int adminGridMinutes,
    required double slotHeight,
    required List<Appointment> appts,
    required int startHour,
    required int endHour,
  }) {
    if (_didInitialAutoJump) return;

    DateTime? target;
    DateTime? end;
    int dayIndex = -1;

    final apptId = (widget.initialAppointmentId ?? '').trim();
    if (apptId.isNotEmpty) {
      final match = appts.where((a) => a.id == apptId).toList();
      if (match.isNotEmpty) {
        target = match.first.start;
        end = match.first.end;
      }
    }

    target ??= widget.initialFocus;
    if (target != null && end == null) {
      end = target.add(const Duration(minutes: 30));
    }

    if (target == null) return;

    dayIndex = days.indexWhere((d) => DateUtils.isSameDay(d, target!));

    _highlightStart = target;
    _highlightEnd = end;
    _highlightDayIndex = dayIndex;

    _didInitialAutoJump = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (dayIndex >= 0 && _horizontalController.hasClients) {
        final rawX = dayIndex * dayWidth - 24.0;
        final x =
            rawX.clamp(0.0, _horizontalController.position.maxScrollExtent);
        _horizontalController.jumpTo(x);
      }

      final startMins = startHour * 60;
      final endMins = endHour * 60;

      final mins = (target!.hour * 60) + target.minute;
      final clampedMins = mins.clamp(startMins, endMins);
      final minsFromStart = clampedMins - startMins;

      final rowsFromTop = minsFromStart / adminGridMinutes;
      final rawY = (_headerHeight + rowsFromTop * slotHeight) - 80.0;

      if (_verticalController.hasClients) {
        final y = rawY.clamp(0.0, _verticalController.position.maxScrollExtent);
        _verticalController.jumpTo(y);
      }

      Future<void>.delayed(const Duration(seconds: 6)).then((_) {
        if (!mounted) return;
        setState(() {
          _highlightStart = null;
          _highlightEnd = null;
          _highlightDayIndex = -1;
        });
      });
    });
  }

  // ---------------------------------------------------------------------------
  // Tap actions
  // ---------------------------------------------------------------------------

  Future<void> _onTapAppointment({
    required String clinicId,
    required Appointment appt,
    required AppointmentsRepository apptRepo,
    required ServicesRepository servicesRepo,
  }) async {
    if (appt.isAdmin) {
      final action = await _showAdminActions(appt);
      if (!mounted || action == null) return;

      if (action == 'delete') {
        final ok = await _confirm('Remove admin block?');
        if (!mounted || !ok) return;

        try {
          await _deleteAppointmentFn(
              clinicId: clinicId, appointmentId: appt.id);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Admin block removed')),
          );
        } on FirebaseFunctionsException catch (e, st) {
          debugPrint('[BookingCalendar] deleteAppointmentFn error: $e\n$st');
          if (!mounted) return;
          await _showFatalDialog(
            title: 'Remove admin block failed',
            message:
                'code: ${e.code}\nmessage: ${e.message}\ndetails: ${e.details}',
          );
        }
      }
      return;
    }

    final action = await _showBookingActions(appt);
    if (!mounted || action == null) return;

    if (action == 'patient') {
      final pid = appt.patientId.trim();
      if (pid.isEmpty) return;

      Navigator.of(context).push(
        PatientDetailsScreen.routeEdit(
          clinicId: clinicId,
          patientId: pid,
        ),
      );
      return;
    }

    if (action == 'edit') {
      final edited = await showDialog<_EditBookingResult>(
        context: context,
        builder: (_) => _EditBookingDialog(
          clinicId: clinicId,
          appt: appt,
          servicesRepo: servicesRepo,
        ),
      );

      if (!mounted || edited == null) return;

      final newEnd = appt.start.add(Duration(minutes: edited.minutes));

      try {
        await apptRepo.updateAppointmentDetails(
          clinicId: clinicId,
          appointmentId: appt.id,
          start: appt.start,
          end: newEnd,
          kind: edited.kind,
          serviceId: edited.serviceId,
        );
      } on ClinicClosureConflictException {
        _showClosedSnack();
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking updated')),
      );
      return;
    }

    if (action.startsWith('status:')) {
      final status = action.split(':')[1];
      try {
        await _updateAppointmentStatusFn(
          clinicId: clinicId,
          appointmentId: appt.id,
          status: status,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status updated to $status')),
        );
      } on FirebaseFunctionsException catch (e, st) {
        debugPrint(
            '[BookingCalendar] updateAppointmentStatusFn error: $e\n$st');
        if (!mounted) return;
        await _showFatalDialog(
          title: 'Update status failed',
          message:
              'code: ${e.code}\nmessage: ${e.message}\ndetails: ${e.details}',
        );
      }
      return;
    }

    if (action == 'delete') {
      final ok = await _confirm('Remove appointment?');
      if (!mounted || !ok) return;

      try {
        await _deleteAppointmentFn(clinicId: clinicId, appointmentId: appt.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Appointment removed')),
        );
      } on FirebaseFunctionsException catch (e, st) {
        debugPrint('[BookingCalendar] deleteAppointmentFn error: $e\n$st');
        if (!mounted) return;
        await _showFatalDialog(
          title: 'Remove appointment failed',
          message:
              'code: ${e.code}\nmessage: ${e.message}\ndetails: ${e.details}',
        );
      }
      return;
    }
  }

  Future<String?> _showAdminActions(Appointment appt) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove admin block'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _showBookingActions(Appointment appt) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_calendar_outlined),
              title: const Text('Edit booking'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            if (appt.patientId.trim().isNotEmpty)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Patient details'),
                onTap: () => Navigator.pop(context, 'patient'),
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Mark attended'),
              onTap: () => Navigator.pop(context, 'status:attended'),
            ),
            ListTile(
              leading: const Icon(Icons.cancel_outlined),
              title: const Text('Mark cancelled'),
              onTap: () => Navigator.pop(context, 'status:cancelled'),
            ),
            ListTile(
              leading: const Icon(Icons.do_not_disturb_on_outlined),
              title: const Text('Mark missed'),
              onTap: () => Navigator.pop(context, 'status:missed'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove appointment'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirm(String msg) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Confirm'),
            content: Text(msg),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('OK'),
              ),
            ],
          ),
        ) ??
        false;
    return ok;
  }

  Future<void> _deleteAppointmentFn({
    required String clinicId,
    required String appointmentId,
  }) async {
    await _functions.httpsCallable('deleteAppointmentFn').call({
      'clinicId': clinicId,
      'appointmentId': appointmentId,
    });
  }

  Future<void> _updateAppointmentStatusFn({
    required String clinicId,
    required String appointmentId,
    required String status,
  }) async {
    await _functions.httpsCallable('updateAppointmentStatusFn').call({
      'clinicId': clinicId,
      'appointmentId': appointmentId,
      'status': status,
    });
  }

  // ---------------------------------------------------------------------------
  // Booking flow
  // ---------------------------------------------------------------------------

  Future<void> _startBookingFlowDialog({
    required String clinicId,
    required AppointmentsRepository apptRepo,
    required ServicesRepository servicesRepo,
    required DateTime slotStart,
    required int adminGridMinutes,
    required int defaultSlotMinutes,
  }) async {
    try {
      final action = await showDialog<_BookingAction>(
        context: context,
        builder: (_) => _ActionDialog(slotStart: slotStart),
      );
      if (!mounted) return;
      if (action == null) return;

      _PickedService? pickedService;
      _PickedPractitioner? pickedPractitioner;

      if (action != _BookingAction.adminBlock) {
        pickedService = await showDialog<_PickedService>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _ServicePickerDialog(
            clinicId: clinicId,
            servicesRepo: servicesRepo,
          ),
        );
        if (!mounted) return;
        if (pickedService == null) return;

        pickedPractitioner = await showDialog<_PickedPractitioner>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _PractitionerPickerDialog(clinicId: clinicId),
        );
        if (!mounted) return;
        if (pickedPractitioner == null) return;

        if (!pickedPractitioner.canScheduleWrite) {
          if (!mounted) return;
          await _showFatalDialog(
            title: 'Cannot book this practitioner',
            message:
                'Selected practitioner does not have schedule.write permission.',
          );
          return;
        }
      }

      final suggestedInitial = (pickedService?.defaultMinutes ?? 0) > 0
          ? pickedService!.defaultMinutes
          : defaultSlotMinutes;

      final lengthOptions = _buildLengthOptions(
        adminGridMinutes: adminGridMinutes,
        include: {15, 20, 30, 45, 60, 90, 120},
        maxMinutes: 240,
      );

      final minutes = await showDialog<int>(
        context: context,
        builder: (_) => _LengthPickerDialog(
          initial: suggestedInitial,
          options: lengthOptions,
        ),
      );
      if (!mounted) return;
      if (minutes == null) return;

      final end = slotStart.add(Duration(minutes: minutes));

      if (action == _BookingAction.adminBlock) {
        final ok = await showDialog<bool>(
              context: context,
              builder: (_) =>
                  _ConfirmAdminBlockDialog(slotStart: slotStart, slotEnd: end),
            ) ??
            false;

        if (!mounted) return;
        if (!ok) return;

        await apptRepo.createAppointment(
          clinicId: clinicId,
          kind: 'admin',
          start: slotStart,
          end: end,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Created admin block ${_fmtTime(slotStart)}–${_fmtTime(end)}'),
          ),
        );
        return;
      }

      final patientMode = await showDialog<_PatientMode>(
        context: context,
        builder: (_) => _PatientModeDialog(action: action),
      );
      if (!mounted) return;
      if (patientMode == null) return;

      String patientId;
      _PatientSnapshot patientSnapshot;

      if (patientMode == _PatientMode.createNew) {
        final created = await showDialog<_PatientSnapshot>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const _NewPatientDialog(),
        );

        if (!mounted) return;
        if (created == null) return;

        final newId =
            await _createPatientInClinic(clinicId: clinicId, patient: created);
        if (!mounted) return;

        patientId = newId;
        patientSnapshot = created.copyWith(id: newId);
      } else {
        final picked = await showDialog<_PatientSnapshot>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _PatientFinderDialog(clinicId: clinicId),
        );

        if (!mounted) return;
        if (picked == null) return;
        if (picked.id == null) return;

        patientId = picked.id!;
        patientSnapshot = picked;
      }

      final kind = (action == _BookingAction.newPatient) ? 'new' : 'followup';

      final ok = await showDialog<bool>(
            context: context,
            builder: (_) => _ConfirmBookingDialog(
              kind: kind,
              slotStart: slotStart,
              slotEnd: end,
              patient: patientSnapshot,
            ),
          ) ??
          false;

      if (!mounted) return;
      if (!ok) return;

      await apptRepo.createAppointment(
        clinicId: clinicId,
        kind: kind,
        patientId: patientId,
        serviceId: pickedService!.id,
        practitionerId: pickedPractitioner!.uid,
        start: slotStart,
        end: end,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Created $kind booking ${_fmtTime(slotStart)}–${_fmtTime(end)}'),
        ),
      );
    } on ClinicClosureConflictException {
      _showClosedSnack(message: 'Clinic closure conflict.');
      return;
    } on FirebaseFunctionsException catch (e, st) {
      debugPrint(
          '[BookingCalendar] Functions error: code=${e.code} message=${e.message} details=${e.details}\n$st');
      if (!mounted) return;
      await _showFatalDialog(
        title: 'Create appointment failed',
        message: 'Functions error\n\n'
            'code: ${e.code}\n'
            'message: ${e.message}\n'
            'details: ${e.details}\n\n'
            'Tip: check Firebase Functions logs for the exact thrown HttpsError.',
      );
    } catch (e, st) {
      debugPrint('[BookingCalendar] Booking flow error: $e\n$st');
      if (!mounted) return;
      await _showFatalDialog(
        title: 'Booking flow failed',
        message: e.toString(),
      );
    }
  }

  Future<void> _updateAppointment({
    required AppointmentsRepository apptRepo,
    required String clinicId,
    required String appointmentId,
    required DateTime start,
    required DateTime end,
    required bool allowClosedOverride,
  }) async {
    await apptRepo.updateAppointment(
      clinicId: clinicId,
      appointmentId: appointmentId,
      start: start,
      end: end,
      allowClosedOverride: allowClosedOverride,
    );
  }

  // ---------------------------------------------------------------------------
  // New patient creation (Cloud Function only)
  // ---------------------------------------------------------------------------

  Future<String> _createPatientInClinic({
    required String clinicId,
    required _PatientSnapshot patient,
  }) async {
    final dobIso =
        DateTime(patient.dob.year, patient.dob.month, patient.dob.day)
            .toIso8601String();

    final payload = <String, dynamic>{
      'clinicId': clinicId,
      'firstName': patient.firstName.trim(),
      'lastName': patient.lastName.trim(),
      'dob': dobIso,
      'dateOfBirth': dobIso,
      'phone': patient.phone.trim(),
      'email': patient.email.trim(),
      'address': (patient.address ?? '').trim(),
    };

    final result =
        await _functions.httpsCallable('createPatientFn').call(payload);

    final data = result.data;
    if (data is Map && data['patientId'] is String) {
      return data['patientId'] as String;
    }

    throw StateError('createPatientFn returned unexpected payload: $data');
  }

  static List<int> _buildLengthOptions({
    required int adminGridMinutes,
    required Set<int> include,
    required int maxMinutes,
  }) {
    final set = <int>{...include};
    set.removeWhere(
        (m) => m <= 0 || m > maxMinutes || m % adminGridMinutes != 0);

    for (int m = adminGridMinutes; m <= maxMinutes; m += adminGridMinutes) {
      if (m == adminGridMinutes ||
          m == adminGridMinutes * 2 ||
          m == adminGridMinutes * 3 ||
          m == adminGridMinutes * 4) {
        set.add(m);
      }
    }

    final list = set.toList()..sort();
    return list;
  }

  static DateTime _startOfWeek(DateTime d) {
    final date = DateTime(d.year, d.month, d.day);
    final diff = date.weekday - DateTime.monday;
    return date.subtract(Duration(days: diff));
  }

  static String _fmtShort(DateTime d) => '${d.day}/${d.month}/${d.year}';

  static String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _showFatalDialog({
    required String title,
    required String message,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }
}

/// ✅ Inline top bar that contains the practitioner dropdown (compact) next to
/// date controls (no giant row above the calendar).
class _TopBarWithPractitioner extends StatelessWidget {
  final String clinicId;
  final String rangeText;

  final String? value; // null = all
  final ValueChanged<String?> onChanged;

  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPickDate;
  final VoidCallback onCurrentWeek;
  final bool fitWeek;
  final VoidCallback onToggleFit;

  const _TopBarWithPractitioner({
    required this.clinicId,
    required this.rangeText,
    required this.value,
    required this.onChanged,
    required this.onPrev,
    required this.onNext,
    required this.onPickDate,
    required this.onCurrentWeek,
    required this.fitWeek,
    required this.onToggleFit,
  });

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 700;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
          Text(rangeText, style: theme.textTheme.titleMedium),
          IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
          const SizedBox(width: 6),
          if (isNarrow)
            IconButton(
              tooltip: 'Pick date',
              onPressed: onPickDate,
              icon: const Icon(Icons.calendar_month),
            )
          else
            OutlinedButton.icon(
              onPressed: onPickDate,
              icon: const Icon(Icons.calendar_month),
              label: const Text('Go to date'),
            ),
          if (isNarrow)
            IconButton(
              tooltip: 'Current week',
              onPressed: onCurrentWeek,
              icon: const Icon(Icons.today),
            )
          else
            OutlinedButton.icon(
              onPressed: onCurrentWeek,
              icon: const Icon(Icons.today),
              label: const Text('Current week'),
            ),
          OutlinedButton.icon(
            onPressed: onToggleFit,
            icon: Icon(fitWeek ? Icons.fullscreen_exit : Icons.fit_screen),
            label: Text(fitWeek ? 'Unfit' : 'Fit week'),
          ),
          _PractitionerInlineDropdown(
            clinicId: clinicId,
            value: value,
            onChanged: onChanged,
            compact: isNarrow,
          ),
        ],
      ),
    );
  }
}

class _PractitionerInlineDropdown extends StatelessWidget {
  final String clinicId;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool compact;

  const _PractitionerInlineDropdown({
    required this.clinicId,
    required this.value,
    required this.onChanged,
    required this.compact,
  });

  bool _isActiveLike(Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString().trim();
    if (status == 'suspended') return false;
    if (status == 'invited') return false;

    final active = data['active'];
    if (active is bool) return active;

    return true;
  }

  bool _canScheduleWrite(Map<String, dynamic> data) {
    final perms = data['permissions'];
    if (perms is Map) return perms['schedule.write'] == true;
    return false;
  }

  String _labelFor(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    final name = (data['displayName'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;

    final email =
        (data['invitedEmail'] ?? data['email'] ?? '').toString().trim();
    if (email.isNotEmpty) return email;

    return d.id.length <= 10 ? d.id : '${d.id.substring(0, 10)}…';
  }

  @override
  Widget build(BuildContext context) {
    final membersCol = FirebaseFirestore.instance
        .collection('clinics')
        .doc(clinicId)
        .collection('members');

    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: compact ? 160 : 240,
        maxWidth: compact ? 220 : 320,
      ),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: membersCol.snapshots(),
        builder: (context, snap) {
          final docs = snap.data?.docs ?? const [];

          final practitioners = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          final seen = <String>{};

          for (final d in docs) {
            if (!seen.add(d.id)) continue;
            final data = d.data();
            if (!_isActiveLike(data)) continue;
            if (!_canScheduleWrite(data)) continue;
            practitioners.add(d);
          }

          practitioners.sort((a, b) {
            final an = (a.data()['displayName'] ?? '').toString();
            final bn = (b.data()['displayName'] ?? '').toString();
            return an.compareTo(bn);
          });

          final allowedIds = practitioners.map((d) => d.id).toSet();
          final safeValue =
              (value != null && allowedIds.contains(value)) ? value : null;

          return DropdownButtonFormField<String?>(
            initialValue: safeValue,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: compact ? null : 'Clinician',
              hintText: 'All',
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All clinicians'),
              ),
              for (final d in practitioners)
                DropdownMenuItem<String?>(
                  value: d.id,
                  child: Text(_labelFor(d), overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: onChanged,
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Opening-hours helpers (weeklyHours)
// ---------------------------------------------------------------------------

class _UtcRange {
  final DateTime startUtc;
  final DateTime endUtc;
  const _UtcRange({required this.startUtc, required this.endUtc});
}

class _WeekBounds {
  final int startHour;
  final int endHour;
  const _WeekBounds({required this.startHour, required this.endHour});
}

_WeekBounds _computeGridBoundsForWeek({
  required List<DateTime> days,
  required _WeeklyHours weeklyHours,
  required int fallbackStartHour,
  required int fallbackEndHour,
}) {
  int? minStartMin;
  int? maxEndMin;

  for (final d in days) {
    final key = _WeeklyHours.dayKeyFromDate(d);
    final spec = weeklyHours.day(key);
    if (spec == null || !spec.open) continue;

    for (final it in spec.intervals) {
      minStartMin = (minStartMin == null)
          ? it.startMin
          : math.min(minStartMin, it.startMin);
      maxEndMin =
          (maxEndMin == null) ? it.endMin : math.max(maxEndMin, it.endMin);
    }
  }

  if (minStartMin == null || maxEndMin == null) {
    return _WeekBounds(startHour: fallbackStartHour, endHour: fallbackEndHour);
  }

  final startHour = (minStartMin ~/ 60).clamp(0, 23);
  final endHour = ((maxEndMin + 59) ~/ 60).clamp(1, 24);

  final safeStart = math.min(startHour, 23);
  final safeEnd = math.max(endHour, safeStart + 1);

  return _WeekBounds(
    startHour: safeStart.clamp(0, 23),
    endHour: safeEnd.clamp(1, 24),
  );
}

class _DayInterval {
  final int startMin;
  final int endMin;
  const _DayInterval({required this.startMin, required this.endMin});
}

class _DayHours {
  final List<_DayInterval> intervals;
  const _DayHours({required this.intervals});

  bool get open => intervals.isNotEmpty;
}

class _WeeklyHours {
  final Map<String, _DayHours> _byKey;

  const _WeeklyHours(this._byKey);

  static const _keys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

  _DayHours? day(String key) => _byKey[key];

  bool isOpen(String key) => _byKey[key]?.open == true;

  bool isWithinOpeningHours(DateTime tLocal) {
    final key = dayKeyFromDate(tLocal);
    final spec = _byKey[key];
    if (spec == null || !spec.open) return false;

    final mins = (tLocal.hour * 60) + tLocal.minute;

    for (final it in spec.intervals) {
      if (mins >= it.startMin && mins < it.endMin) return true;
    }
    return false;
  }

  /// Expected:
  /// { "mon":[{"start":"08:00","end":"18:00"}], ... }
  static _WeeklyHours fromServerWeeklyHours(Map<String, dynamic> raw) {
    final out = <String, _DayHours>{};

    for (final k in _keys) {
      final v = raw[k];

      if (v is! List) {
        out[k] = const _DayHours(intervals: []);
        continue;
      }

      final intervals = <_DayInterval>[];

      for (final item in v) {
        if (item is! Map) continue;
        final mm = Map<String, dynamic>.from(item);

        final startStr = (mm['start'] ?? '').toString();
        final endStr = (mm['end'] ?? '').toString();

        final startMin = _parseHHmmToMinutes(startStr);
        final endMin = _parseHHmmToMinutes(endStr);

        if (startMin == null || endMin == null) continue;
        if (endMin <= startMin) continue;

        intervals.add(_DayInterval(startMin: startMin, endMin: endMin));
      }

      intervals.sort((a, b) => a.startMin.compareTo(b.startMin));
      out[k] = _DayHours(intervals: _mergeIntervals(intervals));
    }

    return _WeeklyHours(out);
  }

  static String dayKeyFromDate(DateTime dLocal) {
    switch (dLocal.weekday) {
      case DateTime.monday:
        return 'mon';
      case DateTime.tuesday:
        return 'tue';
      case DateTime.wednesday:
        return 'wed';
      case DateTime.thursday:
        return 'thu';
      case DateTime.friday:
        return 'fri';
      case DateTime.saturday:
        return 'sat';
      case DateTime.sunday:
        return 'sun';
    }
    return 'mon';
  }

  /// Convert UTC windows into local-day minute intervals.
  static _WeeklyHours fromUtcOpenWindows(List<_UtcRange> windows) {
    final out = <String, List<_DayInterval>>{
      for (final k in _keys) k: <_DayInterval>[],
    };

    for (final w in windows) {
      final startLocal = w.startUtc.toLocal();
      final endLocal = w.endUtc.toLocal();
      if (!endLocal.isAfter(startLocal)) continue;

      var cursor = startLocal;
      while (cursor.isBefore(endLocal)) {
        final dayKey = dayKeyFromDate(cursor);
        final dayStart = DateTime(cursor.year, cursor.month, cursor.day, 0, 0);
        final nextMidnight = dayStart.add(const Duration(days: 1));
        final segEnd =
            endLocal.isBefore(nextMidnight) ? endLocal : nextMidnight;

        final startMin = cursor.difference(dayStart).inMinutes.clamp(0, 1440);
        final endMin = segEnd.difference(dayStart).inMinutes.clamp(0, 1440);

        if (endMin > startMin) {
          out[dayKey]!.add(_DayInterval(startMin: startMin, endMin: endMin));
        }

        cursor = segEnd;
      }
    }

    final byKey = <String, _DayHours>{};
    for (final k in _keys) {
      final list = out[k] ?? <_DayInterval>[];
      list.sort((a, b) => a.startMin.compareTo(b.startMin));
      byKey[k] = _DayHours(intervals: _mergeIntervals(list));
    }
    return _WeeklyHours(byKey);
  }

  static List<_DayInterval> _mergeIntervals(List<_DayInterval> intervals) {
    if (intervals.isEmpty) return const [];
    final sorted = [...intervals]
      ..sort((a, b) => a.startMin.compareTo(b.startMin));
    final merged = <_DayInterval>[];
    var cur = sorted.first;

    for (var i = 1; i < sorted.length; i++) {
      final next = sorted[i];
      if (next.startMin <= cur.endMin) {
        cur = _DayInterval(
          startMin: cur.startMin,
          endMin: math.max(cur.endMin, next.endMin),
        );
      } else {
        merged.add(cur);
        cur = next;
      }
    }
    merged.add(cur);
    return merged;
  }

  /// Legacy safety: supports older Firestore shapes OR default.
  static _WeeklyHours fromFirestore(dynamic weeklyHoursRaw) {
    if (weeklyHoursRaw is! Map) {
      return _WeeklyHours({
        'mon': const _DayHours(
            intervals: [_DayInterval(startMin: 8 * 60, endMin: 18 * 60)]),
        'tue': const _DayHours(
            intervals: [_DayInterval(startMin: 8 * 60, endMin: 18 * 60)]),
        'wed': const _DayHours(
            intervals: [_DayInterval(startMin: 8 * 60, endMin: 18 * 60)]),
        'thu': const _DayHours(
            intervals: [_DayInterval(startMin: 8 * 60, endMin: 18 * 60)]),
        'fri': const _DayHours(
            intervals: [_DayInterval(startMin: 8 * 60, endMin: 18 * 60)]),
        'sat': const _DayHours(intervals: []),
        'sun': const _DayHours(intervals: []),
      });
    }

    final m = Map<String, dynamic>.from(weeklyHoursRaw);
    final out = <String, _DayHours>{};

    for (final k in _keys) {
      final v = m[k];

      if (v is List) {
        final intervals = <_DayInterval>[];

        for (final item in v) {
          if (item is! Map) continue;
          final mm = Map<String, dynamic>.from(item);

          final startMin = _parseHHmmToMinutes((mm['start'] ?? '').toString());
          final endMin = _parseHHmmToMinutes((mm['end'] ?? '').toString());
          if (startMin == null || endMin == null) continue;
          if (endMin <= startMin) continue;

          intervals.add(_DayInterval(startMin: startMin, endMin: endMin));
        }

        intervals.sort((a, b) => a.startMin.compareTo(b.startMin));
        out[k] = _DayHours(intervals: intervals);
        continue;
      }

      if (v is Map) {
        final mm = Map<String, dynamic>.from(v);

        final open = mm['open'] == true;
        if (!open) {
          out[k] = const _DayHours(intervals: []);
          continue;
        }

        final startStr = (mm['start'] ?? '08:00').toString();
        final endStr = (mm['end'] ?? '18:00').toString();

        final startMin = _parseHHmmToMinutes(startStr) ?? (8 * 60);
        final endMin = _parseHHmmToMinutes(endStr) ?? (18 * 60);

        if (endMin <= startMin) {
          out[k] = const _DayHours(intervals: []);
        } else {
          out[k] = _DayHours(
            intervals: [_DayInterval(startMin: startMin, endMin: endMin)],
          );
        }
        continue;
      }

      out[k] = const _DayHours(intervals: []);
    }

    return _WeeklyHours(out);
  }

  static int? _parseHHmmToMinutes(String s) {
    final parts = s.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23) return null;
    if (m < 0 || m > 59) return null;
    return h * 60 + m;
  }
}

// ---------------------------------------------------------------------------
// Audit highlight overlay
// ---------------------------------------------------------------------------

class _AuditHighlightOverlay extends StatelessWidget {
  final Animation<double> pulse;
  final double dayWidth;
  final double headerHeight;
  final int startHour;
  final double pxPerMinute;

  final int dayIndex;
  final DateTime? startLocal;
  final DateTime? endLocal;

  const _AuditHighlightOverlay({
    required this.pulse,
    required this.dayWidth,
    required this.headerHeight,
    required this.startHour,
    required this.pxPerMinute,
    required this.dayIndex,
    required this.startLocal,
    required this.endLocal,
  });

  @override
  Widget build(BuildContext context) {
    if (dayIndex < 0 || startLocal == null || endLocal == null) {
      return const SizedBox.shrink();
    }

    final start = startLocal!;
    final end = endLocal!;

    final top =
        headerHeight + _minutesFromStart(start, startHour) * pxPerMinute;
    final h = (_minutesBetween(start, end).clamp(10, 12 * 60)) * pxPerMinute;

    return Positioned(
      left: dayIndex * dayWidth,
      top: top,
      width: dayWidth,
      height: h,
      child: IgnorePointer(
        ignoring: true,
        child: AnimatedBuilder(
          animation: pulse,
          builder: (context, _) {
            final t = pulse.value;
            final opacity = 0.15 + (0.25 * t);
            final borderOpacity = 0.35 + (0.45 * t);

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: opacity),
                border: Border.all(
                  width: 2,
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: borderOpacity),
                ),
              ),
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(
                    'From audit',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.85),
                        ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  static int _minutesFromStart(DateTime tLocal, int startHour) {
    final start = DateTime(tLocal.year, tLocal.month, tLocal.day, startHour, 0);
    return tLocal.difference(start).inMinutes;
  }

  static int _minutesBetween(DateTime a, DateTime b) =>
      b.difference(a).inMinutes;
}

// ---------------------------------------------------------------------------
// Closures model + overlay layer
// ---------------------------------------------------------------------------

class _ClinicClosure {
  final String id;
  final DateTime fromAtUtc;
  final DateTime toAtUtc;
  final String? reason;
  final bool active;

  const _ClinicClosure({
    required this.id,
    required this.fromAtUtc,
    required this.toAtUtc,
    required this.reason,
    required this.active,
  });

  static DateTime _parseTs(dynamic v) {
    if (v is Timestamp) return v.toDate().toUtc();
    if (v is String) {
      return (DateTime.tryParse(v) ?? DateTime.fromMillisecondsSinceEpoch(0))
          .toUtc();
    }
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v).toUtc();
    return DateTime.fromMillisecondsSinceEpoch(0).toUtc();
  }

  factory _ClinicClosure.fromFirestore(String id, Map<String, dynamic> data) {
    final r = (data['reason'] ?? '').toString().trim();
    return _ClinicClosure(
      id: id,
      fromAtUtc: _parseTs(data['fromAt']),
      toAtUtc: _parseTs(data['toAt']),
      reason: r.isEmpty ? null : r,
      active: data['active'] == true,
    );
  }
}

class _ClosureOverlayLayer extends StatelessWidget {
  final List<_ClinicClosure> closures;
  final List<DateTime> days;
  final double dayWidth;
  final double headerHeight;
  final int startHour;
  final int endHour;
  final double pxPerMinute;

  const _ClosureOverlayLayer({
    required this.closures,
    required this.days,
    required this.dayWidth,
    required this.headerHeight,
    required this.startHour,
    required this.endHour,
    required this.pxPerMinute,
  });

  @override
  Widget build(BuildContext context) {
    final totalMinutes = (endHour - startHour) * 60;

    final segments = <_ClosureSegment>[];
    for (final c in closures) {
      if (!c.active) continue;

      for (var dayIndex = 0; dayIndex < days.length; dayIndex++) {
        final dayLocal = DateTime(
          days[dayIndex].year,
          days[dayIndex].month,
          days[dayIndex].day,
        );

        final dayStartLocal =
            DateTime(dayLocal.year, dayLocal.month, dayLocal.day, startHour, 0);
        final dayEndLocal = dayStartLocal.add(Duration(minutes: totalMinutes));

        final cStartLocal = c.fromAtUtc.toLocal();
        final cEndLocal = c.toAtUtc.toLocal();

        final segStart =
            cStartLocal.isAfter(dayStartLocal) ? cStartLocal : dayStartLocal;
        final segEnd =
            cEndLocal.isBefore(dayEndLocal) ? cEndLocal : dayEndLocal;

        if (!segEnd.isAfter(segStart)) continue;

        segments.add(
          _ClosureSegment(
            dayIndex: dayIndex,
            startLocal: segStart,
            endLocal: segEnd,
            reason: c.reason,
          ),
        );
      }
    }

    if (segments.isEmpty) return const SizedBox.shrink();

    return IgnorePointer(
      ignoring: true,
      child: Stack(
        children: [
          for (final s in segments)
            Positioned(
              left: s.dayIndex * dayWidth,
              top: headerHeight +
                  _minutesFromStart(s.startLocal, startHour) * pxPerMinute,
              width: dayWidth,
              height:
                  (_minutesBetween(s.startLocal, s.endLocal).clamp(1, 1440)) *
                      pxPerMinute,
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .error
                      .withValues(alpha: 0.10),
                  border: Border(
                    left: BorderSide(
                      color: Theme.of(context)
                          .colorScheme
                          .error
                          .withValues(alpha: 0.35),
                      width: 2,
                    ),
                  ),
                ),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(
                      (s.reason == null || s.reason!.trim().isEmpty)
                          ? 'Closed'
                          : 'Closed • ${s.reason}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .error
                                .withValues(alpha: 0.85),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static int _minutesFromStart(DateTime tLocal, int startHour) {
    final start = DateTime(tLocal.year, tLocal.month, tLocal.day, startHour, 0);
    return tLocal.difference(start).inMinutes;
  }

  static int _minutesBetween(DateTime a, DateTime b) =>
      b.difference(a).inMinutes;
}

class _ClosureSegment {
  final int dayIndex;
  final DateTime startLocal;
  final DateTime endLocal;
  final String? reason;
  const _ClosureSegment({
    required this.dayIndex,
    required this.startLocal,
    required this.endLocal,
    required this.reason,
  });
}

// ---------------------------------------------------------------------------
// Edit booking dialog
// ---------------------------------------------------------------------------

class _EditBookingResult {
  final int minutes;
  final String kind; // 'new' | 'followup'
  final String? serviceId;
  const _EditBookingResult({
    required this.minutes,
    required this.kind,
    this.serviceId,
  });
}

class _EditBookingDialog extends StatefulWidget {
  final String clinicId;
  final Appointment appt;
  final ServicesRepository servicesRepo;

  const _EditBookingDialog({
    required this.clinicId,
    required this.appt,
    required this.servicesRepo,
  });

  @override
  State<_EditBookingDialog> createState() => _EditBookingDialogState();
}

class _EditBookingDialogState extends State<_EditBookingDialog> {
  late int _minutes;
  late String _kind;
  String? _serviceId;

  @override
  void initState() {
    super.initState();
    _minutes =
        widget.appt.end.difference(widget.appt.start).inMinutes.clamp(5, 480);
    _kind = (widget.appt.kind.toLowerCase() == 'new') ? 'new' : 'followup';
    _serviceId =
        widget.appt.serviceId.trim().isEmpty ? null : widget.appt.serviceId;
  }

  @override
  Widget build(BuildContext context) {
    final lengthOptions = <int>[15, 20, 30, 45, 60, 90, 120];

    return AlertDialog(
      title: const Text('Edit booking'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _kind,
              items: const [
                DropdownMenuItem(value: 'new', child: Text('New patient (NP)')),
                DropdownMenuItem(
                    value: 'followup', child: Text('Follow up (FU)')),
              ],
              onChanged: (v) => setState(() => _kind = (v ?? 'followup')),
              decoration: const InputDecoration(labelText: 'Appointment type'),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child:
                  Text('Length', style: Theme.of(context).textTheme.titleSmall),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in lengthOptions)
                  ChoiceChip(
                    label: Text('$m min'),
                    selected: _minutes == m,
                    onSelected: (_) => setState(() => _minutes = m),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.medical_services_outlined),
              title: const Text('Service'),
              subtitle: Text(_serviceId == null
                  ? 'Keep current'
                  : 'Selected: $_serviceId'),
              onTap: () async {
                final picked = await showDialog<_PickedService>(
                  context: context,
                  builder: (_) => _ServicePickerDialog(
                    clinicId: widget.clinicId,
                    servicesRepo: widget.servicesRepo,
                  ),
                );
                if (picked == null) return;
                setState(() => _serviceId = picked.id);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _EditBookingResult(
              minutes: _minutes,
              kind: _kind,
              serviceId: _serviceId,
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _DevPermissionHintBanner extends StatelessWidget {
  const _DevPermissionHintBanner();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// ---------------------------------------------------------------------------
// Left gutter time labels
// ---------------------------------------------------------------------------

class _TimeGutter extends StatelessWidget {
  final int startHour;
  final int endHour;
  final int slotMinutes;
  final double headerHeight;
  final double slotHeight;

  const _TimeGutter({
    required this.startHour,
    required this.endHour,
    required this.slotMinutes,
    required this.headerHeight,
    required this.slotHeight,
  });

  @override
  Widget build(BuildContext context) {
    final rows = ((endHour - startHour) * 60 / slotMinutes).ceil();

    return SizedBox(
      width: 64,
      child: Column(
        children: [
          SizedBox(height: headerHeight),
          for (var i = 0; i < rows; i++)
            SizedBox(
              height: slotHeight,
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    (i % (60 ~/ slotMinutes) == 0)
                        ? _fmtHourMinute(startHour * 60 + i * slotMinutes)
                        : '',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[700],
                        ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _fmtHourMinute(int mins) {
    final h = (mins ~/ 60) % 24;
    final m = mins % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------
// Week grid
// ---------------------------------------------------------------------------

class _WeekGrid extends StatelessWidget {
  final List<DateTime> days;
  final double dayWidth;
  final double headerHeight;
  final int startHour;
  final int endHour;
  final int slotMinutes;
  final double slotHeight;
  final _WeeklyHours weeklyHours;
  final void Function(DateTime slotStart) onTapSlot;

  const _WeekGrid({
    required this.days,
    required this.dayWidth,
    required this.headerHeight,
    required this.startHour,
    required this.endHour,
    required this.slotMinutes,
    required this.slotHeight,
    required this.weeklyHours,
    required this.onTapSlot,
  });

  @override
  Widget build(BuildContext context) {
    final rows = ((endHour - startHour) * 60 / slotMinutes).ceil();
    final totalHeight = headerHeight + rows * slotHeight;

    return SizedBox(
      height: totalHeight,
      child: Column(
        children: [
          Row(
            children: [
              for (final d in days)
                Container(
                  width: dayWidth,
                  height: headerHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _dayLabel(d),
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: _isToday(d)
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: _isToday(d)
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                  ),
                        ),
                      ),
                      if (!weeklyHours.isOpen(_WeeklyHours.dayKeyFromDate(d)))
                        Text(
                          'Closed',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .error
                                        .withValues(alpha: 0.8),
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
          for (var r = 0; r < rows; r++)
            SizedBox(
              height: slotHeight,
              child: Row(
                children: [
                  for (var c = 0; c < days.length; c++)
                    SizedBox(
                      width: dayWidth,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          final day = days[c];
                          final minsFromStart = r * slotMinutes;
                          final cellStartMins = startHour * 60 + minsFromStart;

                          final slotStart = DateTime(
                            day.year,
                            day.month,
                            day.day,
                            cellStartMins ~/ 60,
                            cellStartMins % 60,
                          );

                          onTapSlot(slotStart);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(color: Colors.grey.shade300),
                              bottom: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                          foregroundDecoration: _cellClosedOverlayIfNeeded(
                            context: context,
                            day: days[c],
                            cellStartMins: startHour * 60 + r * slotMinutes,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  BoxDecoration? _cellClosedOverlayIfNeeded({
    required BuildContext context,
    required DateTime day,
    required int cellStartMins,
  }) {
    final key = _WeeklyHours.dayKeyFromDate(day);
    final spec = weeklyHours.day(key);

    if (spec == null || !spec.open) {
      return BoxDecoration(
        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.06),
      );
    }

    bool isOpenAtMinute = false;
    for (final it in spec.intervals) {
      if (cellStartMins >= it.startMin && cellStartMins < it.endMin) {
        isOpenAtMinute = true;
        break;
      }
    }

    if (!isOpenAtMinute) {
      return BoxDecoration(
        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.04),
      );
    }

    return null;
  }

  bool _isToday(DateTime d) => DateUtils.isSameDay(d, DateTime.now());

  String _dayLabel(DateTime d) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final w = names[(d.weekday - 1) % 7];
    return '$w ${d.day}/${d.month}';
  }
}

// ---------------------------------------------------------------------------
// Service picker + practitioner picker
// ---------------------------------------------------------------------------

class _PickedService {
  final String id;
  final String name;
  final int defaultMinutes;
  const _PickedService({
    required this.id,
    required this.name,
    required this.defaultMinutes,
  });
}

class _ServicePickerDialog extends StatelessWidget {
  final String clinicId;
  final ServicesRepository servicesRepo;

  const _ServicePickerDialog({
    required this.clinicId,
    required this.servicesRepo,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select service'),
      content: SizedBox(
        width: 520,
        height: 360,
        child: StreamBuilder<List<Service>>(
          stream: servicesRepo.activeServices(clinicId),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(
                  child: Text('Failed to load services:\n${snap.error}'));
            }

            final list = snap.data ?? const <Service>[];
            if (list.isEmpty) {
              return const Center(child: Text('No active services found.'));
            }

            return ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final s = list[i];
                return ListTile(
                  leading: const Icon(Icons.medical_services_outlined),
                  title: Text(s.name.isEmpty ? '(Unnamed service)' : s.name),
                  subtitle: s.description.isEmpty
                      ? null
                      : Text(
                          s.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                  trailing: s.defaultMinutes > 0
                      ? Text('${s.defaultMinutes} min')
                      : null,
                  onTap: () => Navigator.pop(
                    context,
                    _PickedService(
                      id: s.id,
                      name: s.name,
                      defaultMinutes: s.defaultMinutes,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel')),
      ],
    );
  }
}

class _PickedPractitioner {
  final String uid;
  final bool canScheduleWrite;
  const _PickedPractitioner(
      {required this.uid, required this.canScheduleWrite});
}

class _PractitionerPickerDialog extends StatelessWidget {
  final String clinicId;
  const _PractitionerPickerDialog({required this.clinicId});

  @override
  Widget build(BuildContext context) {
    final membersCol = FirebaseFirestore.instance
        .collection('clinics')
        .doc(clinicId)
        .collection('members');

    return AlertDialog(
      title: const Text('Select practitioner'),
      content: SizedBox(
        width: 520,
        height: 360,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: membersCol.snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(
                  child: Text('Failed to load members:\n${snap.error}'));
            }

            final docs = snap.data?.docs ?? const [];
            final activeMembers =
                docs.where((d) => d.data()['active'] == true).toList();

            if (activeMembers.isEmpty) {
              return const Center(
                child: Text(
                  'No active clinic members found.\n\n'
                  'Create a member doc in clinics/{clinicId}/members/{uid} with active:true.',
                  textAlign: TextAlign.center,
                ),
              );
            }

            activeMembers.sort((a, b) {
              final aCan = _canScheduleWrite(a.data());
              final bCan = _canScheduleWrite(b.data());
              if (aCan != bCan) return bCan ? 1 : -1;
              return a.id.compareTo(b.id);
            });

            return ListView.separated(
              itemCount: activeMembers.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final d = activeMembers[i];
                final uid = d.id;
                final data = d.data();
                final roleId = (data['roleId'] ?? '').toString();
                final canWrite = _canScheduleWrite(data);

                return ListTile(
                  leading: CircleAvatar(
                    child:
                        Icon(canWrite ? Icons.event_available : Icons.person),
                  ),
                  title: Text(_shortUid(uid)),
                  subtitle: Text(
                    [
                      if (roleId.isNotEmpty) 'Role: $roleId',
                      canWrite
                          ? 'schedule.write ✓ (can be booked)'
                          : 'schedule.write ✕ (cannot be booked)',
                    ].join(' • '),
                  ),
                  onTap: () => Navigator.pop(
                    context,
                    _PickedPractitioner(uid: uid, canScheduleWrite: canWrite),
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel')),
      ],
    );
  }

  static bool _canScheduleWrite(Map<String, dynamic> data) {
    final permsRaw = data['permissions'];
    if (permsRaw is Map) {
      final perms = Map<String, dynamic>.from(permsRaw);
      return perms['schedule.write'] == true;
    }
    return false;
  }

  static String _shortUid(String uid) =>
      uid.length <= 10 ? uid : '${uid.substring(0, 10)}…';
}

// ---------------------------------------------------------------------------
// Booking dialogs
// ---------------------------------------------------------------------------

enum _BookingAction { newPatient, followUp, adminBlock }

enum _PatientMode { createNew, findExisting }

class _ActionDialog extends StatelessWidget {
  final DateTime slotStart;
  const _ActionDialog({required this.slotStart});

  @override
  Widget build(BuildContext context) {
    final date = '${slotStart.day}/${slotStart.month}/${slotStart.year}';
    final time =
        '${slotStart.hour.toString().padLeft(2, '0')}:${slotStart.minute.toString().padLeft(2, '0')}';

    return AlertDialog(
      title: const Text('Book this slot'),
      content: Text('$date • $time\n\nWhat type of booking is this?'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel')),
        FilledButton.tonalIcon(
          onPressed: () => Navigator.pop(context, _BookingAction.adminBlock),
          icon: const Icon(Icons.event_busy),
          label: const Text('Admin block'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _BookingAction.followUp),
          icon: const Icon(Icons.person_search),
          label: const Text('Follow up'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _BookingAction.newPatient),
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('New patient'),
        ),
      ],
    );
  }
}

class _PatientModeDialog extends StatelessWidget {
  final _BookingAction action;
  const _PatientModeDialog({required this.action});

  @override
  Widget build(BuildContext context) {
    final label = (action == _BookingAction.newPatient)
        ? 'New patient booking'
        : 'Follow up booking';

    return AlertDialog(
      title: Text(label),
      content: const Text('Choose how to select the patient.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel')),
        FilledButton.tonalIcon(
          onPressed: () => Navigator.pop(context, _PatientMode.findExisting),
          icon: const Icon(Icons.search),
          label: const Text('Patient finder'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _PatientMode.createNew),
          icon: const Icon(Icons.person_add),
          label: const Text('New patient'),
        ),
      ],
    );
  }
}

class _LengthPickerDialog extends StatefulWidget {
  final int initial;
  final List<int> options;
  const _LengthPickerDialog({required this.initial, required this.options});

  @override
  State<_LengthPickerDialog> createState() => _LengthPickerDialogState();
}

class _LengthPickerDialogState extends State<_LengthPickerDialog> {
  late int sel = widget.initial;

  @override
  void initState() {
    super.initState();
    if (!widget.options.contains(sel) && widget.options.isNotEmpty) {
      sel = widget.options.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Appointment length'),
      content: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final m in widget.options)
            ChoiceChip(
              label: Text('$m min'),
              selected: sel == m,
              onSelected: (_) => setState(() => sel = m),
            ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, sel),
            child: const Text('Continue')),
      ],
    );
  }
}

class _ConfirmAdminBlockDialog extends StatelessWidget {
  final DateTime slotStart;
  final DateTime slotEnd;

  const _ConfirmAdminBlockDialog({
    required this.slotStart,
    required this.slotEnd,
  });

  @override
  Widget build(BuildContext context) {
    final date = '${slotStart.day}/${slotStart.month}/${slotStart.year}';
    final time =
        '${slotStart.hour.toString().padLeft(2, '0')}:${slotStart.minute.toString().padLeft(2, '0')}'
        '–${slotEnd.hour.toString().padLeft(2, '0')}:${slotEnd.minute.toString().padLeft(2, '0')}';

    return AlertDialog(
      title: const Text('Confirm admin block'),
      content: Text('Create admin block?\n\n$date • $time'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Patient models + dialogs (these fix your "_PatientSnapshot isn't a type" etc)
// ---------------------------------------------------------------------------

class _PatientSnapshot {
  final String? id;
  final String firstName;
  final String lastName;
  final DateTime dob;
  final String phone;
  final String email;
  final String? address;

  const _PatientSnapshot({
    this.id,
    required this.firstName,
    required this.lastName,
    required this.dob,
    required this.phone,
    required this.email,
    this.address,
  });

  String get fullName => '${firstName.trim()} ${lastName.trim()}'.trim();

  _PatientSnapshot copyWith({String? id}) => _PatientSnapshot(
        id: id ?? this.id,
        firstName: firstName,
        lastName: lastName,
        dob: dob,
        phone: phone,
        email: email,
        address: address,
      );

  static _PatientSnapshot fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data() ?? const <String, dynamic>{};

    DateTime dob = DateTime(2000, 1, 1);
    final v = data['dob'] ?? data['dateOfBirth'];
    if (v is Timestamp) {
      dob = v.toDate();
    } else if (v is String) {
      dob = DateTime.tryParse(v) ?? dob;
    }
    dob = DateTime(dob.year, dob.month, dob.day);

    return _PatientSnapshot(
      id: d.id,
      firstName: (data['firstName'] ?? '').toString(),
      lastName: (data['lastName'] ?? '').toString(),
      dob: dob,
      phone: (data['phone'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      address: (data['address'] ?? '').toString(),
    );
  }
}

class _NewPatientDialog extends StatefulWidget {
  const _NewPatientDialog();

  @override
  State<_NewPatientDialog> createState() => _NewPatientDialogState();
}

class _NewPatientDialogState extends State<_NewPatientDialog> {
  final _formKey = GlobalKey<FormState>();

  final _first = TextEditingController();
  final _last = TextEditingController();
  DateTime? _dob;
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    super.dispose();
  }

  String? _req(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New patient details'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _first,
                decoration: const InputDecoration(labelText: 'First name *'),
                validator: _req,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _last,
                decoration: const InputDecoration(labelText: 'Last name *'),
                validator: _req,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.cake_outlined),
                      label: Text(_dob == null
                          ? 'DOB *'
                          : '${_dob!.day}/${_dob!.month}/${_dob!.year}'),
                      onPressed: () async {
                        final now = DateTime.now();
                        final init =
                            DateTime(now.year - 30, now.month, now.day);
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _dob ?? init,
                          firstDate: DateTime(1900),
                          lastDate: DateTime(now.year, now.month, now.day),
                        );
                        if (!mounted) return;
                        if (d != null) {
                          setState(
                              () => _dob = DateTime(d.year, d.month, d.day));
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Phone *'),
                validator: _req,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email *'),
                validator: _req,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _address,
                decoration:
                    const InputDecoration(labelText: 'Address (optional)'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final ok = _formKey.currentState?.validate() ?? false;
            if (!ok) return;
            if (_dob == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('DOB is required')));
              return;
            }

            Navigator.pop(
              context,
              _PatientSnapshot(
                firstName: _first.text.trim(),
                lastName: _last.text.trim(),
                dob: _dob!,
                phone: _phone.text.trim(),
                email: _email.text.trim(),
                address:
                    _address.text.trim().isEmpty ? null : _address.text.trim(),
              ),
            );
          },
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class _PatientFinderDialog extends StatefulWidget {
  final String clinicId;
  const _PatientFinderDialog({required this.clinicId});

  @override
  State<_PatientFinderDialog> createState() => _PatientFinderDialogState();
}

class _PatientFinderDialogState extends State<_PatientFinderDialog> {
  final _nameCtl = TextEditingController();
  DateTime? _dobFilter;

  CollectionReference<Map<String, dynamic>> get _patientsCol =>
      FirebaseFirestore.instance
          .collection('clinics')
          .doc(widget.clinicId)
          .collection('patients');

  @override
  void dispose() {
    _nameCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final queryText = _nameCtl.text.trim().toLowerCase();

    return AlertDialog(
      title: const Text('Find patient'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtl,
              decoration: const InputDecoration(
                labelText: 'Name (first or last)',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.cake_outlined),
                    label: Text(
                      _dobFilter == null
                          ? 'DOB (optional filter)'
                          : 'DOB: ${_dobFilter!.day}/${_dobFilter!.month}/${_dobFilter!.year}',
                    ),
                    onPressed: () async {
                      final now = DateTime.now();
                      final init = DateTime(now.year - 30, now.month, now.day);
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _dobFilter ?? init,
                        firstDate: DateTime(1900),
                        lastDate: DateTime(now.year, now.month, now.day),
                      );
                      if (!mounted) return;
                      if (d != null) {
                        setState(() =>
                            _dobFilter = DateTime(d.year, d.month, d.day));
                      }
                    },
                  ),
                ),
                if (_dobFilter != null)
                  IconButton(
                    tooltip: 'Clear DOB',
                    onPressed: () => setState(() => _dobFilter = null),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 320,
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _patientsCol.orderBy('lastName').limit(200).snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(
                        child: Text('Failed to load patients:\n${snap.error}'));
                  }

                  var list =
                      snap.data?.docs.map(_PatientSnapshot.fromDoc).toList() ??
                          <_PatientSnapshot>[];

                  if (queryText.isNotEmpty) {
                    list = list.where((p) {
                      final fn = p.firstName.toLowerCase();
                      final ln = p.lastName.toLowerCase();
                      return fn.contains(queryText) || ln.contains(queryText);
                    }).toList();
                  }

                  if (_dobFilter != null) {
                    list = list.where((p) {
                      final d = p.dob;
                      return d.year == _dobFilter!.year &&
                          d.month == _dobFilter!.month &&
                          d.day == _dobFilter!.day;
                    }).toList();
                  }

                  if (list.isEmpty) {
                    return const Center(child: Text('No matching patients'));
                  }

                  return ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final p = list[i];
                      final dob = '${p.dob.day}/${p.dob.month}/${p.dob.year}';
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(p.fullName),
                        subtitle: Text('DOB: $dob'),
                        onTap: () => Navigator.pop(context, p),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel')),
      ],
    );
  }
}

class _ConfirmBookingDialog extends StatelessWidget {
  final String kind; // 'new' | 'followup'
  final DateTime slotStart;
  final DateTime slotEnd;
  final _PatientSnapshot patient;

  const _ConfirmBookingDialog({
    required this.kind,
    required this.slotStart,
    required this.slotEnd,
    required this.patient,
  });

  @override
  Widget build(BuildContext context) {
    final typeLabel = (kind == 'new') ? 'New patient' : 'Follow up';
    final date = '${slotStart.day}/${slotStart.month}/${slotStart.year}';
    final time =
        '${slotStart.hour.toString().padLeft(2, '0')}:${slotStart.minute.toString().padLeft(2, '0')}'
        '–${slotEnd.hour.toString().padLeft(2, '0')}:${slotEnd.minute.toString().padLeft(2, '0')}';
    final dob = '${patient.dob.day}/${patient.dob.month}/${patient.dob.year}';

    return AlertDialog(
      title: const Text('Confirm booking'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(typeLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('When: $date • $time'),
          const SizedBox(height: 8),
          Text('Patient: ${patient.fullName}'),
          Text('DOB: $dob'),
          const SizedBox(height: 8),
          Text('Phone: ${patient.phone}'),
          Text('Email: ${patient.email}'),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Fatal panel
// ---------------------------------------------------------------------------

class _FatalPanel extends StatelessWidget {
  final String title;
  final String message;

  const _FatalPanel({
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: DefaultTextStyle(
              style:
                  Theme.of(context).textTheme.bodyMedium ?? const TextStyle(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Text(message),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
