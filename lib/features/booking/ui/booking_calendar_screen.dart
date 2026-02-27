// lib/features/booking/ui/booking_calendar_screen.dart
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/clinic_context.dart';
import '../../../app/clinic_session.dart';
import '../../../data/repositories/appointments_repository.dart'
    show AppointmentsRepository, ClinicClosureConflictException, PractitionerOverlapException;
import '../../../data/repositories/calendar_display_settings_repository.dart';
import '../../../data/repositories/services_repository.dart';
import '../../../data/repositories/staff_repository.dart';
import '../../../data/repositories/waitlist_repository.dart';
import '../../../models/appointment.dart';
import '../../../models/calendar_display_settings.dart';
import '../../../models/recurrence_draft.dart';
import '../../../models/service.dart';
import '../../../models/waitlist_entry.dart';
import 'draggable_appointment_block.dart';
import 'calendar_display_settings_screen.dart';
import 'booking_rail_date_navigator.dart';
import 'booking_rail_practitioners_section.dart';
import 'booking_rail_waitlist_section.dart';

import '../../../shared/ui/overlay_left_drawer.dart';
import '../../../shared/ui/sticky_tab_button.dart';
import '../../shell/shell_overlay_scope.dart';

import '../data/booking_calendar_prefs.dart'
    show loadBookingRailCollapsed, loadMiniCalendarExpanded, loadPractitionerVisibilityPrefs, PractitionerVisibilityPrefs, saveBookingRailCollapsed, saveMiniCalendarExpanded;

import '../../notes/data/notes_permissions.dart';
import '../../notes/ui/note_editor_screen.dart';
import '../../notes/ui/soap_note_edit_screen.dart';
import '../../patients/patient_details_screen.dart';

class BookingCalendarScreen extends StatefulWidget {
  /// If provided (e.g. from Audit), the calendar opens on that week/time.
  final DateTime? initialFocus;

  /// Optional: from Audit - will jump to that appointment if present in week stream.
  final String? initialAppointmentId;

  /// If you ever want to use this screen OUTSIDE the ClinicianShell,
  /// set this to true and it will render its own Scaffold/AppBar.
  final bool standaloneScaffold;

  /// When opening the calendar tools overlay, call this to close the clinic shell overlay (Option B).
  final VoidCallback? onCloseShellOverlay;

  /// Set to true to show Repeat? dialog, series badge, and scope picker when editing/dragging series.
  static const bool showRecurrenceUI = false;

  const BookingCalendarScreen({
    super.key,
    this.initialFocus,
    this.initialAppointmentId,
    this.standaloneScaffold = false,
    this.onCloseShellOverlay,
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
  late DateTime _weekStart; // first day shown
  bool _fitWeek = false;
  bool _hideCancelled = false;

  /// View mode: 1 = 1 Day, 3 = 3 Days, 5 = Work Week, 7 = 7 Days
  int _viewModeDays = 7;

  // ✅ Practitioner filter
  String? _selectedPractitionerId; // null = all

  // Cache for weekly hours future to prevent multiple calls on rebuilds
  Future<_WeeklyHours>? _cachedWeeklyHoursFuture;
  String? _cachedWeeklyHoursClinicId;
  DateTime? _cachedWeeklyHoursWeekStart;
  String? _cachedWeeklyHoursPractitionerId;

  /// Cached Firestore streams so StreamBuilder keeps the same subscription across rebuilds (avoids Firestore "Unexpected state" + LateInitializationError on web).
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _cachedClinicDocStream;
  String? _cachedClinicDocClinicId;
  Stream<List<_ClinicClosure>>? _cachedClosuresStream;
  String? _cachedClosuresClinicId;
  Stream<List<Appointment>>? _cachedAppointmentsStream;
  String? _cachedAppointmentsKey;
  Stream<CalendarDisplaySettings>? _cachedDisplaySettingsStream;
  String? _cachedDisplaySettingsClinicId;

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

  /// F2: mini date navigator section expanded (persisted). ValueNotifier so toggling doesn't rebuild the whole screen (no flash).
  late final ValueNotifier<bool> _miniCalendarExpandedNotifier;

  // Highlight (audit)
  DateTime? _highlightStart;
  DateTime? _highlightEnd;
  int _highlightDayIndex = -1;

  late final AnimationController _pulseCtrl;

  /// Calendar tools overlay open state. ValueNotifier so only the overlay rebuilds (no calendar flicker).
  late final ValueNotifier<bool> _calendarToolsOpenNotifier;

  /// Practitioner visibility/order from rail (empty visible = all visible).
  PractitionerVisibilityPrefs _practitionerPrefs =
      const PractitionerVisibilityPrefs();
  List<String> _visiblePractitionerIds = const [];
  List<String> _orderPractitionerIds = const [];

  /// F3: When user taps "Book" on a waitlist entry, we set this; next empty-slot tap can book this patient.
  WaitlistEntry? _pendingWaitlistEntry;

  // ───────────────────────────────────────────────────────────────────────────
  // ✅ Unified opening-hours source: Cloud Function listPublicSlotsFn
  // ───────────────────────────────────────────────────────────────────────────
  static const String _tz = 'Europe/Prague';

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'europe-west3');

  @override
  void initState() {
    super.initState();
    _calendarToolsOpenNotifier = ValueNotifier<bool>(false);
    _miniCalendarExpandedNotifier = ValueNotifier<bool>(true);
    _weekStart = _startOfWeek(widget.initialFocus ?? DateTime.now());

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _loadRailCollapsed();
    _loadMiniCalendarExpanded();
    _loadPractitionerPrefs();
  }

  Future<void> _loadMiniCalendarExpanded() async {
    final expanded = await loadMiniCalendarExpanded();
    if (mounted) _miniCalendarExpandedNotifier.value = expanded;
  }

  Future<void> _loadPractitionerPrefs() async {
    final prefs = await loadPractitionerVisibilityPrefs();
    if (mounted) setState(() => _practitionerPrefs = prefs);
  }

  Future<void> _loadRailCollapsed() async {
    final collapsed = await loadBookingRailCollapsed();
    if (mounted) _calendarToolsOpenNotifier.value = !collapsed;
  }

  void _setCalendarToolsOpen(bool open) {
    _calendarToolsOpenNotifier.value = open;
    saveBookingRailCollapsed(!open);
  }

  @override
  void dispose() {
    _calendarToolsOpenNotifier.dispose();
    _miniCalendarExpandedNotifier.dispose();
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

  // ───────────────────────────────────────────────────────────────────────────
  // Week / period navigation
  // ───────────────────────────────────────────────────────────────────────────

  void _prevPeriod() => setState(() {
        if (_viewModeDays == 30) {
          _weekStart = DateTime(_weekStart.year, _weekStart.month - 1, 1);
        } else {
          _weekStart = _weekStart.subtract(Duration(days: _viewModeDays));
        }
        _didInitialAutoJump = true;
      });

  void _nextPeriod() => setState(() {
        if (_viewModeDays == 30) {
          _weekStart = DateTime(_weekStart.year, _weekStart.month + 1, 1);
        } else {
          _weekStart = _weekStart.add(Duration(days: _viewModeDays));
        }
        _didInitialAutoJump = true;
      });

  void _goCurrentWeek() => setState(() {
        final now = DateTime.now();
        if (_viewModeDays == 1) {
          _weekStart = DateTime(now.year, now.month, now.day);
        } else if (_viewModeDays == 30) {
          _weekStart = DateTime(now.year, now.month, 1);
        } else {
          _weekStart = _startOfWeek(now);
        }
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
      if (_viewModeDays == 1) {
        _weekStart = DateTime(picked.year, picked.month, picked.day);
      } else if (_viewModeDays == 30) {
        _weekStart = DateTime(picked.year, picked.month, 1);
      } else {
        _weekStart = _startOfWeek(picked);
      }
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
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final visibleIds = _visiblePractitionerIds;
    final orderIds = _orderPractitionerIds;

    final bodyContent = _buildBody(
      context,
      clinicId,
      visiblePractitionerIds: visibleIds,
      orderPractitionerIds: orderIds,
    );

    if (!widget.standaloneScaffold) {
      if (isWide) {
        final screenWidth = MediaQuery.sizeOf(context).width;
        final drawerWidth = screenWidth >= 900 ? 360.0 : (screenWidth * 0.85).clamp(260.0, 360.0);
        final shellRight = ShellOverlayScope.getShellRightEdge(context);
        final viewHeight = MediaQuery.sizeOf(context).height;
        final tabGroupHeight = StickyTabButton.restingHeight * 2 + 4; // shell + gap + calendar
        final tabTopOffset = (viewHeight - tabGroupHeight) / 2 + StickyTabButton.restingHeight + 4;

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(child: RepaintBoundary(child: bodyContent)),
            ValueListenableBuilder<bool>(
              valueListenable: _calendarToolsOpenNotifier,
              builder: (context, isOpen, _) {
                final tabLeft = isOpen ? shellRight + drawerWidth : shellRight;
                return OverlayLeftDrawer(
                  isOpen: isOpen,
                  width: drawerWidth,
                  topOffset: 0,
                  drawerLeftOffset: shellRight,
                  tabTopOffset: tabTopOffset,
                  tabLeftOffset: tabLeft,
                  showScrim: true,
                  onScrimTap: () => _setCalendarToolsOpen(false),
                  tab: StickyTabButton(
                    icon: Icons.calendar_month,
                    iconSize: 20,
                    useDarkerStyle: true,
                    onTap: () {
                      _setCalendarToolsOpen(!isOpen);
                    },
                    tooltip: 'Calendar tools',
                  ),
                  child: _buildCalendarToolsPanel(context, clinicId),
                );
              },
            ),
          ],
        );
      }
      return bodyContent;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Booking calendar')),
      body: _buildBody(context, clinicId,
          visiblePractitionerIds: const [], orderPractitionerIds: const []),
    );
  }

  /// Content for the left rail: date navigator (F2) + practitioners. Scrollable so clinicians list can extend below the fold.
  Widget _buildRailContent(BuildContext context, String clinicId) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: _miniCalendarExpandedNotifier,
            builder: (context, expanded, _) => BookingRailDateNavigator(
              currentFocus: _weekStart,
              isExpanded: expanded,
              onExpandedChanged: (v) {
                _miniCalendarExpandedNotifier.value = v;
                saveMiniCalendarExpanded(v);
              },
              onDateSelected: (date) => setState(() {
                _weekStart = _startOfWeek(date);
                _viewModeDays = 7;
                _didInitialAutoJump = true;
              }),
            ),
          ),
          BookingRailPractitionersSection(
            clinicId: clinicId,
            initialPrefs: _practitionerPrefs,
            onPrefsChanged: (prefs, visibleIds, orderIds) {
              setState(() {
                _practitionerPrefs = prefs;
                _visiblePractitionerIds = visibleIds;
                _orderPractitionerIds = orderIds;
              });
            },
            shrinkWrap: true,
          ),
          BookingRailWaitlistSection(
            clinicId: clinicId,
            onBookEntry: (entry) {
              setState(() => _pendingWaitlistEntry = entry);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Click an empty slot to book ${entry.displayLabel}'),
                  duration: const Duration(seconds: 4),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Content for the calendar tools overlay drawer (mini month + practitioners + waitlist).
  /// Left padding clears the clinician shell sticky tab (hover width + gap).
  static const double _calendarToolsPanelLeftInset = 18.0;

  Widget _buildCalendarToolsPanel(BuildContext context, String clinicId) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: _calendarToolsPanelLeftInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Text(
              'Calendar tools',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          Expanded(
            child: _buildRailContent(context, clinicId),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    String clinicId, {
    List<String> visiblePractitionerIds = const [],
    List<String> orderPractitionerIds = const [],
  }) {
    final clinicCtx = context.watch<ClinicContext>();
    final session = context.watch<ClinicSession?>();
    final hasSession = clinicCtx.hasSession || session != null;

    if (!clinicCtx.hasClinic) {
      return const _FatalPanel(
        title: 'No clinic selected',
        message: 'Go back to clinic picker and select a clinic.',
      );
    }

    if (!hasSession) {
      return const Center(child: CircularProgressIndicator());
    }

    final perms = (clinicCtx.hasSession ? clinicCtx.session.permissions : session!.permissions);
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

    // Reuse same stream instance for same clinicId so StreamBuilder does not cancel/resubscribe on rebuild (avoids Firestore web SDK "Unexpected state").
    Stream<DocumentSnapshot<Map<String, dynamic>>> clinicDoc;
    if (_cachedClinicDocClinicId == clinicId && _cachedClinicDocStream != null) {
      clinicDoc = _cachedClinicDocStream!;
    } else {
      clinicDoc = FirebaseFirestore.instance
          .collection('clinics')
          .doc(clinicId)
          .snapshots();
      _cachedClinicDocStream = clinicDoc;
      _cachedClinicDocClinicId = clinicId;
    }

    Stream<List<_ClinicClosure>> closuresStream;
    if (_cachedClosuresClinicId == clinicId && _cachedClosuresStream != null) {
      closuresStream = _cachedClosuresStream!;
    } else {
      closuresStream = FirebaseFirestore.instance
          .collection('clinics')
          .doc(clinicId)
          .collection('closures')
          .where('active', isEqualTo: true)
          .orderBy('fromAt')
          .snapshots()
          .map((snap) => snap.docs
              .map((d) => _ClinicClosure.fromFirestore(d.id, d.data()))
              .toList());
      _cachedClosuresStream = closuresStream;
      _cachedClosuresClinicId = clinicId;
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: clinicDoc,
      builder: (context, clinicSnap) {
        if (clinicSnap.connectionState == ConnectionState.waiting && !clinicSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (clinicSnap.hasError) {
          final err = clinicSnap.error!;
          final isPermissionDenied = err is FirebaseException &&
              err.code == 'permission-denied';
          return _FatalPanel(
            title: 'Failed to load clinic settings',
            message: isPermissionDenied
                ? 'Missing or insufficient permissions. '
                  'If you just signed out, sign in again. '
                  'If you are a new member, ask an admin to grant you schedule.read (or settings.read) for this clinic.'
                : err.toString(),
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

        final int defaultSlotMinutes =
            (bookingStructure['defaultSlotMinutes'] as num?)?.toInt() ?? 20;

        // Cache the future to prevent multiple calls when toggling hide/show cancelled
        // Only recreate if clinicId, weekStart, or practitionerId changed
        if (_cachedWeeklyHoursFuture == null ||
            _cachedWeeklyHoursClinicId != clinicId ||
            _cachedWeeklyHoursWeekStart?.millisecondsSinceEpoch != _weekStart.millisecondsSinceEpoch ||
            _cachedWeeklyHoursPractitionerId != _selectedPractitionerId) {
          _cachedWeeklyHoursFuture = _weeklyHoursFromListPublicSlots(
            clinicId: clinicId,
            weekStartLocal: _weekStart,
            practitionerId: _selectedPractitionerId,
          );
          _cachedWeeklyHoursClinicId = clinicId;
          _cachedWeeklyHoursWeekStart = _weekStart;
          _cachedWeeklyHoursPractitionerId = _selectedPractitionerId;
        }

        return FutureBuilder<_WeeklyHours>(
          future: _cachedWeeklyHoursFuture,
          builder: (context, hoursSnap) {
            if (hoursSnap.connectionState == ConnectionState.waiting && !hoursSnap.hasData) {
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

            final int daysCount = _viewModeDays;
            final List<DateTime> days = List.generate(
              daysCount,
              (i) => _weekStart.add(Duration(days: i)),
            );

            return StreamBuilder<List<_ClinicClosure>>(
              stream: closuresStream,
              builder: (context, closureSnap) {
                if (closureSnap.connectionState == ConnectionState.waiting && !closureSnap.hasData) {
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

                // Month view: calendar grid with appointment counts per day
                if (_viewModeDays == 30) {
                  final monthStart = _weekStart;
                  final monthEnd = DateTime(_weekStart.year, _weekStart.month + 1, 1);
                  final apptKey = '$clinicId|${monthStart.millisecondsSinceEpoch}|${monthEnd.millisecondsSinceEpoch}|${_selectedPractitionerId ?? ""}';
                  Stream<List<Appointment>> apptsStream;
                  if (_cachedAppointmentsKey == apptKey && _cachedAppointmentsStream != null) {
                    apptsStream = _cachedAppointmentsStream!;
                  } else {
                    apptsStream = apptRepo.watchAppointmentsForDateRange(
                      clinicId: clinicId,
                      startLocal: monthStart,
                      endLocal: monthEnd,
                      practitionerId: _selectedPractitionerId,
                    );
                    _cachedAppointmentsStream = apptsStream;
                    _cachedAppointmentsKey = apptKey;
                  }
                  return StreamBuilder<List<Appointment>>(
                    stream: apptsStream,
                    builder: (context, apptSnap) {
                      if (apptSnap.connectionState == ConnectionState.waiting && !apptSnap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (apptSnap.hasError) {
                        return _FatalPanel(
                          title: 'Failed to load appointments',
                          message: '${apptSnap.error}',
                        );
                      }
                      final allAppts = apptSnap.data ?? const <Appointment>[];
                      var appts = _hideCancelled
                          ? allAppts.where((a) => a.status.toLowerCase() != 'cancelled').toList()
                          : allAppts;
                      if (visiblePractitionerIds.isNotEmpty) {
                        appts = appts.where((a) => visiblePractitionerIds.contains(a.practitionerId)).toList();
                      }
                      final calendarDisplayRepo = context.read<CalendarDisplaySettingsRepository>();
                      Stream<CalendarDisplaySettings> displayStream;
                      if (_cachedDisplaySettingsClinicId == clinicId && _cachedDisplaySettingsStream != null) {
                        displayStream = _cachedDisplaySettingsStream!;
                      } else {
                        displayStream = calendarDisplayRepo.streamSettings(clinicId);
                        _cachedDisplaySettingsStream = displayStream;
                        _cachedDisplaySettingsClinicId = clinicId;
                      }
                      return StreamBuilder<CalendarDisplaySettings>(
                        stream: displayStream,
                        initialData: CalendarDisplaySettings.defaults,
                        builder: (context, displaySnap) {
                          final displaySettings = displaySnap.data ?? CalendarDisplaySettings.defaults;
                          return Column(
                            children: [
                              _CalendarHeader(
                                clinicId: clinicId,
                                weekStartLabel: _fmtMonthStart(_weekStart),
                                value: _selectedPractitionerId,
                                onChanged: (v) {
                                  setState(() {
                                    _selectedPractitionerId = v;
                                    _didInitialAutoJump = true;
                                  });
                                },
                                visiblePractitionerIds: visiblePractitionerIds,
                                orderPractitionerIds: orderPractitionerIds,
                                onPrev: _prevPeriod,
                                onNext: _nextPeriod,
                                onPickDate: _pickDate,
                                onCurrentWeek: _goCurrentWeek,
                                fitWeek: _fitWeek,
                                onToggleFit: _toggleFitWeek,
                                hideCancelled: _hideCancelled,
                                onToggleHideCancelled: () => setState(() => _hideCancelled = !_hideCancelled),
                                viewModeDays: _viewModeDays,
                                onViewModeChanged: (v) => setState(() {
                                  _viewModeDays = v;
                                  if (v == 30) _weekStart = DateTime(_weekStart.year, _weekStart.month, 1);
                                }),
                                hidePatientNames: displaySettings.hidePatientNames,
                                onToggleHidePatientNames: () async {
                                  final repo = context.read<CalendarDisplaySettingsRepository>();
                                  await repo.updateSettings(clinicId, {'hidePatientNames': !displaySettings.hidePatientNames});
                                },
                                onOpenSettings: () async {
                                  final repo = context.read<CalendarDisplaySettingsRepository>();
                                  final saved = await Navigator.of(context).push<CalendarDisplaySettings>(
                                    MaterialPageRoute(
                                      builder: (_) => CalendarDisplaySettingsScreen(
                                        clinicId: clinicId,
                                        initial: displaySettings,
                                        repo: repo,
                                      ),
                                    ),
                                  );
                                  if (saved != null && mounted) setState(() {});
                                },
                              ),
                              const _DevPermissionHintBanner(),
                              Expanded(
                                child: _MonthCalendarGrid(
                                  monthStart: monthStart,
                                  appts: appts,
                                  onDaySelected: (date) => setState(() {
                                    _viewModeDays = 7;
                                    _weekStart = _startOfWeek(date);
                                  }),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                }

                final weekEnd = _weekStart.add(const Duration(days: 7));
                final weekApptKey = '$clinicId|${_weekStart.millisecondsSinceEpoch}|${weekEnd.millisecondsSinceEpoch}|${_selectedPractitionerId ?? ""}';
                Stream<List<Appointment>> weekApptsStream;
                if (_cachedAppointmentsKey == weekApptKey && _cachedAppointmentsStream != null) {
                  weekApptsStream = _cachedAppointmentsStream!;
                } else {
                  weekApptsStream = apptRepo.watchAppointmentsForWeek(
                    clinicId: clinicId,
                    weekStart: _weekStart,
                    practitionerId: _selectedPractitionerId,
                  );
                  _cachedAppointmentsStream = weekApptsStream;
                  _cachedAppointmentsKey = weekApptKey;
                }
                return StreamBuilder<List<Appointment>>(
                  stream: weekApptsStream,
                  builder: (context, apptSnap) {
                    if (apptSnap.connectionState == ConnectionState.waiting && !apptSnap.hasData) {
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

                    final allAppts = apptSnap.data ?? const <Appointment>[];
                    // Filter cancelled appointments if hide toggle is on
                    var appts = _hideCancelled
                        ? allAppts.where((a) => a.status.toLowerCase() != 'cancelled').toList()
                        : allAppts;
                    
                    // Sort so cancelled appointments render last (on top) to ensure they can receive taps
                    // when squashed side-by-side with booked appointments
                    appts = List<Appointment>.from(appts)..sort((a, b) {
                      final aCancelled = a.status.toLowerCase() == 'cancelled';
                      final bCancelled = b.status.toLowerCase() == 'cancelled';
                      // Non-cancelled first, cancelled last (so cancelled render on top)
                      if (aCancelled == bCancelled) return 0;
                      return aCancelled ? 1 : -1;
                    });
                    if (visiblePractitionerIds.isNotEmpty) {
                      appts = appts.where((a) => visiblePractitionerIds.contains(a.practitionerId)).toList();
                    }

                    final calendarDisplayRepo = context.read<CalendarDisplaySettingsRepository>();
                    Stream<CalendarDisplaySettings> weekDisplayStream;
                    if (_cachedDisplaySettingsClinicId == clinicId && _cachedDisplaySettingsStream != null) {
                      weekDisplayStream = _cachedDisplaySettingsStream!;
                    } else {
                      weekDisplayStream = calendarDisplayRepo.streamSettings(clinicId);
                      _cachedDisplaySettingsStream = weekDisplayStream;
                      _cachedDisplaySettingsClinicId = clinicId;
                    }
                    return StreamBuilder<CalendarDisplaySettings>(
                      stream: weekDisplayStream,
                      initialData: CalendarDisplaySettings.defaults,
                      builder: (context, displaySnap) {
                        final displaySettings = displaySnap.data ?? CalendarDisplaySettings.defaults;
                        final gridStartHour = displaySettings.displayStartHour;
                        final gridEndHour = displaySettings.displayEndHour;
                        final adminGridMinutes = displaySettings.minutesPerBlock;
                        final baseSlotHeight = displaySettings.slotHeightPx;

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
                                .clamp(28.0, 96.0);

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
                            // ✅ 3-zone header: Context (A) | Navigation & View (B) | Actions (C)
                            _CalendarHeader(
                              clinicId: clinicId,
                              weekStartLabel: _viewModeDays == 30 ? _fmtMonthStart(_weekStart) : _fmtWeekStart(_weekStart),
                              value: _selectedPractitionerId,
                              onChanged: (v) {
                                setState(() {
                                  _selectedPractitionerId = v;
                                  _didInitialAutoJump = true;
                                });
                              },
                              visiblePractitionerIds: visiblePractitionerIds,
                              orderPractitionerIds: orderPractitionerIds,
                              onPrev: _prevPeriod,
                              onNext: _nextPeriod,
                              onPickDate: _pickDate,
                              onCurrentWeek: _goCurrentWeek,
                              fitWeek: _fitWeek,
                              onToggleFit: _toggleFitWeek,
                              hideCancelled: _hideCancelled,
                              onToggleHideCancelled: () => setState(() => _hideCancelled = !_hideCancelled),
                              viewModeDays: _viewModeDays,
                              onViewModeChanged: (v) => setState(() {
                                    _viewModeDays = v;
                                    if (v == 30) _weekStart = DateTime(_weekStart.year, _weekStart.month, 1);
                                  }),
                              hidePatientNames: displaySettings.hidePatientNames,
                              onToggleHidePatientNames: () async {
                                final repo = context.read<CalendarDisplaySettingsRepository>();
                                await repo.updateSettings(clinicId, {'hidePatientNames': !displaySettings.hidePatientNames});
                              },
                              onOpenSettings: () async {
                                final repo = context.read<CalendarDisplaySettingsRepository>();
                                final saved = await Navigator.of(context).push<CalendarDisplaySettings>(
                                  MaterialPageRoute(
                                    builder: (_) => CalendarDisplaySettingsScreen(
                                      clinicId: clinicId,
                                      initial: displaySettings,
                                      repo: repo,
                                    ),
                                  ),
                                );
                                if (saved != null && mounted) setState(() {});
                              },
                            ),

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
                                                    waitlistEntry: _pendingWaitlistEntry,
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
                                              if (displaySettings.showCurrentTimeIndicator)
                                                _CurrentTimeIndicator(
                                                  days: days,
                                                  dayWidth: dayWidth,
                                                  headerHeight: _headerHeight,
                                                  displayStartHour: gridStartHour,
                                                  displayEndHour: gridEndHour,
                                                  pxPerMinute: pxPerMinute,
                                                ),
                                              for (final a in appts)
                                                DraggableAppointmentBlock(
                                                  key: ValueKey('appt_${a.id}'),
                                                  appointment: a,
                                                  allAppointments: allAppts,
                                                  hideCancelled: _hideCancelled,
                                                  hidePatientNames: displaySettings.hidePatientNames,
                                                  confirmAppointmentMoves: displaySettings.confirmAppointmentMoves,
                                                  weekStart: _weekStart,
                                                  daysCount: daysCount,
                                                  dayWidth: dayWidth,
                                                  headerHeight: _headerHeight,
                                                  startHour: gridStartHour,
                                                  endHour: gridEndHour,
                                                  pxPerMinute: pxPerMinute,
                                                  snapMinutes: _dragSnapMinutes,
                                                  showRecurrenceUI: BookingCalendarScreen.showRecurrenceUI,
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

                                                    String? dragScope;
                                                    if (a.isSeriesOccurrence && BookingCalendarScreen.showRecurrenceUI) {
                                                      dragScope = await showDialog<String>(
                                                        context: context,
                                                        builder: (_) => const _SeriesEditScopeDialog(),
                                                      );
                                                      if (!mounted || dragScope == null) return;
                                                    } else if (a.isSeriesOccurrence) {
                                                      dragScope = 'this_only';
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

                                                    final durationMinutes = newEnd.difference(newStart).inMinutes;
                                                    final startTimeLocal =
                                                        '${newStart.hour.toString().padLeft(2, '0')}:${newStart.minute.toString().padLeft(2, '0')}';

                                                    Future<void> performUpdate({required bool allowClosedOverride}) async {
                                                      if (!a.isSeriesOccurrence) {
                                                        await _updateAppointment(
                                                          apptRepo: apptRepo,
                                                          clinicId: clinicId,
                                                          appointmentId: appointmentId,
                                                          start: newStart,
                                                          end: newEnd,
                                                          allowClosedOverride: allowClosedOverride,
                                                        );
                                                        return;
                                                      }
                                                      switch (dragScope ?? 'this_only') {
                                                        case 'this_only':
                                                          await apptRepo.updateAppointmentOccurrence(
                                                            clinicId: clinicId,
                                                            appointmentId: appointmentId,
                                                            start: newStart,
                                                            end: newEnd,
                                                            markException: true,
                                                            allowClosedOverride: allowClosedOverride,
                                                          );
                                                          break;
                                                        case 'this_and_following':
                                                          await apptRepo.splitAppointmentSeries(
                                                            clinicId: clinicId,
                                                            seriesId: a.seriesId!,
                                                            splitFromAppointmentId: appointmentId,
                                                            newStartTimeLocal: startTimeLocal,
                                                            newDurationMinutes: durationMinutes,
                                                            conflictPolicy: 'BLOCK',
                                                          );
                                                          break;
                                                        case 'entire_series':
                                                          await apptRepo.updateAppointmentSeries(
                                                            clinicId: clinicId,
                                                            seriesId: a.seriesId!,
                                                            startTimeLocal: startTimeLocal,
                                                            durationMinutes: durationMinutes,
                                                            tz: _tz,
                                                            effectiveFromMs: a.start.toUtc().millisecondsSinceEpoch,
                                                            preserveExceptions: true,
                                                            conflictPolicy: 'BLOCK',
                                                          );
                                                          break;
                                                      }
                                                    }

                                                    if (!isOverlap) {
                                                      try {
                                                        await performUpdate(allowClosedOverride: false);
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
                                                      await performUpdate(allowClosedOverride: true);
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
                    ); // StreamBuilder<CalendarDisplaySettings>
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

    final clinicCtx = context.read<ClinicContext>();
    final canCreateNote = canEditClinicalNotes(clinicCtx.session.permissions);
    final canWriteSchedule = clinicCtx.session.permissions.has('schedule.write');
    final action = await _showBookingActions(
      appt,
      canCreateNote: canCreateNote,
      canWriteSchedule: canWriteSchedule,
    );
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

    if (action == 'create_note') {
      final pid = appt.patientId.trim();
      if (pid.isEmpty) return;

      // Mirror the patient Notes tab: let the clinician choose which note
      // type to create (Basic SOAP vs Initial Assessment).
      final choice = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('Basic SOAP note'),
                subtitle: const Text('Free-text subjective, objective, assessment, plan'),
                onTap: () => Navigator.pop(ctx, 'basicSoap'),
              ),
              ListTile(
                leading: const Icon(Icons.assignment_outlined),
                title: const Text('Initial Assessment'),
                subtitle: const Text('Structured, region-specific initial assessment'),
                onTap: () => Navigator.pop(ctx, 'initialAssessment'),
              ),
              ListTile(
                leading: const Icon(Icons.cancel),
                title: const Text('Cancel'),
                onTap: () => Navigator.pop(ctx, null),
              ),
            ],
          ),
        ),
      );

      if (choice == null) return;

      if (choice == 'basicSoap') {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => NoteEditorScreen.create(
              clinicId: clinicId,
              patientId: pid,
              appointmentId: appt.id,
            ),
          ),
        );
      } else if (choice == 'initialAssessment') {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SoapNoteEditScreen(
              clinicId: clinicId,
              patientId: pid,
              noteId: null,
            ),
          ),
        );
      }
      return;
    }

    if (action == 'edit') {
      String? editScope;
      if (appt.isSeriesOccurrence && BookingCalendarScreen.showRecurrenceUI) {
        editScope = await showDialog<String>(
          context: context,
          builder: (_) => const _SeriesEditScopeDialog(),
        );
        if (!mounted || editScope == null) return;
      } else if (appt.isSeriesOccurrence) {
        editScope = 'this_only';
      }

      final edited = await showDialog<_EditBookingResult>(
        context: context,
        builder: (_) => _EditBookingDialog(
          clinicId: clinicId,
          appt: appt,
          servicesRepo: servicesRepo,
        ),
      );

      if (!mounted || edited == null) return;

      try {
        if (!appt.isSeriesOccurrence) {
          await apptRepo.updateAppointmentDetails(
            clinicId: clinicId,
            appointmentId: appt.id,
            start: edited.start,
            end: edited.end,
            kind: edited.kind,
            serviceId: edited.serviceId,
          );
        } else {
          switch (editScope ?? 'this_only') {
            case 'this_only':
              await apptRepo.updateAppointmentOccurrence(
                clinicId: clinicId,
                appointmentId: appt.id,
                start: edited.start,
                end: edited.end,
                kind: edited.kind,
                serviceId: edited.serviceId,
                markException: true,
                allowClosedOverride: false,
              );
              break;
            case 'this_and_following':
              final minutes = edited.end.difference(edited.start).inMinutes;
              final startTimeLocal =
                  '${edited.start.hour.toString().padLeft(2, '0')}:${edited.start.minute.toString().padLeft(2, '0')}';
              await apptRepo.splitAppointmentSeries(
                clinicId: clinicId,
                seriesId: appt.seriesId!,
                splitFromAppointmentId: appt.id,
                newStartTimeLocal: startTimeLocal,
                newDurationMinutes: minutes,
                conflictPolicy: 'BLOCK',
              );
              break;
            case 'entire_series':
              final effectiveFromMs = appt.start.toUtc().millisecondsSinceEpoch;
              final startTimeLocal =
                  '${edited.start.hour.toString().padLeft(2, '0')}:${edited.start.minute.toString().padLeft(2, '0')}';
              await apptRepo.updateAppointmentSeries(
                clinicId: clinicId,
                seriesId: appt.seriesId!,
                kind: edited.kind,
                serviceId: edited.serviceId,
                startTimeLocal: startTimeLocal,
                durationMinutes: edited.end.difference(edited.start).inMinutes,
                tz: _tz,
                effectiveFromMs: effectiveFromMs,
                preserveExceptions: true,
                conflictPolicy: 'BLOCK',
              );
              break;
          }
        }
      } on ClinicClosureConflictException {
        _showClosedSnack();
        return;
      } on PractitionerOverlapException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
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
        if (status == 'cancelled') {
          await apptRepo.cancelAppointment(
            clinicId: clinicId,
            appointmentId: appt.id,
          );
          if (!mounted) return;
          // F4: Show waitlist matches when toggle is on
          final displaySettingsRepo = context.read<CalendarDisplaySettingsRepository>();
          final displaySettings = await displaySettingsRepo.getSettings(clinicId);
          if (displaySettings.showWaitlistMatchesOnCancel && mounted) {
            final waitlistRepo = context.read<WaitlistRepository>();
            final allEntries = await waitlistRepo.watchEntries(clinicId).first;
            final matches = _matchWaitlistToFreedSlot(allEntries, appt);
            if (matches.isNotEmpty && mounted) {
              final result = await showDialog<_WaitlistMatchResult>(
                context: context,
                builder: (_) => _WaitlistMatchesDialog(
                  matches: matches,
                  freedSlotStart: appt.start,
                  freedSlotEnd: appt.end,
                  onRemove: (entry) => waitlistRepo.removeEntry(clinicId, entry.id),
                ),
              );
              if (!mounted) return;
              if (result?.action == 'book' && result!.entry != null) {
                await _startBookingFlowDialog(
                  clinicId: clinicId,
                  apptRepo: apptRepo,
                  servicesRepo: servicesRepo,
                  slotStart: appt.start,
                  adminGridMinutes: 15,
                  defaultSlotMinutes: appt.end.difference(appt.start).inMinutes,
                  waitlistEntry: result.entry,
                );
                if (mounted) {
                  await context.read<WaitlistRepository>().removeEntry(clinicId, result.entry!.id);
                  setState(() => _pendingWaitlistEntry = null);
                }
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Appointment cancelled')),
                );
              }
            } else if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Appointment cancelled')),
              );
            }
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Appointment cancelled')),
            );
          }
        } else {
          final result = await _updateAppointmentStatusFn(
            clinicId: clinicId,
            appointmentId: appt.id,
            status: status,
          );
          if (!mounted) return;
          String message = 'Status updated to $status';
          final billing = result?['billing'] as Map<String, dynamic>?;
          if (billing != null && status == 'attended') {
            final created = billing['created'] as bool? ?? false;
            if (created) {
              final invNum = billing['invoiceNumber']?.toString();
              message = invNum != null && invNum.isNotEmpty
                  ? 'Status updated. Invoice $invNum created.'
                  : 'Status updated. Invoice created.';
            } else {
              final reason = billing['reason'] as String?;
              final errors = billing['validationErrors'] as List<dynamic>?;
              if (reason == 'billing_not_configured') {
                message = 'Status updated. No invoice: set up Billing in Clinic Settings first.';
              } else if (reason == 'validation' && errors != null && errors.isNotEmpty) {
                final firstErr = errors.first;
                final first = firstErr is Map ? firstErr['message']?.toString() ?? '' : '';
                message = first.isNotEmpty
                    ? 'Status updated. No invoice: $first'
                    : 'Status updated. No invoice: check service price and tax in Billing settings.';
              } else if (reason == 'already_invoiced') {
                message = 'Status updated. Invoice already existed.';
              } else if (reason == 'no_patient') {
                message = 'Status updated. No invoice: appointment has no patient.';
              } else {
                message = 'Status updated. No invoice created.';
              }
            }
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              duration: status == 'attended' ? const Duration(seconds: 4) : const Duration(seconds: 2),
            ),
          );
        }
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

  Future<String?> _showBookingActions(
    Appointment appt, {
    required bool canCreateNote,
    required bool canWriteSchedule,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (appt.isSeriesOccurrence && BookingCalendarScreen.showRecurrenceUI)
              ListTile(
                leading: const Icon(Icons.repeat),
                title: const Text('Repeating appointment'),
                subtitle: const Text('Choose scope when editing or moving'),
              ),
            if (canWriteSchedule)
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
            if (appt.patientId.trim().isNotEmpty && canCreateNote)
              ListTile(
                leading: const Icon(Icons.note_add_outlined),
                title: const Text('Create note'),
                onTap: () => Navigator.pop(context, 'create_note'),
              ),
            if (canWriteSchedule) ...[
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
          ],
        ),
      ),
    );
  }

  /// F4: Filter waitlist entries that match the freed slot (practitioner, service, date range). Sorted by priority desc, then createdAt asc.
  static List<WaitlistEntry> _matchWaitlistToFreedSlot(
    List<WaitlistEntry> entries,
    Appointment appt,
  ) {
    final slotDate = DateTime(appt.start.year, appt.start.month, appt.start.day);
    final list = entries.where((e) {
      if (e.preferredPractitionerIds.isNotEmpty &&
          !e.preferredPractitionerIds.contains(appt.practitionerId)) return false;
      if (e.preferredAppointmentTypeIds.isNotEmpty &&
          !e.preferredAppointmentTypeIds.contains(appt.serviceId)) return false;
      if (e.earliestDate != null && slotDate.isBefore(DateTime(e.earliestDate!.year, e.earliestDate!.month, e.earliestDate!.day))) return false;
      if (e.latestDate != null && slotDate.isAfter(DateTime(e.latestDate!.year, e.latestDate!.month, e.latestDate!.day))) return false;
      return true;
    }).toList();
    list.sort((a, b) {
      if (a.priority != b.priority) return b.priority.compareTo(a.priority);
      final aAt = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bAt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return aAt.compareTo(bAt);
    });
    return list;
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

  Future<Map<String, dynamic>?> _updateAppointmentStatusFn({
    required String clinicId,
    required String appointmentId,
    required String status,
  }) async {
    final res = await _functions.httpsCallable('updateAppointmentStatusFn').call({
      'clinicId': clinicId,
      'appointmentId': appointmentId,
      'status': status,
    });
    return res.data as Map<String, dynamic>?;
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
    WaitlistEntry? waitlistEntry,
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

      String patientId;
      _PatientSnapshot patientSnapshot;

      if (waitlistEntry != null) {
        patientId = waitlistEntry.patientId;
        patientSnapshot = _PatientSnapshot(
          id: patientId,
          firstName: waitlistEntry.displayLabel,
          lastName: '',
          dob: DateTime(2000, 1, 1),
          phone: '',
          email: '',
        );
      } else {
        final patientMode = await showDialog<_PatientMode>(
          context: context,
          builder: (_) => _PatientModeDialog(action: action),
        );
        if (!mounted) return;
        if (patientMode == null) return;

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

      final RecurrenceDraft? repeat = BookingCalendarScreen.showRecurrenceUI
          ? await showDialog<RecurrenceDraft?>(
              context: context,
              builder: (_) => _RecurrenceDialog(initialDay: slotStart),
            )
          : RecurrenceDraft.none;
      if (!mounted) return;
      if (repeat == null) return;

      final tz = _tz;

      if (repeat.isNone) {
        await apptRepo.createAppointment(
          clinicId: clinicId,
          kind: kind,
          patientId: patientId,
          serviceId: pickedService!.id,
          practitionerId: pickedPractitioner!.uid,
          start: slotStart,
          end: end,
        );
        if (waitlistEntry != null && mounted) {
          await context.read<WaitlistRepository>().removeEntry(clinicId, waitlistEntry.id);
          if (mounted) setState(() => _pendingWaitlistEntry = null);
        }
      } else {
        final result = await apptRepo.createAppointmentSeries(
          clinicId: clinicId,
          kind: kind,
          patientId: patientId,
          serviceId: pickedService!.id,
          practitionerId: pickedPractitioner!.uid,
          tz: tz,
          start: slotStart,
          durationMinutes: minutes,
          rule: repeat.toJson(),
          generateDaysAhead: 180,
          conflictPolicy: 'BLOCK',
        );
        final ids = result['createdAppointmentIds'] as List<dynamic>? ?? [];
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Created repeating appointments (${ids.length})'),
          ),
        );
        return;
      }

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
    } on PractitionerOverlapException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
      return;
    } on FirebaseFunctionsException catch (e, st) {
      debugPrint(
          '[BookingCalendar] Functions error: code=${e.code} message=${e.message} details=${e.details}\n$st');
      if (!mounted) return;
      final msg = (e.message != null && e.message!.trim().isNotEmpty)
          ? e.message!
          : 'Server error (${e.code}). Check Firebase Functions logs for details.';
      await _showFatalDialog(
        title: 'Create appointment failed',
        message: msg,
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

  /// Format week-start for toolbar: "Mon 23 Feb 2026"
  static String _fmtWeekStart(DateTime d) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final w = weekdays[(d.weekday - 1) % 7];
    final m = months[d.month - 1];
    return '$w ${d.day} $m ${d.year}';
  }

  /// Format for month view toolbar: "February 2026"
  static String _fmtMonthStart(DateTime d) {
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return '${months[d.month - 1]} ${d.year}';
  }

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

/// Revised calendar header: 56px, left block (title + clinician) + right cluster (date, view, actions).
/// Zone B + C form one right-anchored cluster (no floating center).
class _CalendarHeader extends StatelessWidget {
  final String clinicId;
  final String weekStartLabel;
  final String? value;
  final ValueChanged<String?> onChanged;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPickDate;
  final VoidCallback onCurrentWeek;
  final bool fitWeek;
  final VoidCallback onToggleFit;
  final bool hideCancelled;
  final VoidCallback onToggleHideCancelled;
  final int viewModeDays;
  final ValueChanged<int> onViewModeChanged;
  final bool hidePatientNames;
  final VoidCallback onToggleHidePatientNames;
  final VoidCallback onOpenSettings;
  final List<String> visiblePractitionerIds;
  final List<String> orderPractitionerIds;

  const _CalendarHeader({
    required this.clinicId,
    required this.weekStartLabel,
    required this.value,
    required this.onChanged,
    required this.onPrev,
    required this.onNext,
    required this.onPickDate,
    required this.onCurrentWeek,
    required this.fitWeek,
    required this.onToggleFit,
    required this.hideCancelled,
    required this.onToggleHideCancelled,
    required this.viewModeDays,
    required this.onViewModeChanged,
    required this.hidePatientNames,
    required this.onToggleHidePatientNames,
    required this.onOpenSettings,
    this.visiblePractitionerIds = const [],
    this.orderPractitionerIds = const [],
  });

  static const double _headerHeight = 56;
  static const double _zonePadding = 24;
  static const double _dividerOpacity = 0.25;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isNarrow = MediaQuery.sizeOf(context).width < 700;
    final isTablet = MediaQuery.sizeOf(context).width < 900;

    final dividerColor = scheme.outline.withValues(alpha: _dividerOpacity);

    return Container(
      height: _headerHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: dividerColor),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Zone A — Title + clinician (left anchored)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: _zonePadding),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _ZoneA(
                  clinicId: clinicId,
                  value: value,
                  onChanged: onChanged,
                  theme: theme,
                  compact: isNarrow,
                  visiblePractitionerIds: visiblePractitionerIds,
                  orderPractitionerIds: orderPractitionerIds,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Right cluster: date nav | view segments | actions (right anchored)
          _RightCluster(
            weekStartLabel: weekStartLabel,
            onPrev: onPrev,
            onNext: onNext,
            onPickDate: onPickDate,
            viewModeDays: viewModeDays,
            onViewModeChanged: onViewModeChanged,
            fitWeek: fitWeek,
            onToggleFit: onToggleFit,
            hideCancelled: hideCancelled,
            onToggleHideCancelled: onToggleHideCancelled,
            hidePatientNames: hidePatientNames,
            onToggleHidePatientNames: onToggleHidePatientNames,
            onOpenSettings: onOpenSettings,
            theme: theme,
            collapseToDropdown: isTablet,
            dividerColor: dividerColor,
          ),
          const SizedBox(width: _zonePadding),
        ],
      ),
    );
  }
}

/// Month view: calendar grid with day cells and booked appointment count per day.
class _MonthCalendarGrid extends StatelessWidget {
  final DateTime monthStart;
  final List<Appointment> appts;
  final ValueChanged<DateTime>? onDaySelected;

  const _MonthCalendarGrid({
    required this.monthStart,
    required this.appts,
    this.onDaySelected,
  });

  static DateTime _startOfWeek(DateTime d) {
    final date = DateTime(d.year, d.month, d.day);
    final diff = date.weekday - DateTime.monday;
    return date.subtract(Duration(days: diff));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final firstCell = _startOfWeek(monthStart);
    // 6 rows of 7 days to cover any month
    const int rows = 6;
    const int cols = 7;

    int countFor(DateTime date) {
      return appts.where((a) =>
          a.start.year == date.year &&
          a.start.month == date.month &&
          a.start.day == date.day).length;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Weekday headers
          Row(
            children: List.generate(cols, (c) => Expanded(
              child: Center(
                child: Text(
                  weekdays[c],
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )),
          ),
          const SizedBox(height: 8),
          // Grid of days
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1.1,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
              itemCount: rows * cols,
              itemBuilder: (context, index) {
                final dayOffset = index;
                final date = firstCell.add(Duration(days: dayOffset));
                final isCurrentMonth = date.month == monthStart.month && date.year == monthStart.year;
                final count = countFor(date);
                final isToday = _isToday(date);

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onDaySelected != null
                        ? () => onDaySelected!(date)
                        : null,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isCurrentMonth
                            ? (isToday ? scheme.primaryContainer.withValues(alpha: 0.5) : scheme.surfaceContainerHighest.withValues(alpha: 0.4))
                            : scheme.surface.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                        border: isToday ? Border.all(color: scheme.primary, width: 1.5) : null,
                      ),
                      padding: const EdgeInsets.all(6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${date.day}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: isCurrentMonth ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.5),
                              fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                          if (count > 0) ...[
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$count',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }
}

/// Zone A: Clinician dropdown only (title removed; nav item shows context).
class _ZoneA extends StatelessWidget {
  final String clinicId;
  final String? value;
  final ValueChanged<String?> onChanged;
  final ThemeData theme;
  final bool compact;
  final List<String> visiblePractitionerIds;
  final List<String> orderPractitionerIds;

  const _ZoneA({
    required this.clinicId,
    required this.value,
    required this.onChanged,
    required this.theme,
    required this.compact,
    this.visiblePractitionerIds = const [],
    this.orderPractitionerIds = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: compact ? 200 : 240,
        height: 32,
        child: _ClinicianDropdownCompact(
          clinicId: clinicId,
          value: value,
          onChanged: onChanged,
          theme: theme,
          visiblePractitionerIds: visiblePractitionerIds,
          orderPractitionerIds: orderPractitionerIds,
        ),
      ),
    );
  }
}

/// Right cluster: date nav | divider | view (1/3/7 days) | divider | actions.
/// Right-aligned so date/view sit next to Fit Screen.
class _RightCluster extends StatelessWidget {
  final String weekStartLabel;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPickDate;
  final int viewModeDays;
  final ValueChanged<int> onViewModeChanged;
  final bool fitWeek;
  final VoidCallback onToggleFit;
  final bool hideCancelled;
  final VoidCallback onToggleHideCancelled;
  final bool hidePatientNames;
  final VoidCallback onToggleHidePatientNames;
  final VoidCallback onOpenSettings;
  final ThemeData theme;
  final bool collapseToDropdown;
  final Color dividerColor;

  const _RightCluster({
    required this.weekStartLabel,
    required this.onPrev,
    required this.onNext,
    required this.onPickDate,
    required this.viewModeDays,
    required this.onViewModeChanged,
    required this.fitWeek,
    required this.onToggleFit,
    required this.hideCancelled,
    required this.onToggleHideCancelled,
    required this.hidePatientNames,
    required this.onToggleHidePatientNames,
    required this.onOpenSettings,
    required this.theme,
    required this.collapseToDropdown,
    required this.dividerColor,
  });

  static const double _controlHeight = 32;
  static const _segmentValues = [1, 3, 7, 30];
  static const _segmentLabels = ['1 Day', '3 Days', '7 Days', 'Month'];
  static const double _dividerHeight = 24;
  static const double _iconGap = 11;

  @override
  Widget build(BuildContext context) {
    Widget viewControl;
    if (collapseToDropdown) {
      final effective = _segmentValues.contains(viewModeDays) ? viewModeDays : 7;
      viewControl = _ViewModeDropdown(
        value: effective,
        onChanged: onViewModeChanged,
        theme: theme,
        headerSegments: true,
      );
    } else {
      viewControl = _ViewModeSegmentedControl(
        value: _segmentValues.contains(viewModeDays) ? viewModeDays : 7,
        values: _segmentValues,
        labels: _segmentLabels,
        onChanged: onViewModeChanged,
        theme: theme,
      );
    }

    return Align(
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // B1 — Date navigation (12px group padding, 10px chevron-date)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Previous period',
                  onPressed: onPrev,
                  icon: const Icon(Icons.chevron_left),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(_controlHeight, _controlHeight),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 10),
                InkWell(
                  onTap: onPickDate,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Text(
                      weekStartLabel,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  tooltip: 'Next period',
                  onPressed: onNext,
                  icon: const Icon(Icons.chevron_right),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(_controlHeight, _controlHeight),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
          _vDivider(),
          viewControl,
          _vDivider(),
          // Zone C — Actions (10–12px between icons)
          IconButton(
            tooltip: fitWeek ? 'Unfit' : 'Fit to viewport',
            onPressed: onToggleFit,
            icon: Icon(fitWeek ? Icons.fullscreen_exit : Icons.fit_screen),
            style: IconButton.styleFrom(
              minimumSize: const Size(_controlHeight, _controlHeight),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: _iconGap),
          IconButton(
            tooltip: hideCancelled ? 'Show cancelled' : 'Hide cancelled',
            onPressed: onToggleHideCancelled,
            icon: Icon(hideCancelled ? Icons.visibility_off : Icons.visibility),
            style: IconButton.styleFrom(
              minimumSize: const Size(_controlHeight, _controlHeight),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: _iconGap),
          IconButton(
            tooltip: hidePatientNames ? 'Show names' : 'Hide names',
            onPressed: onToggleHidePatientNames,
            icon: Icon(hidePatientNames ? Icons.person_off : Icons.person),
            style: IconButton.styleFrom(
              minimumSize: const Size(_controlHeight, _controlHeight),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: _iconGap),
          IconButton(
            tooltip: 'Calendar display settings',
            onPressed: onOpenSettings,
            icon: const Icon(Icons.settings),
            style: IconButton.styleFrom(
              minimumSize: const Size(_controlHeight, _controlHeight),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  Widget _vDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        width: 1,
        height: _dividerHeight,
        color: dividerColor,
      ),
    );
  }
}

/// Segmented control: 1 Day | 3 Days | 7 Days, 32px height, low-contrast bg, active filled.
class _ViewModeSegmentedControl extends StatelessWidget {
  final int value;
  final List<int> values;
  final List<String> labels;
  final ValueChanged<int> onChanged;
  final ThemeData theme;

  const _ViewModeSegmentedControl({
    required this.value,
    required this.values,
    required this.labels,
    required this.onChanged,
    required this.theme,
  });

  static const double _height = 32;

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    return Container(
      height: _height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < values.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 16,
                color: scheme.outline.withValues(alpha: 0.15),
              ),
            _Segment(
              label: labels[i],
              selected: value == values[i],
              onTap: () => onChanged(values[i]),
              theme: theme,
            ),
          ],
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;

  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    return Material(
      color: selected
          ? scheme.surface
          : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          alignment: Alignment.center,
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w500,
              color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact clinician dropdown for Zone A: 240px, 32px height, outlined.
class _ClinicianDropdownCompact extends StatelessWidget {
  final String clinicId;
  final String? value;
  final ValueChanged<String?> onChanged;
  final ThemeData theme;
  final List<String> visiblePractitionerIds;
  final List<String> orderPractitionerIds;

  const _ClinicianDropdownCompact({
    required this.clinicId,
    required this.value,
    required this.onChanged,
    required this.theme,
    this.visiblePractitionerIds = const [],
    this.orderPractitionerIds = const [],
  });

  @override
  Widget build(BuildContext context) {
    return _PractitionerInlineDropdown(
      clinicId: clinicId,
      value: value,
      onChanged: onChanged,
      compact: true,
      theme: theme,
      headerStyle: true,
      visiblePractitionerIds: visiblePractitionerIds,
      orderPractitionerIds: orderPractitionerIds,
    );
  }
}

class _ViewModeDropdown extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final ThemeData theme;
  /// When true, show 1 Day | 7 Days | Month (for header collapsed mode).
  final bool headerSegments;

  const _ViewModeDropdown({
    required this.value,
    required this.onChanged,
    required this.theme,
    this.headerSegments = false,
  });

  static const Map<int, String> _labels = {
    1: '1 Day',
    3: '3 Days',
    5: 'Work Week',
    7: '7 Days',
  };
  static const Map<int, String> _headerLabels = {
    1: '1 Day',
    3: '3 Days',
    7: '7 Days',
    30: 'Month',
  };

  @override
  Widget build(BuildContext context) {
    final labels = headerSegments ? _headerLabels : _labels;
    final safeValue = labels.containsKey(value) ? value : (headerSegments ? 7 : 7);
    return DropdownButton<int>(
      value: safeValue,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w500,
        color: theme.colorScheme.onSurface,
      ),
      items: labels.entries
          .map((e) => DropdownMenuItem(
                value: e.key,
                child: Text(
                  e.value,
                  style: theme.textTheme.bodyMedium,
                ),
              ))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _PractitionerInlineDropdown extends StatelessWidget {
  final String clinicId;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool compact;
  final ThemeData theme;
  /// When true, use 32px height and outlined style for header Zone A.
  final bool headerStyle;
  final List<String> visiblePractitionerIds;
  final List<String> orderPractitionerIds;

  const _PractitionerInlineDropdown({
    required this.clinicId,
    required this.value,
    required this.onChanged,
    required this.compact,
    required this.theme,
    this.headerStyle = false,
    this.visiblePractitionerIds = const [],
    this.orderPractitionerIds = const [],
  });

  bool _isActiveLike(Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString().trim();
    if (status == 'suspended') return false;
    if (status == 'invited') return false;

    final active = data['active'];
    if (active is bool) return active;

    return true;
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
    // ✅ Use StaffRepository with fallback to query both members and memberships collections (from Provider so stream cache is shared).
    final staffRepo = context.read<StaffRepository>();
    final membersStream = staffRepo.watchMembershipsWithFallback(clinicId);

    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: headerStyle ? 240 : (compact ? 160 : 240),
        maxWidth: headerStyle ? 240 : (compact ? 220 : 320),
        minHeight: headerStyle ? 32 : 0,
        maxHeight: headerStyle ? 32 : double.infinity,
      ),
      child: StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        stream: membersStream,
        builder: (context, snap) {
          final docs = snap.data ?? const [];

          final practitioners = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          final seen = <String>{};

          for (final d in docs) {
            if (!seen.add(d.id)) continue;
            final data = d.data();
            if (!_isActiveLike(data)) continue;
            practitioners.add(d);
          }

          if (visiblePractitionerIds.isNotEmpty) {
            final visibleSet = visiblePractitionerIds.toSet();
            practitioners.removeWhere((d) => !visibleSet.contains(d.id));
          }
          if (orderPractitionerIds.isNotEmpty) {
            final orderIndex = {for (var i = 0; i < orderPractitionerIds.length; i++) orderPractitionerIds[i]: i};
            practitioners.sort((a, b) {
              final ai = orderIndex[a.id] ?? 9999;
              final bi = orderIndex[b.id] ?? 9999;
              if (ai != bi) return ai.compareTo(bi);
              final an = (a.data()['displayName'] ?? '').toString();
              final bn = (b.data()['displayName'] ?? '').toString();
              return an.compareTo(bn);
            });
          } else {
            practitioners.sort((a, b) {
              final an = (a.data()['displayName'] ?? '').toString();
              final bn = (b.data()['displayName'] ?? '').toString();
              return an.compareTo(bn);
            });
          }

          final allowedIds = practitioners.map((d) => d.id).toSet();
          final safeValue =
              (value != null && allowedIds.contains(value)) ? value : null;

          final decoration = headerStyle
              ? InputDecoration(
                  labelText: 'Clinician',
                  hintText: 'All clinicians',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: theme.colorScheme.outline.withValues(alpha: 0.5),
                    ),
                  ),
                )
              : InputDecoration(
                  labelText: compact ? null : 'Clinician',
                  hintText: 'All',
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                );

          return DropdownButtonFormField<String?>(
            value: safeValue,
            isExpanded: true,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface,
            ),
            decoration: decoration,
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(
                  'All clinicians',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              for (final d in practitioners)
                DropdownMenuItem<String?>(
                  value: d.id,
                  child: Text(
                    _labelFor(d),
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
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
  final DateTime start;
  final DateTime end;
  final String kind; // 'new' | 'followup'
  final String? serviceId;
  const _EditBookingResult({
    required this.start,
    required this.end,
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
  late DateTime _start;
  late int _minutes;
  late String _kind;
  String? _serviceId;

  @override
  void initState() {
    super.initState();
    _start = widget.appt.start;
    _minutes =
        widget.appt.end.difference(widget.appt.start).inMinutes.clamp(5, 480);
    _kind = (widget.appt.kind.toLowerCase() == 'new') ? 'new' : 'followup';
    _serviceId =
        widget.appt.serviceId.trim().isEmpty ? null : widget.appt.serviceId;
  }

  DateTime get _end => _start.add(Duration(minutes: _minutes));

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(_start.year - 1),
      lastDate: DateTime(_start.year + 2),
    );
    if (date == null || !mounted) return;
    setState(() {
      _start = DateTime(date.year, date.month, date.day, _start.hour, _start.minute);
    });
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _start.hour, minute: _start.minute),
    );
    if (time == null || !mounted) return;
    setState(() {
      _start = DateTime(
        _start.year,
        _start.month,
        _start.day,
        time.hour,
        time.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final lengthOptions = <int>[15, 20, 30, 45, 60, 90, 120];
    final dateStr = '${_start.day}/${_start.month}/${_start.year}';
    final timeStr =
        '${_start.hour.toString().padLeft(2, '0')}:${_start.minute.toString().padLeft(2, '0')}';

    return AlertDialog(
      title: const Text('Edit booking'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              value: _kind,
              items: const [
                DropdownMenuItem(value: 'new', child: Text('New patient (NP)')),
                DropdownMenuItem(
                    value: 'followup', child: Text('Follow up (FU)')),
              ],
              onChanged: (v) => setState(() => _kind = v ?? 'followup'),
              decoration: const InputDecoration(labelText: 'Appointment type'),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Date'),
              subtitle: Text(dateStr),
              onTap: _pickDate,
            ),
            ListTile(
              leading: const Icon(Icons.access_time_outlined),
              title: const Text('Time'),
              subtitle: Text(timeStr),
              onTap: _pickTime,
            ),
            const SizedBox(height: 8),
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
              start: _start,
              end: _end,
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
// Current time indicator (today column only, updates every 60s)
// ---------------------------------------------------------------------------

class _CurrentTimeIndicator extends StatefulWidget {
  final List<DateTime> days;
  final double dayWidth;
  final double headerHeight;
  final int displayStartHour;
  final int displayEndHour;
  final double pxPerMinute;

  const _CurrentTimeIndicator({
    required this.days,
    required this.dayWidth,
    required this.headerHeight,
    required this.displayStartHour,
    required this.displayEndHour,
    required this.pxPerMinute,
  });

  @override
  State<_CurrentTimeIndicator> createState() => _CurrentTimeIndicatorState();
}

class _CurrentTimeIndicatorState extends State<_CurrentTimeIndicator> {
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _scheduleTick();
  }

  void _scheduleTick() {
    Future<void>.delayed(const Duration(seconds: 60), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _scheduleTick();
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = _now;
    final todayIndex = widget.days.indexWhere((d) => DateUtils.isSameDay(d, now));
    if (todayIndex < 0) return const SizedBox.shrink();

    final startMins = widget.displayStartHour * 60;
    final endMins = widget.displayEndHour * 60;
    final nowMins = now.hour * 60 + now.minute;
    if (nowMins < startMins || nowMins >= endMins) return const SizedBox.shrink();

    final top = widget.headerHeight + (nowMins - startMins) * widget.pxPerMinute;
    final left = todayIndex * widget.dayWidth;

    return Positioned(
      left: left,
      top: top,
      width: widget.dayWidth,
      height: 2,
      child: IgnorePointer(
        child: Container(
          color: Theme.of(context).colorScheme.error,
        ),
      ),
    );
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
            if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
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
            if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
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
                  if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
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

/// Returns 'this_only' | 'this_and_following' | 'entire_series', or null if cancelled.
class _SeriesEditScopeDialog extends StatelessWidget {
  const _SeriesEditScopeDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit repeating appointment'),
      content: const Text(
        'Apply changes to this appointment only, this and following occurrences, or the entire series?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'this_only'),
          child: const Text('This appointment only'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'this_and_following'),
          child: const Text('This and following'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, 'entire_series'),
          child: const Text('Entire series'),
        ),
      ],
    );
  }
}

class _RecurrenceDialog extends StatefulWidget {
  final DateTime initialDay;

  const _RecurrenceDialog({required this.initialDay});

  @override
  State<_RecurrenceDialog> createState() => _RecurrenceDialogState();
}

class _RecurrenceDialogState extends State<_RecurrenceDialog> {
  static const int _defaultCount = 12;
  int _step = 0; // 0: No/Yes, 1: How many?
  final _countController = TextEditingController(text: '$_defaultCount');

  @override
  void dispose() {
    _countController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_step == 0) {
      return AlertDialog(
        title: const Text('Repeat?'),
        content: const Text(
          'Is this a repeating appointment? Choose "No" for a single appointment, '
          '"Yes" to create a weekly series starting on this day.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, RecurrenceDraft.none),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => setState(() => _step = 1),
            child: const Text('Yes'),
          ),
        ],
      );
    }

    // Step 1: How many times?
    return AlertDialog(
      title: const Text('How many appointments?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Weekly on the same weekday, starting ${widget.initialDay.day}/${widget.initialDay.month}/${widget.initialDay.year}.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _countController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Number of appointments',
                hintText: 'e.g. 12',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submitCount(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitCount,
          child: const Text('Create series'),
        ),
      ],
    );
  }

  void _submitCount() {
    final s = _countController.text.trim();
    int? count = int.tryParse(s);
    if (count == null || count < 2 || count > 260) {
      count = _defaultCount;
    }
    final byWeekday = RecurrenceDraft.defaultByWeekdayFrom(widget.initialDay);
    Navigator.pop(
      context,
      RecurrenceDraft(
        freq: 'WEEKLY',
        interval: 1,
        byWeekday: byWeekday,
        count: count,
      ),
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
      content: SingleChildScrollView(
        child: Column(
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

/// F4: Result from waitlist matches modal — book this entry, or dismiss.
class _WaitlistMatchResult {
  final String action; // 'book' | 'dismiss'
  final WaitlistEntry? entry;

  _WaitlistMatchResult({required this.action, this.entry});
}

class _WaitlistMatchesDialog extends StatelessWidget {
  final List<WaitlistEntry> matches;
  final DateTime freedSlotStart;
  final DateTime freedSlotEnd;
  final Future<void> Function(WaitlistEntry) onRemove;

  const _WaitlistMatchesDialog({
    required this.matches,
    required this.freedSlotStart,
    required this.freedSlotEnd,
    required this.onRemove,
  });

  static String _timeStr(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slotStr = '${freedSlotStart.day}/${freedSlotStart.month}/${freedSlotStart.year} ${_timeStr(freedSlotStart)}–${_timeStr(freedSlotEnd)}';

    return AlertDialog(
      title: const Text('Waitlist matches'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Freed slot: $slotStr',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            ...matches.map((e) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      e.displayLabel,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (e.priority != 0 || (e.notes?.trim().isNotEmpty == true))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          [
                            if (e.priority != 0) 'Priority ${e.priority}',
                            if (e.notes?.trim().isNotEmpty == true) e.notes!.trim(),
                          ].join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () async {
                            await onRemove(e);
                            if (context.mounted) Navigator.pop(context, _WaitlistMatchResult(action: 'dismiss', entry: null));
                          },
                          child: const Text('Remove from waitlist'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, _WaitlistMatchResult(action: 'book', entry: e)),
                          child: const Text('Book into slot'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _WaitlistMatchResult(action: 'dismiss', entry: null)),
          child: const Text('Close'),
        ),
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
