// lib/features/public/ui/patient_booking_simple_screen.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_routes.dart';
import '../../booking/ui/public_booking_mirror_health_banner.dart';
import '../../../ui/design_tokens.dart';
import '../widgets/public_header.dart';
import '../widgets/public_shell.dart';
import '../widgets/public_contact_actions.dart';
import '../widgets/inline_month_calendar.dart';
import '../widgets/therapy_loading_indicator.dart';

/// Selectable slot tile — fixed height, centered label, grid-friendly.
class SlotTile extends StatefulWidget {
  static const double height = 58;

  final String label;
  final VoidCallback? onTap;
  final bool corporate;
  final bool selected;
  final bool disabled;
  /// Optional subtle badge (e.g. 'Earliest') shown below the time.
  final String? badge;

  const SlotTile({
    super.key,
    required this.label,
    this.onTap,
    this.corporate = false,
    this.selected = false,
    this.disabled = false,
    this.badge,
  });

  @override
  State<SlotTile> createState() => _SlotTileState();
}

class _SlotTileState extends State<SlotTile> {
  bool _hovered = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final isInteractive = !widget.disabled && widget.onTap != null;
    final existingColor = widget.corporate
        ? Colors.orange.withValues(alpha: 0.25)
        : (widget.selected ? primary.withValues(alpha: 0.5) : Colors.black12);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        elevation: _hovered ? 1 : 0,
        borderRadius: BorderRadius.circular(AppRadius.element),
        color: widget.selected
            ? primary.withValues(alpha: 0.08)
            : Colors.transparent,
        child: Focus(
          focusNode: _focusNode,
          child: Builder(
            builder: (context) {
              final isFocused = _focusNode.hasFocus;
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.element),
                  border: isFocused
                      ? Border.all(
                          color: theme.colorScheme.primary,
                          width: 2,
                        )
                      : null,
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.element),
                  onTap: isInteractive ? widget.onTap! : null,
                  child: Container(
                    height: SlotTile.height,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.element),
                      border: Border.all(
                        color: _hovered
                            ? primary.withValues(alpha: 0.4)
                            : existingColor,
                        width: widget.selected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.label,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: widget.selected ? FontWeight.w600 : null,
                            color: widget.disabled
                                ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
                                : (widget.selected ? theme.colorScheme.primary : null),
                          ),
                        ),
                        if (widget.badge != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.badge!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
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
      ),
    );
  }
}

class PatientBookingSimpleScreen extends StatefulWidget {
  static const String routeName = AppRoutes.patientBookSimple;

  /// Width breakpoint for two-column layout. Card max width is 720 so use 600 to get two columns on desktop.
  static const double twoColBreakpoint = 600;
  /// Fixed width of the left column (month calendar) on desktop.
  static const double calendarColWidth = 320;
  /// Desktop: width of the right column (slots); narrow so only 2 columns of times, giving calendar more space.
  static const double slotsColMaxWidth = 200;

  final String clinicId;

  /// Legacy name kept for routing compatibility, but this is actually a
  /// practitioner/clinician identifier used for public booking.
  final String? clinicianId;

  /// Optional: allow deep-linking a corporate code via URL routing layer.
  final String? initialCorporateCodeFromUrl;

  const PatientBookingSimpleScreen({
    super.key,
    required this.clinicId,
    this.clinicianId,
    this.initialCorporateCodeFromUrl,
  });

  @override
  State<PatientBookingSimpleScreen> createState() =>
      _PatientBookingSimpleScreenState();
}

class _PatientBookingSimpleScreenState
    extends State<PatientBookingSimpleScreen> {
  // --- Date state ---
  DateTime _selectedDay = _dateOnly(DateTime.now());
  late DateTime _visibleMonth;
  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  // --- Month availability (drives calendar dots and bold available dates) ---
  Map<String, DayAvailability> _monthAvail = {};
  bool _loadingMonthAvail = false;
  String? _monthAvailError;

  /// Request token to ignore stale async results and prevent race-condition flicker.
  int _requestToken = 0;

  /// Cache for month availability keyed by 'YYYY-MM' (silent prefetch).
  final Map<String, Map<String, DayAvailability>> _monthAvailCache = {};

  /// Slot cache keyed by 'practitionerId|yyyy-mm-dd'. Prefetch only; no UI update unless that day is selected.
  final Map<String, List<_PublicSlot>> _slotsCache = {};
  bool _slotsPrefetchBusy = false;

  // --- Scroll / nudge (premium flow) ---
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _clinicianKey = GlobalKey();
  final GlobalKey _calendarKey = GlobalKey();
  final GlobalKey _slotsKey = GlobalKey();

  // --- UX timings ---
  static const Duration _confirmTimeout = Duration(seconds: 25);

  // Preassessment routing fade behaviour
  static const Duration _fadeDuration = Duration(milliseconds: 500);
  static const Duration _fadePause = Duration(milliseconds: 500);

  // --- Slot rules ---
  static const Duration _minLeadTime = Duration(hours: 1);

  // --- Auth ---
  bool _authReady = false;
  String? _authError;

  // --- Slots ---
  bool _loadingSlots = false;
  String? _slotsError;
  List<_PublicSlot> _slots = [];
  _PublicSlot? _selectedSlot;

  // --- Practitioners (public booking must run listPublicSlotsFn against a practitionerId) ---
  bool _loadingPractitioners = false;
  String? _practitionersError;

  List<_PractitionerOption> _practitioners = const [];
  String? _selectedPractitionerId; // null = not yet chosen/resolved

  CollectionReference<Map<String, dynamic>> get _bookingRequestsCol =>
      FirebaseFirestore.instance
          .collection('clinics')
          .doc(widget.clinicId)
          .collection('bookingRequests');

  bool get _ready => _authReady && _authError == null;

  @override
  void initState() {
    super.initState();
    _visibleMonth = DateTime(_selectedDay.year, _selectedDay.month, 1);

    // If deep-linked clinicianId exists, set initial selection immediately.
    final deepLinked = (widget.clinicianId ?? '').trim();
    if (deepLinked.isNotEmpty) {
      _selectedPractitionerId = deepLinked;
    }

    _initAndLoad();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _initAndLoad() async {
    setState(() {
      _authReady = false;
      _authError = null;
      _slotsError = null;
      _practitionersError = null;
    });

    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }

      if (!mounted) return;
      setState(() => _authReady = true);

      await _refreshAll();
      if (mounted) _loadMonthAvailability();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _authError = 'Anonymous sign-in failed: $e';
        _authReady = false;
      });
    }
  }

  Future<void> _refreshAll() async {
    await _loadPractitionersIfNeeded();
    await _loadSlots();
  }

  DocumentReference<Map<String, dynamic>> get _publicBookingDoc =>
      FirebaseFirestore.instance
          .collection('clinics')
          .doc(widget.clinicId.trim())
          .collection('public')
          .doc('config')
          .collection('publicBooking')
          .doc('publicBooking');

  CollectionReference<Map<String, dynamic>> get _publicDirectoryPractitioners =>
      FirebaseFirestore.instance
          .collection('clinics')
          .doc(widget.clinicId.trim())
          .collection('public')
          .doc('directory')
          .collection('practitioners');

  /// Loads practitioners for dropdown.
  ///
  /// Supported sources (in order):
  /// 1) clinics/{clinicId}/public/config/publicBooking/publicBooking.practitioners
  ///    - supports both top-level `practitioners` and nested `publicBooking.practitioners`
  ///    - supports each item as Map {id, displayName} or String (id)
  /// 2) fallback: clinics/{clinicId}/public/directory/practitioners (active == true)
  ///
  /// Selection rules:
  /// - If deep-linked clinicianId exists, keep it selected (even if missing; a placeholder option will be added).
  /// - Else select first practitioner found.
  Future<void> _loadPractitionersIfNeeded({bool force = false}) async {
    if (!force &&
        _practitioners.isNotEmpty &&
        (_selectedPractitionerId ?? '').trim().isNotEmpty) {
      return;
    }

    setState(() {
      _loadingPractitioners = true;
      _practitionersError = null;
    });

    try {
      final cid = widget.clinicId.trim();
      if (cid.isEmpty) throw StateError('Missing clinicId');

      final deepLinked = (widget.clinicianId ?? '').trim();

      // 1) Try config doc first
      final doc = await _publicBookingDoc.get();
      final data = doc.data() ?? <String, dynamic>{};

      dynamic rawList = data['practitioners'];
      if (rawList == null && data['publicBooking'] is Map) {
        final pb = Map<String, dynamic>.from(data['publicBooking'] as Map);
        rawList = pb['practitioners'];
      }

      final options = <_PractitionerOption>[];

      if (rawList is List) {
        for (final item in rawList) {
          if (item is Map) {
            final m = Map<String, dynamic>.from(item);
            final id = (m['id'] ?? '').toString().trim();
            final name = (m['displayName'] ?? '').toString().trim();
            if (id.isNotEmpty) {
              options.add(
                _PractitionerOption(
                  id: id,
                  displayName: name.isNotEmpty ? name : _shortId(id),
                ),
              );
            }
            continue;
          }

          if (item is String) {
            final s = item.trim();
            if (s.isEmpty) continue;

            // Try extract: id: "XXXXX"
            final match = RegExp(r'id:\s*"([^"]+)"').firstMatch(s);
            if (match != null) {
              final id = (match.group(1) ?? '').trim();
              if (id.isNotEmpty) {
                options.add(
                  _PractitionerOption(
                    id: id,
                    displayName: _shortId(id),
                  ),
                );
              }
              continue;
            }

            // Or if string is just an id
            if (!s.contains(' ') && s.length > 10) {
              options.add(
                _PractitionerOption(id: s, displayName: _shortId(s)),
              );
            }
          }
        }
      }

      // 2) Fallback: public directory if config empty
      if (options.isEmpty) {
        final q = await _publicDirectoryPractitioners
            .where('active', isEqualTo: true)
            .get();

        for (final d in q.docs) {
          final m = d.data();
          final pid = (m['practitionerId'] ?? '').toString().trim();
          final id = pid.isNotEmpty ? pid : d.id;
          if (id.isEmpty) continue;

          final name = (m['displayName'] ?? m['name'] ?? '').toString().trim();
          options.add(
            _PractitionerOption(
              id: id,
              displayName: name.isNotEmpty ? name : _shortId(id),
            ),
          );
        }
      }

      // De-dupe by id
      final seen = <String>{};
      final deduped = <_PractitionerOption>[];
      for (final o in options) {
        if (seen.add(o.id)) deduped.add(o);
      }

      // Ensure deep-linked appears even if not in list
      final selected = (deepLinked.isNotEmpty)
          ? deepLinked
          : (_selectedPractitionerId ?? '').trim();

      var finalList = deduped;

      if (selected.isNotEmpty && !finalList.any((p) => p.id == selected)) {
        finalList = [
          _PractitionerOption(
            id: selected,
            displayName: 'Selected clinician',
          ),
          ...finalList,
        ];
      }

      // Choose selection
      String? nextSelected = _selectedPractitionerId?.trim();

      // Deep-link always wins if present
      if (deepLinked.isNotEmpty) {
        nextSelected = deepLinked;
      } else {
        if ((nextSelected ?? '').isEmpty) {
          nextSelected = finalList.isNotEmpty ? finalList.first.id : null;
        } else {
          // keep existing selection if still valid; else pick first
          if (finalList.isNotEmpty &&
              !finalList.any((p) => p.id == nextSelected)) {
            nextSelected = finalList.first.id;
          }
        }
      }

      if (finalList.isEmpty || (nextSelected ?? '').isEmpty) {
        throw StateError(
          'No practitioners found. Configure practitioners in public booking config '
          'or add an active practitioner under /public/directory/practitioners.',
        );
      }

      if (!mounted) return;
      setState(() {
        _practitioners = finalList;
        _selectedPractitionerId = nextSelected;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _practitionersError = 'Could not load practitioners: $e';
        // keep existing values if any
      });
    } finally {
      if (mounted) setState(() => _loadingPractitioners = false);
    }
  }

  static String _shortId(String id) {
    if (id.length <= 8) return id;
    return '${id.substring(0, 4)}…${id.substring(id.length - 4)}';
  }

  Future<void> _onPractitionerChanged(String? id) async {
    final next = (id ?? '').trim();
    if (next.isEmpty) return;
    if (next == (_selectedPractitionerId ?? '').trim()) return;

    setState(() {
      _selectedPractitionerId = next;
    });

    await _refreshAll();
    if (mounted) _loadMonthAvailability();

    if (mounted && _slots.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToSlots();
      });
    }
  }

  static String _slotsCacheKey(String practitionerId, DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return '$practitionerId|${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  List<_PublicSlot> _applySlotFilters(List<_PublicSlot> input, [DateTime? forDay]) {
    final now = DateTime.now();
    final cutoff = now.add(_minLeadTime);

    bool isHourlyStart(DateTime d) =>
        d.minute == 0 &&
        d.second == 0 &&
        d.millisecond == 0 &&
        d.microsecond == 0;

    final selectedDate = _dateOnly(forDay ?? _selectedDay);
    final today = _dateOnly(now);

    return input.where((s) {
      final start = s.startLocal;

      if (!isHourlyStart(start)) return false;
      if (start.isBefore(now)) return false;
      if (start.isBefore(cutoff)) return false;
      if (selectedDate.isBefore(today)) return false;

      return true;
    }).toList()
      ..sort((a, b) => a.startLocal.compareTo(b.startLocal));
  }

  Future<void> _loadSlots() async {
    final token = ++_requestToken;

    await _loadPractitionersIfNeeded();
    if (token != _requestToken) return;

    final practitionerId = (_selectedPractitionerId ?? '').trim();
    if (practitionerId.isEmpty) {
      setState(() {
        _loadingSlots = false;
        _slotsError = null;
        _slots = [];
      });
      return;
    }

    final startLocal = _selectedDay;
    final cacheKey = _slotsCacheKey(practitionerId, startLocal);
    final cached = _slotsCache[cacheKey];
    if (cached != null && mounted && token == _requestToken) {
      setState(() {
        _slots = cached;
        _loadingSlots = false;
        _slotsError = null;
      });
      _refreshSlotsInBackground(practitionerId, startLocal, token);
      return;
    }

    setState(() {
      _loadingSlots = true;
      _slotsError = null;
      _slots = [];
    });

    final startUtc =
        DateTime.utc(startLocal.year, startLocal.month, startLocal.day, 0, 0);
    final endUtc = startUtc.add(const Duration(days: 1));

    try {
      final functions = FirebaseFunctions.instanceFor(region: 'europe-west3');
      final fn = functions.httpsCallable('listPublicSlotsFn');

      final payload = <String, dynamic>{
        'clinicId': widget.clinicId.trim(),
        'serviceId': 'default',
        'practitionerId': practitionerId,
        'rangeStartMs': startUtc.millisecondsSinceEpoch,
        'rangeEndMs': endUtc.millisecondsSinceEpoch,
        'tz': 'Europe/Prague',
      };

      final res = await fn.call(payload).timeout(_confirmTimeout);
      if (token != _requestToken) return;

      final rawData = res.data;
      if (rawData is! Map) {
        throw StateError('Unexpected response payload: $rawData');
      }

      final data = Map<String, dynamic>.from(rawData);

      final rawSlots = (data['slots'] as List?) ?? const [];
      final slots = rawSlots
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .map(_PublicSlot.fromMap)
          .toList();

      final filtered = _applySlotFilters(slots);
      _slotsCache[cacheKey] = filtered;

      if (!mounted) return;
      if (token != _requestToken) return;
      setState(() => _slots = filtered);
    } catch (e) {
      if (!mounted) return;
      if (token != _requestToken) return;
      setState(() => _slotsError = 'Failed to load availability: $e');
    } finally {
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  /// Background refresh for current day only; updates cache and state only if still the selected day and token matches.
  Future<void> _refreshSlotsInBackground(String practitionerId, DateTime forDay, int token) async {
    final startUtc = DateTime.utc(forDay.year, forDay.month, forDay.day, 0, 0);
    final endUtc = startUtc.add(const Duration(days: 1));
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'europe-west3').httpsCallable('listPublicSlotsFn');
      final res = await fn.call(<String, dynamic>{
        'clinicId': widget.clinicId.trim(),
        'serviceId': 'default',
        'practitionerId': practitionerId,
        'rangeStartMs': startUtc.millisecondsSinceEpoch,
        'rangeEndMs': endUtc.millisecondsSinceEpoch,
        'tz': 'Europe/Prague',
      }).timeout(_confirmTimeout);
      final rawData = res.data;
      if (rawData is! Map || token != _requestToken) return;
      final data = Map<String, dynamic>.from(rawData);
      final rawSlots = (data['slots'] as List?) ?? const [];
      final slots = rawSlots
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .map(_PublicSlot.fromMap)
          .toList();
      final filtered = _applySlotFilters(slots, forDay);
      final key = _slotsCacheKey(practitionerId, forDay);
      _slotsCache[key] = filtered;
      if (mounted && token == _requestToken && _dateOnly(_selectedDay) == _dateOnly(forDay)) {
        setState(() => _slots = filtered);
      }
    } catch (_) {
      // ignore background refresh errors
    }
  }

  /// Prefetch slots for a single day into cache only. One at a time; no UI update.
  Future<void> _prefetchSlotsForDay(DateTime day) async {
    if (_slotsPrefetchBusy) return;
    final practitionerId = (_selectedPractitionerId ?? '').trim();
    if (practitionerId.isEmpty) return;

    _slotsPrefetchBusy = true;
    try {
      final startUtc = DateTime.utc(day.year, day.month, day.day, 0, 0);
      final endUtc = startUtc.add(const Duration(days: 1));
      final fn = FirebaseFunctions.instanceFor(region: 'europe-west3').httpsCallable('listPublicSlotsFn');
      final res = await fn.call(<String, dynamic>{
        'clinicId': widget.clinicId.trim(),
        'serviceId': 'default',
        'practitionerId': practitionerId,
        'rangeStartMs': startUtc.millisecondsSinceEpoch,
        'rangeEndMs': endUtc.millisecondsSinceEpoch,
        'tz': 'Europe/Prague',
      }).timeout(const Duration(seconds: 15));
      final rawData = res.data;
      if (rawData is! Map) return;
      final data = Map<String, dynamic>.from(rawData);
      final rawSlots = (data['slots'] as List?) ?? const [];
      final slots = rawSlots
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .map(_PublicSlot.fromMap)
          .toList();
      final filtered = _applySlotFilters(slots, day);
      _slotsCache[_slotsCacheKey(practitionerId, day)] = filtered;
    } catch (_) {
      // ignore prefetch errors
    } finally {
      _slotsPrefetchBusy = false;
    }
  }

  Future<void> _setSelectedDay(DateTime day) async {
    final hasClinician = (_selectedPractitionerId ?? '').trim().isNotEmpty;

    setState(() {
      _selectedDay = _dateOnly(day);
      _visibleMonth = DateTime(_selectedDay.year, _selectedDay.month, 1);
      _selectedSlot = null;
      // Keep calendar expanded so it stays visible (no collapse on date select)
    });

    if (!hasClinician) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToKey(_clinicianKey);
      });
    }

    await _refreshAll();

    // Auto-scroll to slots after date selection (calendar has collapsed)
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _slotsKey.currentContext;
        if (ctx != null && mounted) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            alignment: 0.1,
          );
        }
      });
    }
  }

  static const int _nextAvailableMaxDays = 90;

  /// Finds the first day with availability from [selectedDay] + 1 using month availability cache (no slot fetch). Max horizon 90 days.
  Future<DateTime?> _findNextAvailableDate() async {
    final practitionerId = (_selectedPractitionerId ?? '').trim();
    if (practitionerId.isEmpty) return null;
    DateTime cursor = _dateOnly(_selectedDay.add(const Duration(days: 1)));
    final end = _dateOnly(DateTime.now().add(const Duration(days: _nextAvailableMaxDays)));
    while (!cursor.isAfter(end)) {
      final monthKey = '${cursor.year}-${cursor.month.toString().padLeft(2, '0')}';
      Map<String, DayAvailability>? monthData = _monthAvailCache[monthKey];
      if (monthData == null) {
        await _loadMonthAvailability(forMonth: DateTime(cursor.year, cursor.month, 1), silent: true);
        if (!mounted) return null;
        monthData = _monthAvailCache[monthKey];
        if (monthData == null) {
          cursor = _dateOnly(DateTime(cursor.year, cursor.month + 1, 1));
          continue;
        }
      }
      final ymd = '${cursor.year.toString().padLeft(4, '0')}-${cursor.month.toString().padLeft(2, '0')}-${cursor.day.toString().padLeft(2, '0')}';
      final a = monthData[ymd];
      if (a != null && a.hasAvailability) return cursor;
      cursor = _dateOnly(cursor.add(const Duration(days: 1)));
    }
    return null;
  }

  /// Next available: use month availability to find next day with slots, then set day and load slots.
  Future<void> _jumpToNextAvailable() async {
    if ((_selectedPractitionerId ?? '').trim().isEmpty) return;
    if (mounted) {
      setState(() {
        _loadingSlots = true;
        _slotsError = null;
        _slots = [];
      });
    }
    final next = await _findNextAvailableDate();
    if (!mounted) return;
    if (next == null) {
      setState(() {
        _loadingSlots = false;
        _slotsError = 'No appointments found in the next $_nextAvailableMaxDays days.';
      });
      return;
    }
    setState(() {
      _selectedDay = next;
      _visibleMonth = DateTime(next.year, next.month, 1);
      _selectedSlot = null;
      _loadingSlots = true;
      _slotsError = null;
      _slots = [];
    });
    await _loadSlots();
    if (!mounted) return;
    _loadMonthAvailability();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Next available: ${_prettyLongDate(next)}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _setVisibleMonth(DateTime month) {
    setState(() {
      _visibleMonth = DateTime(month.year, month.month, 1);
    });
    _loadMonthAvailability();
  }

  Future<void> _scrollToKey(GlobalKey key) async {
    final ctx = key.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      alignment: 0.05,
    );
  }

  void _scrollToSlots() {
    final ctx = _slotsKey.currentContext;
    if (ctx != null && mounted) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        alignment: 0.1,
      );
    }
  }

  Future<void> _loadMonthAvailability({DateTime? forMonth, bool silent = false}) async {
    final practitionerId = (_selectedPractitionerId ?? '').trim();
    if (practitionerId.isEmpty) {
      if (!silent && mounted) setState(() => _monthAvail = {});
      return;
    }

    final month = forMonth ?? _visibleMonth;
    final monthKey = '${month.year}-${month.month.toString().padLeft(2, '0')}';

    final token = ++_requestToken;

    if (!silent) {
      setState(() {
        _loadingMonthAvail = true;
        _monthAvailError = null;
      });
    }

    try {
      final startUtc = DateTime.utc(month.year, month.month, 1);
      final endUtc = month.month == 12
          ? DateTime.utc(month.year + 1, 1, 1)
          : DateTime.utc(month.year, month.month + 1, 1);

      final functions = FirebaseFunctions.instanceFor(region: 'europe-west3');
      final fn = functions.httpsCallable('getPublicMonthAvailabilityFn');

      final res = await fn.call(<String, dynamic>{
        'clinicId': widget.clinicId.trim(),
        'serviceId': 'default',
        'practitionerId': practitionerId,
        'monthStartMs': startUtc.millisecondsSinceEpoch,
        'monthEndMs': endUtc.millisecondsSinceEpoch,
        'tz': 'Europe/Prague',
      }).timeout(const Duration(seconds: 15));

      if (token != _requestToken) return;

      final data = res.data;
      if (data is! Map) {
        if (!silent && mounted) setState(() => _monthAvail = {});
        return;
      }

      final days = data['days'];
      final out = <String, DayAvailability>{};
      if (days is Map) {
        for (final e in days.entries) {
          final k = e.key as String?;
          final v = e.value;
          if (k == null || v is! Map) continue;
          final count = (v['count'] is num) ? (v['count'] as num).toInt() : 0;
          final corporateOnly = v['corporateOnly'] == true;
          out[k] = DayAvailability(count: count, corporateOnly: corporateOnly);
        }
      }

      _monthAvailCache[monthKey] = out;

      if (!silent && mounted && token == _requestToken) {
        setState(() => _monthAvail = out);
        _prefetchNextMonthAvailability();
        _prefetchSlotsForFirstAvailableDay();
      }
    } on FirebaseFunctionsException catch (_) {
      if (!silent && mounted && token == _requestToken) {
        setState(() {
          _monthAvail = {};
          _monthAvailError = 'Availability preview unavailable';
        });
      }
    } catch (_) {
      if (!silent && mounted && token == _requestToken) {
        setState(() {
          _monthAvail = {};
          _monthAvailError = 'Availability preview unavailable';
        });
      }
    } finally {
      if (!silent && mounted) setState(() => _loadingMonthAvail = false);
    }
  }

  void _prefetchNextMonthAvailability() {
    final nextMonth = _visibleMonth.month == 12
        ? DateTime(_visibleMonth.year + 1, 1, 1)
        : DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1);
    _loadMonthAvailability(forMonth: nextMonth, silent: true);
  }

  /// First available day in visible month (>= today); prefetch slots for it.
  void _prefetchSlotsForFirstAvailableDay() {
    final today = _dateOnly(DateTime.now());
    final year = _visibleMonth.year;
    final month = _visibleMonth.month;
    final lastDay = DateTime(year, month + 1, 0).day;
    for (int day = 1; day <= lastDay; day++) {
      final d = DateTime(year, month, day);
      if (d.isBefore(today)) continue;
      final ymd = '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
      final a = _monthAvail[ymd];
      if (a != null && a.hasAvailability) {
        _prefetchSlotsForDay(d);
        return;
      }
    }
  }

  static const int _nextMonthWithAvailabilityMaxMonths = 6;

  /// Whether the currently visible month has any day with availability (from cache).
  bool _currentMonthHasAnyAvailability() {
    return _monthAvail.values.any((a) => a.hasAvailability);
  }

  /// Find next month that has at least one day with availability; use cache or load silently. Max 6 months.
  Future<DateTime?> _findNextMonthWithAvailability() async {
    final practitionerId = (_selectedPractitionerId ?? '').trim();
    if (practitionerId.isEmpty) return null;
    DateTime cursor = _visibleMonth.month == 12
        ? DateTime(_visibleMonth.year + 1, 1, 1)
        : DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1);
    for (int i = 0; i < _nextMonthWithAvailabilityMaxMonths; i++) {
      final key = '${cursor.year}-${cursor.month.toString().padLeft(2, '0')}';
      var monthData = _monthAvailCache[key];
      if (monthData == null) {
        await _loadMonthAvailability(forMonth: cursor, silent: true);
        if (!mounted) return null;
        monthData = _monthAvailCache[key];
        if (monthData == null) {
          cursor = cursor.month == 12 ? DateTime(cursor.year + 1, 1, 1) : DateTime(cursor.year, cursor.month + 1, 1);
          continue;
        }
      }
      final hasAny = monthData.values.any((a) => a.hasAvailability);
      if (hasAny) return cursor;
      cursor = cursor.month == 12 ? DateTime(cursor.year + 1, 1, 1) : DateTime(cursor.year, cursor.month + 1, 1);
    }
    return null;
  }

  /// Jump to next month with availability and optionally select first available day.
  Future<void> _goToNextMonthWithAvailability() async {
    final next = await _findNextMonthWithAvailability();
    if (!mounted || next == null) return;
    setState(() => _visibleMonth = next);
    await _loadMonthAvailability(forMonth: next);
    if (!mounted) return;
    final year = next.year;
    final month = next.month;
    final lastDay = DateTime(year, month + 1, 0).day;
    final monthData = _monthAvailCache['$year-${month.toString().padLeft(2, '0')}'];
    if (monthData != null) {
      final today = _dateOnly(DateTime.now());
      for (int day = 1; day <= lastDay; day++) {
        final d = DateTime(year, month, day);
        if (d.isBefore(today)) continue;
        final ymd = '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
        if (monthData[ymd]?.hasAvailability == true) {
          setState(() {
            _selectedDay = d;
            _selectedSlot = null;
          });
          await _loadSlots();
          return;
        }
      }
    }
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _prettyDate(DateTime d) =>
      '${_two(d.day)}/${_two(d.month)}/${d.year}';
  static String _prettyTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';
  static String _prettyDateTime(DateTime d) =>
      '${_prettyDate(d)} ${_prettyTime(d)}';

  Future<void> _showPreparingQuestionnaireDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        title: Text('Preparing questionnaire…'),
        content: Padding(
          padding: EdgeInsets.only(top: 8),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text('Please wait while we prepare your form.'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String> _createGeneralQuestionnaireToken({
    required _PatientFormResult patient,
  }) async {
    final functions = FirebaseFunctions.instanceFor(region: 'europe-west3');
    final fn = functions.httpsCallable('createGeneralQuestionnaireLinkFn');

    final res = await fn.call(<String, dynamic>{
      'clinicId': widget.clinicId.trim(),
      'email': patient.email,
      'expiresInDays': 7,
    });

    if (res.data is! Map) {
      throw Exception('Server returned unexpected payload: ${res.data}');
    }

    final data = Map<String, dynamic>.from(res.data as Map);
    final token = (data['token'] ?? '').toString().trim();
    if (token.isEmpty) {
      throw Exception('Server did not return a token.');
    }

    return token;
  }

  void _closeDialogIfOpen() {
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }

  /// ✅ Updated: ask which questionnaire to complete after booking
  Future<void> _askPreassessmentNextStep(
    _PatientFormResult patient, {
    required String bookingRequestId,
  }) async {
    final result = await showDialog<_IntakeChoice>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _QuestionnaireChoiceDialog(),
    );

    if (!mounted) return;
    if (result == null) return;

    await Future.delayed(_fadePause);
    if (!mounted) return;

    if (result == _IntakeChoice.skip) return;

    if (result == _IntakeChoice.preassessment) {
      await Navigator.of(context).push(
        PageRouteBuilder(
          transitionDuration: _fadeDuration,
          pageBuilder: (_, __, ___) => _PushNamedAfterFrame(
            routeName: AppRoutes.preassessmentConsent,
            arguments: {
              'clinicId': widget.clinicId,
              'bookingRequestId': bookingRequestId, // ✅ AUTO-LINK INPUT
              'prefillPatient': {
                'firstName': patient.firstName,
                'lastName': patient.lastName,
                'dobIso': patient.dob.toIso8601String(),
                'phone': patient.phone,
                'email': patient.email,
                'address': patient.address,
              },
            },
          ),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
      return;
    }

    if (result == _IntakeChoice.general) {
      unawaited(_showPreparingQuestionnaireDialog());
      try {
        final token =
            await _createGeneralQuestionnaireToken(patient: patient);
        _closeDialogIfOpen();
        if (!mounted) return;

        await Navigator.of(context).push(
          PageRouteBuilder(
            transitionDuration: _fadeDuration,
            pageBuilder: (_, __, ___) => _PushNamedAfterFrame(
              routeName:
                  '${AppRoutes.generalQuestionnaireTokenBase}/$token',
            ),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
        );
      } catch (e) {
        _closeDialogIfOpen();
        if (!mounted) return;
        final msg = e.toString().replaceFirst('Exception: ', '').trim();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              msg.isEmpty ? 'Could not start questionnaire.' : msg,
            ),
          ),
        );
      }
    }
  }

  /// ✅ Callable-only create:
  /// - Requires auth so callable has context.auth.uid
  /// - Uses selected practitionerId (dropdown)
  /// - Sends millis timestamps + dobMs
  /// - Sends BOTH practitionerId + clinicianId (migration-safe)
  Future<DocumentReference<Map<String, dynamic>>> _createBookingRequest({
    required DateTime startLocal,
    required _AppointmentType appt,
    required _PatientFormResult patient,
  }) async {
    final auth = FirebaseAuth.instance;
    final requesterUid = auth.currentUser?.uid;
    if (requesterUid == null) {
      throw Exception('Not signed in. Please refresh and try again.');
    }

    final user = auth.currentUser;
    if (user == null) {
      throw Exception('Not signed in (anonymous auth missing).');
    }

    // Ensure callable definitely has context.auth.uid
    await user.getIdToken(true);

    final endLocal = startLocal.add(Duration(minutes: appt.minutes));

    // Practitioner must be selected/resolved
    await _loadPractitionersIfNeeded();
    final practitionerId = (_selectedPractitionerId ?? '').trim();
    if (practitionerId.isEmpty) {
      throw Exception('Booking not available: Missing practitioner selection.');
    }

    final functions = FirebaseFunctions.instanceFor(region: 'europe-west3');
    final fn = functions.httpsCallable('createBookingRequestFn');

    final payload = <String, dynamic>{
      'clinicId': widget.clinicId.trim(),

      // migration-safe: support both field names
      'practitionerId': practitionerId,
      'clinicianId': practitionerId,

      'startUtcMs': startLocal.toUtc().millisecondsSinceEpoch,
      'endUtcMs': endLocal.toUtc().millisecondsSinceEpoch,

      'tz': 'Europe/Prague',
      'kind': (appt.kind == BookingKind.newPatient) ? 'newPatient' : 'followUp',

      'patient': {
        'firstName': patient.firstName,
        'lastName': patient.lastName,
        'dobMs': patient.dob.toUtc().millisecondsSinceEpoch,
        'phone': patient.phone,
        'email': patient.email,
        'address': patient.address,
        'consentToTreatment': patient.acceptsPolicies == true,
      },

      'appointment': {
        'minutes': appt.minutes,
        'label': appt.label,
        'priceText': appt.priceText,
        'description': appt.description,
      },

    };

    try {
      final res = await fn.call(payload);

      if (res.data is! Map) {
        throw Exception(
          'createBookingRequestFn returned unexpected data: ${res.data}',
        );
      }

      final data = Map<String, dynamic>.from(res.data as Map);

      // Most robust: returned path
      final path = (data['path'] ?? '').toString().trim();
      if (path.isNotEmpty) {
        return FirebaseFirestore.instance
            .doc(path)
            .withConverter<Map<String, dynamic>>(
              fromFirestore: (snap, _) => snap.data() ?? <String, dynamic>{},
              toFirestore: (value, _) => value,
            );
      }

      final bookingRequestId =
          (data['bookingRequestId'] ?? '').toString().trim();
      if (bookingRequestId.isEmpty) {
        throw Exception(
          'createBookingRequestFn did not return bookingRequestId or path',
        );
      }

      return _bookingRequestsCol.doc(bookingRequestId);
    } on FirebaseFunctionsException catch (e) {
      final msg = (e.message ?? '').trim();
      final details = e.details;

      final pretty = [
        'Booking failed',
        if (e.code.isNotEmpty) '[${e.code}]',
        if (msg.isNotEmpty) msg,
        if (details != null) 'details: $details',
      ].join(' ');

      throw Exception(pretty);
    } catch (e) {
      throw Exception('Booking failed: $e');
    }
  }

  Future<Map<String, dynamic>> _waitForBookingRequestResult(
    DocumentReference<Map<String, dynamic>> ref, {
    Duration timeout = _confirmTimeout,
  }) async {
    final completer = Completer<Map<String, dynamic>>();
    late final StreamSubscription sub;

    sub = ref.snapshots().listen(
      (snap) {
        final data = snap.data();
        if (data == null) return;

        final status = (data['status'] ?? '').toString();
        if (status == 'approved' || status == 'rejected') {
          if (!completer.isCompleted) completer.complete(data);
          sub.cancel();
        }
      },
      onError: (error) async {
        if (error is FirebaseException && error.code == 'permission-denied') {
          if (!completer.isCompleted) {
            completer.completeError(
              Exception(
                'Booking was created, but the app cannot read the booking request (permission-denied). '
                'Check Firestore rules for clinics/{clinicId}/bookingRequests/{requestId} reads. '
                'Typically you need: request.auth != null AND resource.data.requesterUid == request.auth.uid.',
              ),
            );
          }
        } else {
          if (!completer.isCompleted) completer.completeError(error);
        }
        await sub.cancel();
      },
    );

    Future.delayed(timeout).then((_) async {
      if (!completer.isCompleted) {
        await sub.cancel();
        completer.completeError(
          TimeoutException('No booking confirmation received.'),
        );
      }
    });

    return completer.future;
  }

  /// Used by BookingDetailsScreen to submit booking (create + wait for result).
  Future<Map<String, dynamic>?> _submitBookingFromDetails(
    _PublicSlot slot,
    _AppointmentType appt,
    _PatientFormResult patient,
  ) async {
    final ref = await _createBookingRequest(
      startLocal: slot.startLocal,
      appt: appt,
      patient: patient,
    );
    return _waitForBookingRequestResult(ref);
  }

  Future<void> _onTapSlot(_PublicSlot slot) async {
    if (!_ready) return;

    final now = DateTime.now();
    final cutoff = now.add(_minLeadTime);

    if (slot.startLocal.isBefore(now)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You cannot book an appointment in the past.'),
        ),
      );
      return;
    }
    if (slot.startLocal.isBefore(cutoff)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bookings must be made at least 1 hour in advance.'),
        ),
      );
      return;
    }
    if (slot.startLocal.minute != 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only hourly start times are available.'),
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _selectedSlot = slot);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BookingDetailsScreen(
          slot: slot,
          clinicId: widget.clinicId,
          prettyDateTime: _prettyDateTime,
          onSubmit: (appt, patient) =>
              _submitBookingFromDetails(slot, appt, patient),
          onSuccess: (
            Map<String, dynamic> data,
            _AppointmentType appt,
            _PatientFormResult patient,
          ) {
            if (!mounted) return;
            final path = (data['path'] ?? '').toString().trim();
            final id = path.isNotEmpty
                ? path.split('/').last
                : (data['bookingRequestId'] ?? '').toString().trim();
            Navigator.of(context).pop(); // pop details
            Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => BookingConfirmationScreen(
                  slotStartLocal: slot.startLocal,
                  apptType: appt,
                  bookingRequestId: id,
                  patient: patient,
                  clinicId: widget.clinicId,
                  onBackToBooking: () => Navigator.of(context).pop(),
                  onContinue: (p, reqId) =>
                      _askPreassessmentNextStep(p, bookingRequestId: reqId),
                  onGoHome: () {
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      AppRoutes.publicHome,
                      (r) => false,
                      arguments: {'clinicId': widget.clinicId},
                    );
                  },
                ),
              ),
            ).then((_) {
              if (mounted) _refreshAll();
            });
          },
        ),
      ),
    );
    if (mounted) _refreshAll();
  }

  @override
  Widget build(BuildContext context) {
    final cid = widget.clinicId.trim();
    if (cid.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(title: const Text('Book an appointment')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              'Missing clinicId.\n\nOpen the public portal with ?c=<ID>\n'
              'or navigate with arguments: { clinicId: <ID> }',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (_authError != null) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(title: const Text('Book an appointment')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 42),
                const SizedBox(height: 12),
                const Text(
                  'Unable to start booking',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(_authError!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_ready) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(title: const Text('Book an appointment')),
        body: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final controlsWidget = KeyedSubtree(
      key: _clinicianKey,
      child: _BookingControls(
        selectedDay: _selectedDay,
        practitioners: _practitioners,
        selectedPractitionerId: _selectedPractitionerId,
        onPractitionerChanged: _onPractitionerChanged,
        loadingPractitioners: _loadingPractitioners,
        practitionersError: _practitionersError,
        selectedPractitionerLabel: _selectedPractitionerLabel(),
      ),
    );

    final hasClinician = (_selectedPractitionerId ?? '').trim().isNotEmpty;
    final monthNoAvailabilityHint = hasClinician &&
            _monthAvail.isNotEmpty &&
            !_currentMonthHasAnyAvailability()
        ? Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'No availability this month',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Skips months with no available times',
                  child: FilledButton(
                    onPressed: () => _goToNextMonthWithAvailability(),
                    child: const Text('Next month with availability'),
                  ),
                ),
              ],
            ),
          )
        : null;

    final availableTimesPanelWidget = KeyedSubtree(
      key: _slotsKey,
      child: _AvailableTimesPanel(
        selectedDay: _selectedDay,
        hasClinician: hasClinician,
        practitionerId: _selectedPractitionerId,
        loadingSlots: _loadingSlots,
        slotsError: _slotsError,
        slots: _slots,
        selectedSlot: _selectedSlot,
        isCorporateDay: false,
        prettyTime: _prettyTime,
        onSlotTap: _onTapSlot,
        onRefresh: _refreshAll,
        onNextAvailable: _jumpToNextAvailable,
        prettyDayLabel: _prettyLongDate,
        practitionerLabel: _selectedPractitionerLabel(),
      ),
    );

    return PublicBookingMirrorHealthBanner(
      clinicId: cid,
      child: PublicShell(
        title: null,
        subtitle: null,
        showBack: true,
        topRight: PublicContactActions(clinicId: cid, debugWhenEmpty: kDebugMode),
        scrollableCard: false,
        showPoweredBy: false,
        child: LayoutBuilder(
        builder: (context, constraints) {
          final isTwoCol =
              constraints.maxWidth >= PatientBookingSimpleScreen.twoColBreakpoint;

          if (isTwoCol) {
            return _TwoColumnBookingPanel(
              header: const PublicHeader(
                title: 'Choose a time',
                subtitle: 'Select clinician, then pick a day.',
              ),
              stepIndicator: const _BookingStepIndicator(step: 1),
              hasClinician: hasClinician,
              visibleMonth: _visibleMonth,
              selectedDay: _selectedDay,
              firstAllowedDay: _dateOnly(DateTime.now()),
              lastAllowedDay: _dateOnly(DateTime.now().add(const Duration(days: 365))),
              onMonthChanged: _setVisibleMonth,
              onDaySelected: _setSelectedDay,
              onRefresh: () async {
                await _refreshAll();
                if (mounted) _loadMonthAvailability();
              },
              availabilityByYmd: _monthAvail,
              loadingMonthAvail: _loadingMonthAvail,
              monthAvailError: _monthAvailError,
              controls: controlsWidget,
              slotSection: availableTimesPanelWidget,
              monthAvailabilityHint: monthNoAvailabilityHint,
            );
          }

          return _SingleColumnBookingPanel(
            scrollController: _scrollCtrl,
            calendarKey: _calendarKey,
            hasClinician: hasClinician,
            visibleMonth: _visibleMonth,
            selectedDay: _selectedDay,
            onDaySelected: _setSelectedDay,
            onMonthChanged: _setVisibleMonth,
            monthAvail: _monthAvail,
            loadingMonthAvail: _loadingMonthAvail,
            monthAvailError: _monthAvailError,
            onRefreshAll: _refreshAll,
            loadMonthAvailability: _loadMonthAvailability,
            controls: controlsWidget,
            selectedSlot: _selectedSlot,
            prettyTime: _prettyTime,
            slotSection: availableTimesPanelWidget,
            monthAvailabilityHint: monthNoAvailabilityHint,
          );
        },
        ),
      ),
    );
  }

  String _selectedPractitionerLabel() {
    final id = (_selectedPractitionerId ?? '').trim();
    if (id.isEmpty) return '';
    final match = _practitioners.where((p) => p.id == id).toList(growable: false);
    if (match.isEmpty) return _shortId(id);
    return match.first.displayName;
  }
}

DateTime _dateOnlyForBooking(DateTime d) =>
    DateTime(d.year, d.month, d.day);

String _twoDigits(int n) => n.toString().padLeft(2, '0');

const List<String> _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const List<String> _weekdaysShort = [
  'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
];

String _weekdayShort(DateTime d) => _weekdaysShort[d.weekday - 1];

String _prettyLongDate(DateTime d) =>
    '${_weekdayShort(d)} ${d.day} ${_monthNames[d.month - 1]} ${d.year}';

/// Step indicator for the booking grid screen (Step 1 of 3).
class _BookingStepIndicator extends StatelessWidget {
  final int step;

  const _BookingStepIndicator({required this.step});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Step $step of 3',
          style: theme.textTheme.labelSmall?.copyWith(
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Type — Details — Confirm',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.black45,
          ),
        ),
      ],
    );
  }
}

class _BookingControls extends StatelessWidget {
  final DateTime selectedDay;
  final List<_PractitionerOption> practitioners;
  final String? selectedPractitionerId;
  final void Function(String?) onPractitionerChanged;
  final bool loadingPractitioners;
  final String? practitionersError;
  final String selectedPractitionerLabel;

  const _BookingControls({
    required this.selectedDay,
    required this.practitioners,
    required this.selectedPractitionerId,
    required this.onPractitionerChanged,
    required this.loadingPractitioners,
    required this.practitionersError,
    required this.selectedPractitionerLabel,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final leadCutoff = now.add(const Duration(hours: 1));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InputDecorator(
          decoration: InputDecoration(
            labelText: 'Clinician',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.element),
            ),
            isDense: true,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: (selectedPractitionerId ?? '').trim().isEmpty
                  ? null
                  : selectedPractitionerId,
              hint: const Text('Select a clinician'),
              items: practitioners
                  .map(
                    (p) => DropdownMenuItem<String>(
                      value: p.id,
                      child: Text(p.displayName),
                    ),
                  )
                  .toList(),
              onChanged: loadingPractitioners ? null : onPractitionerChanged,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _dateOnlyForBooking(selectedDay) == _dateOnlyForBooking(now)
              ? 'Earliest bookable today: ${_twoDigits(leadCutoff.hour)}:${_twoDigits(leadCutoff.minute)}'
              : 'Book at least 1 hour in advance.',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
        ),
        if (loadingPractitioners)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        if (practitionersError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              practitionersError!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ),
      ],
    );
  }
}

/// Right-column panel: stable header + body states (no clinician, loading, no slots, slots).
class _AvailableTimesPanel extends StatelessWidget {
  final DateTime selectedDay;
  final bool hasClinician;
  final String? practitionerId;
  final bool loadingSlots;
  final String? slotsError;
  final List<_PublicSlot> slots;
  final _PublicSlot? selectedSlot;
  final bool isCorporateDay;
  final String Function(DateTime) prettyTime;
  final void Function(_PublicSlot) onSlotTap;
  final VoidCallback onRefresh;
  final VoidCallback? onNextAvailable;
  final String Function(DateTime) prettyDayLabel;
  final String? practitionerLabel;

  const _AvailableTimesPanel({
    required this.selectedDay,
    required this.hasClinician,
    this.practitionerId,
    required this.loadingSlots,
    this.slotsError,
    required this.slots,
    this.selectedSlot,
    required this.isCorporateDay,
    required this.prettyTime,
    required this.onSlotTap,
    required this.onRefresh,
    this.onNextAvailable,
    required this.prettyDayLabel,
    this.practitionerLabel,
  });

  static const double slotTileHeight = 58;
  static const double gridSpacing = AppSpacing.elementGap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formattedSelectedDate = hasClinician ? prettyDayLabel(selectedDay) : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.hasBoundedHeight && constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 400.0;
        return SizedBox(
          height: maxH,
          child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Available times',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            if (formattedSelectedDate != null)
              Text(
                formattedSelectedDate,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              )
            else
              Text('Select a date'),
          ],
        ),
        const SizedBox(height: 16),
        if (selectedSlot != null && practitionerLabel != null && practitionerLabel!.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$practitionerLabel · ${prettyTime(selectedSlot!.startLocal)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
                if (kIsWeb)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Times shown in local time',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.element),
            child: _buildBody(context),
          ),
        ),
      ],
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    if (!hasClinician) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Text(
            'Select a clinician to see availability.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.black54,
            ),
          ),
        ),
      );
    }
    if (loadingSlots) {
      return _LoadingPlaceholderGrid();
    }
    if (slotsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.elementGap),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 40,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 10),
              Text(
                slotsError!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    if (slots.isEmpty) {
      return SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'No appointments available',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Try another day or jump to the next available time.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.black45,
                  ),
                ),
                const SizedBox(height: 16),
                if (onNextAvailable != null)
                  FilledButton.icon(
                    onPressed: onNextAvailable,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: const Text('Next available'),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.02, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: Container(
        key: ValueKey(
            '${selectedDay.toIso8601String()}-${practitionerId ?? 'any'}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Tooltip(
                message: 'First available time on this day',
                child: Text(
                  'Earliest available',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final crossAxisCount = width < 260 ? 2 : (width < 520 ? 3 : (width < 900 ? 4 : 5));
            final childWidth = (width - (crossAxisCount - 1) * gridSpacing) / crossAxisCount;
            final childAspectRatio = childWidth / slotTileHeight;
            return SingleChildScrollView(
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 8),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: gridSpacing,
                  crossAxisSpacing: gridSpacing,
                  childAspectRatio: childAspectRatio,
                ),
                itemCount: slots.length,
                itemBuilder: (context, i) {
                  final s = slots[i];
                  final selected = selectedSlot != null &&
                      selectedSlot!.startLocal.millisecondsSinceEpoch == s.startLocal.millisecondsSinceEpoch;
                  return SlotTile(
                    label: prettyTime(s.startLocal),
                    corporate: isCorporateDay,
                    selected: selected,
                    badge: i == 0 ? 'Earliest' : null,
                    onTap: () => onSlotTap(s),
                  );
                },
              ),
            );
          },
        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 6–8 disabled placeholder tiles while loading (or searching next available).
class _LoadingPlaceholderGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width < 260 ? 2 : (width < 520 ? 3 : (width < 900 ? 4 : 5));
        final childWidth = (width - (crossAxisCount - 1) * _AvailableTimesPanel.gridSpacing) / crossAxisCount;
        final childAspectRatio = childWidth / _AvailableTimesPanel.slotTileHeight;
        const placeholders = 8;
        return GridView.builder(
          padding: const EdgeInsets.only(top: 8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: _AvailableTimesPanel.gridSpacing,
            crossAxisSpacing: _AvailableTimesPanel.gridSpacing,
            childAspectRatio: childAspectRatio,
          ),
          itemCount: placeholders,
          itemBuilder: (context, i) => Opacity(
            opacity: 0.5,
            child: SlotTile(
              label: '--:--',
              disabled: true,
            ),
          ),
        );
      },
    );
  }
}

/// Desktop layout: clinician fixed at top; below, two columns — left = month calendar, right = time slots.
class _TwoColumnBookingPanel extends StatelessWidget {
  final Widget header;
  final Widget stepIndicator;
  final bool hasClinician;
  final DateTime visibleMonth;
  final DateTime selectedDay;
  final DateTime firstAllowedDay;
  final DateTime lastAllowedDay;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDaySelected;
  final VoidCallback onRefresh;
  final Map<String, DayAvailability> availabilityByYmd;
  final bool loadingMonthAvail;
  final String? monthAvailError;
  final Widget controls;
  final Widget slotSection;
  final Widget? monthAvailabilityHint;

  const _TwoColumnBookingPanel({
    required this.header,
    required this.stepIndicator,
    required this.hasClinician,
    required this.visibleMonth,
    required this.selectedDay,
    required this.firstAllowedDay,
    required this.lastAllowedDay,
    required this.onMonthChanged,
    required this.onDaySelected,
    required this.onRefresh,
    required this.availabilityByYmd,
    required this.loadingMonthAvail,
    this.monthAvailError,
    required this.controls,
    required this.slotSection,
    this.monthAvailabilityHint,
  });

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    // Taller panel so the calendar has more vertical space (needs height more than width).
    final panelH = (h - 180).clamp(580.0, 820.0);

    return SizedBox(
      height: panelH,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1) Clinician fixed at top (full width)
          header,
          const SizedBox(height: 16),
          stepIndicator,
          const SizedBox(height: 16),
          controls,
          const SizedBox(height: 16),
          // 2) Below: two columns — left = month calendar (gets remaining space), right = narrow scrollable slots
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left: month calendar (Expanded so it gets more room; right column is fixed width)
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, innerConstraints) {
                          final calMaxHeight = (innerConstraints.maxHeight - 32).clamp(200.0, double.infinity);
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (monthAvailabilityHint != null) ...[
                                monthAvailabilityHint!,
                                const SizedBox(height: 8),
                              ],
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: 320.0.clamp(0.0, calMaxHeight),
                                  maxWidth: 400,
                                  maxHeight: calMaxHeight,
                                ),
                                child: InlineMonthCalendar(
                                    visibleMonth: visibleMonth,
                                    selectedDay: selectedDay,
                                    firstAllowedDay: firstAllowedDay,
                                    lastAllowedDay: lastAllowedDay,
                                    onDaySelected: onDaySelected,
                                    onMonthChanged: onMonthChanged,
                                    availabilityByYmd: availabilityByYmd,
                                    loadingAvailability: loadingMonthAvail,
                                    disableDaysWithoutAvailability: hasClinician,
                                    maxHeight: calMaxHeight,
                                    footer: Tooltip(
                                      message: 'Based on number of available times',
                                      child: const InlineMonthCalendarLegend(),
                                    ),
                                    trailingAction: IconButton(
                                      tooltip: 'Refresh',
                                      icon: loadingMonthAvail
                                          ? const SizedBox(
                                              height: 24,
                                              width: 24,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : const Icon(Icons.refresh),
                                      onPressed: loadingMonthAvail
                                          ? null
                                          : onRefresh,
                                    ),
                                  ),
                                ),
                          if (monthAvailError != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              monthAvailError!,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                        ],
                      );
                  },
                ),
              ),
              const SizedBox(width: 24),
              // Right: _AvailableTimesPanel — give bounded height so inner Expanded doesn't overflow
              SizedBox(
                width: PatientBookingSimpleScreen.slotsColMaxWidth,
                height: constraints.maxHeight,
                child: slotSection,
              ),
            ],
          );
        },
      ),
    ),
        ],
      ),
    );
  }
}

/// Mobile layout: one column — clinician → full calendar (fixed height) → time slots. Calendar always fully visible.
class _SingleColumnBookingPanel extends StatelessWidget {
  final ScrollController scrollController;
  final GlobalKey calendarKey;
  final bool hasClinician;
  final DateTime visibleMonth;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onDaySelected;
  final ValueChanged<DateTime> onMonthChanged;
  final Map<String, DayAvailability> monthAvail;
  final bool loadingMonthAvail;
  final String? monthAvailError;
  final Future<void> Function() onRefreshAll;
  final Future<void> Function() loadMonthAvailability;
  final Widget controls;
  final _PublicSlot? selectedSlot;
  final String Function(DateTime) prettyTime;
  final Widget slotSection;
  final Widget? monthAvailabilityHint;

  const _SingleColumnBookingPanel({
    required this.scrollController,
    required this.calendarKey,
    required this.hasClinician,
    required this.visibleMonth,
    required this.selectedDay,
    required this.onDaySelected,
    required this.onMonthChanged,
    required this.monthAvail,
    required this.loadingMonthAvail,
    this.monthAvailError,
    required this.onRefreshAll,
    required this.loadMonthAvailability,
    required this.controls,
    required this.selectedSlot,
    required this.prettyTime,
    required this.slotSection,
    this.monthAvailabilityHint,
  });

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PublicHeader(
            title: 'Choose a time',
            subtitle: 'Select clinician, then pick a day.',
          ),
          const SizedBox(height: 16),
          const _BookingStepIndicator(step: 1),
          const SizedBox(height: 12),
          controls,
          const SizedBox(height: 16),
          // 2) Calendar — fixed height so full 6-row month is always visible (no "only week" problem)
          if (monthAvailabilityHint != null) ...[
            monthAvailabilityHint!,
            const SizedBox(height: 8),
          ],
          SizedBox(
            height: _calendarHeightForMobile(context),
            child: KeyedSubtree(
              key: calendarKey,
              child: InlineMonthCalendar(
                visibleMonth: visibleMonth,
                selectedDay: selectedDay,
                firstAllowedDay: _dateOnly(DateTime.now()),
                lastAllowedDay: _dateOnly(DateTime.now().add(const Duration(days: 365))),
                onDaySelected: onDaySelected,
                onMonthChanged: onMonthChanged,
                availabilityByYmd: monthAvail,
                loadingAvailability: loadingMonthAvail,
                disableDaysWithoutAvailability: hasClinician,
                footer: Tooltip(
                  message: 'Based on number of available times',
                  child: const InlineMonthCalendarLegend(),
                ),
                trailingAction: IconButton(
                  tooltip: 'Refresh',
                  icon: loadingMonthAvail
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  onPressed: loadingMonthAvail
                      ? null
                      : () async {
                          await onRefreshAll();
                          await loadMonthAvailability();
                        },
                ),
              ),
            ),
          ),
          if (monthAvailError != null) ...[
            const SizedBox(height: 6),
            Text(
              monthAvailError!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sectionGap),
          if (selectedSlot != null) ...[
            Text(
              'Selected: ${prettyTime(selectedSlot!.startLocal)}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 6),
          ],
          SizedBox(
            height: 420,
            child: slotSection,
          ),
        ],
      ),
    );
  }
}

/// Fixed height so the full 6-row calendar grid is always visible on mobile (no scrolling the calendar).
double _calendarHeightForMobile(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  final cellW = (w - (AppSpacing.screenPadding * 2)) / 7;
  final cell = cellW.clamp(34.0, 44.0);
  const header = 48.0;
  const weekday = 18.0;
  const gaps = 8.0 + 6.0 + 8.0;
  final grid = cell * 6;
  const footer = 24.0 + 8.0;
  return header + weekday + gaps + grid + footer;
}

enum BookingKind { newPatient, followUp }

enum CorporateMode { linkOnly, codeUnlock }

enum _IntakeChoice { skip, preassessment, general }

class _AppointmentType {
  final int minutes;
  final BookingKind kind;
  final String label;
  final String priceText;
  final String description;

  const _AppointmentType({
    required this.minutes,
    required this.kind,
    required this.label,
    required this.priceText,
    required this.description,
  });
}

class _PatientFormResult {
  final String firstName;
  final String lastName;
  final DateTime dob;
  final String phone;
  final String email;
  final String address;
  final bool acceptsPolicies;

  const _PatientFormResult({
    required this.firstName,
    required this.lastName,
    required this.dob,
    required this.phone,
    required this.email,
    required this.address,
    required this.acceptsPolicies,
  });
}

class _PublicSlot {
  final DateTime startLocal;
  final DateTime endLocal;

  _PublicSlot({required this.startLocal, required this.endLocal});

  factory _PublicSlot.fromMap(Map<String, dynamic> m) {
    return _PublicSlot(
      startLocal:
          DateTime.fromMillisecondsSinceEpoch((m['startMs'] as num).toInt()),
      endLocal:
          DateTime.fromMillisecondsSinceEpoch((m['endMs'] as num).toInt()),
    );
  }
}

class _PractitionerOption {
  final String id;
  final String displayName;

  const _PractitionerOption({
    required this.id,
    required this.displayName,
  });
}

// -----------------------------------------------------------------------------
// Full-screen booking flow (replaces appointment type, patient details, confirm dialogs)
// -----------------------------------------------------------------------------

class BookingDetailsScreen extends StatefulWidget {
  final _PublicSlot slot;
  final String clinicId;
  final String Function(DateTime) prettyDateTime;
  final Future<Map<String, dynamic>?> Function(
    _AppointmentType appt,
    _PatientFormResult patient,
  ) onSubmit;
  final void Function(
    Map<String, dynamic> data,
    _AppointmentType appt,
    _PatientFormResult patient,
  ) onSuccess;

  const BookingDetailsScreen({
    super.key,
    required this.slot,
    required this.clinicId,
    required this.prettyDateTime,
    required this.onSubmit,
    required this.onSuccess,
  });

  @override
  State<BookingDetailsScreen> createState() => _BookingDetailsScreenState();
}

class _BookingDetailsScreenState extends State<BookingDetailsScreen> {
  int _step = 0;
  _AppointmentType? _apptType;
  _PatientFormResult? _patient;
  bool _submitting = false;
  String? _error;

  static const _typeInitial = _AppointmentType(
    minutes: 60,
    kind: BookingKind.newPatient,
    label: 'Initial consultation (60 mins)',
    priceText: '1300 Kč',
    description:
        'Initial consultation, mobility assessment & manual techniques',
  );
  static const _typeFollowUp = _AppointmentType(
    minutes: 45,
    kind: BookingKind.followUp,
    label: 'Follow-up (45 mins)',
    priceText: '1000 Kč',
    description:
        'Follow-up focusing on movement progression & soft-tissue work',
  );

  static const Duration _stepTransitionDuration = Duration(milliseconds: 240);

  @override
  Widget build(BuildContext context) {
    return PublicShell(
      showBack: true,
      scrollableCard: true,
      showPoweredBy: false,
      title: null,
      subtitle: null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStepIndicator(context),
          const SizedBox(height: AppSpacing.sectionGap),
          AnimatedSize(
            duration: _stepTransitionDuration,
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: _stepTransitionDuration,
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) {
                final fade = FadeTransition(opacity: anim, child: child);
                final offsetAnim = Tween<Offset>(
                  begin: const Offset(0, 0.03),
                  end: Offset.zero,
                ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut));
                return SlideTransition(position: offsetAnim, child: fade);
              },
              child: KeyedSubtree(
                key: ValueKey<int>(_submitting ? 3 : _step),
                child: _buildStepBody(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepBody() {
    if (_submitting) return _buildSubmitting();
    switch (_step) {
      case 0:
        return _buildStepType();
      case 1:
        return _buildStepPatient();
      default:
        return _buildStepConfirm();
    }
  }

  Widget _buildStepIndicator(BuildContext context) {
    final theme = Theme.of(context);
    final step = _submitting ? 3 : (_step + 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Step $step of 3',
          style: theme.textTheme.labelSmall?.copyWith(
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Appointment type → Details → Confirm',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.black45,
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitting() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TherapyLoadingIndicator(
              size: 40,
              color: Theme.of(context).colorScheme.primary,
              iconAssetPaths: TherapyLoadingIndicator.therapyIconPaths,
            ),
            const SizedBox(height: 16),
            Text(
              'Submitting booking…',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepType() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const PublicHeader(
          title: 'Choose appointment type',
          subtitle: 'Select one option to continue.',
        ),
        const SizedBox(height: AppSpacing.sectionGap),
        _TypeOptionTile(
          type: _typeInitial,
          onTap: () {
            setState(() {
              _apptType = _typeInitial;
              _step = 1;
              _error = null;
            });
          },
        ),
        const SizedBox(height: AppSpacing.elementGap),
        _TypeOptionTile(
          type: _typeFollowUp,
          onTap: () {
            setState(() {
              _apptType = _typeFollowUp;
              _step = 1;
              _error = null;
            });
          },
        ),
      ],
    );
  }

  Widget _buildStepPatient() {
    return _PatientFormStep(
      kind: _apptType!.kind,
      onCancel: () => setState(() => _step = 0),
      onContinue: (result) {
        setState(() {
          _patient = result;
          _step = 2;
          _error = null;
        });
      },
    );
  }

  Widget _buildStepConfirm() {
    final theme = Theme.of(context);
    final appt = _apptType!;
    final patient = _patient!;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const PublicHeader(
            title: 'Confirm booking',
            subtitle: 'Review and confirm your appointment.',
          ),
          const SizedBox(height: AppSpacing.sectionGap),
          Text(
            '${appt.label} — ${appt.priceText}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.prettyDateTime(widget.slot.startLocal),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${patient.firstName} ${patient.lastName}',
            style: theme.textTheme.bodyMedium,
          ),
          Text(
            patient.email,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.black54,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              TextButton(
                onPressed: () => setState(() => _step = 1),
                child: const Text('Back'),
              ),
              const SizedBox(width: AppSpacing.elementGap),
              Expanded(
                child: SizedBox(
                  height: AppSizes.buttonHeight,
                  child: FilledButton(
                    onPressed: _confirmTap,
                    child: const Text('Confirm booking'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmTap() async {
    if (_apptType == null || _patient == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final data = await widget.onSubmit(_apptType!, _patient!);
      if (!mounted) return;

      final status = (data?['status'] ?? '').toString();
      if (status == 'rejected') {
        final reason = (data?['rejectionReason'] ?? 'Booking rejected.').toString();
        setState(() {
          _submitting = false;
          _error = reason;
        });
        return;
      }

      if (status == 'approved' || data != null) {
        widget.onSuccess(data!, _apptType!, _patient!);
        return;
      }

      setState(() => _submitting = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString().replaceFirst('Exception: ', '').trim();
      });
    }
  }
}

class _TypeOptionTile extends StatelessWidget {
  final _AppointmentType type;
  final VoidCallback onTap;

  const _TypeOptionTile({required this.type, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.element),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 16,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.element),
          border: Border.all(color: AppColors.subtleBorder),
        ),
        child: Row(
          children: [
            Icon(
              type.kind == BookingKind.newPatient
                  ? Icons.timer_outlined
                  : Icons.timer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${type.label} — ${type.priceText}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    type.description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.black54,
                        ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14),
          ],
        ),
      ),
    );
  }
}

class _PatientFormStep extends StatefulWidget {
  final BookingKind kind;
  final VoidCallback onCancel;
  final void Function(_PatientFormResult result) onContinue;

  const _PatientFormStep({
    required this.kind,
    required this.onCancel,
    required this.onContinue,
  });

  @override
  State<_PatientFormStep> createState() => _PatientFormStepState();
}

class _PatientFormStepState extends State<_PatientFormStep> {
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  DateTime? _dob;
  bool _acceptsPolicies = false;

  static String _prettyDate(DateTime d) {
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    return '$day/$month/${d.year}';
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  bool _valid() {
    return _firstNameCtrl.text.trim().isNotEmpty &&
        _lastNameCtrl.text.trim().isNotEmpty &&
        _dob != null &&
        _emailCtrl.text.trim().isNotEmpty &&
        _phoneCtrl.text.trim().isNotEmpty &&
        _acceptsPolicies;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          PublicHeader(
            title: widget.kind == BookingKind.newPatient
                ? 'Your details'
                : 'Client details',
            subtitle: 'We need these to confirm your appointment.',
          ),
          const SizedBox(height: AppSpacing.sectionGap),
          TextField(
            controller: _firstNameCtrl,
            decoration: const InputDecoration(
              labelText: 'First name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _lastNameCtrl,
            decoration: const InputDecoration(
              labelText: 'Last name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.cake_outlined),
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime(now.year - 30, now.month, now.day),
                firstDate: DateTime(1900, 1, 1),
                lastDate: now,
              );
              if (picked != null) setState(() => _dob = picked);
            },
            label: Text(_dob == null ? 'Date of birth' : _prettyDate(_dob!)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
            decoration: const InputDecoration(
              labelText: 'Phone',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailCtrl,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _addressCtrl,
            decoration: const InputDecoration(
              labelText: 'Address (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _acceptsPolicies,
                onChanged: (v) =>
                    setState(() => _acceptsPolicies = v ?? false),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'I have read and understand the policies (privacy, consent & cancellation).',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    TextButton(
                      onPressed: () {
                        showDialog<void>(
                          context: context,
                          builder: (_) => const _PolicyPreviewDialog(),
                        );
                      },
                      child: const Text('View policies'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              TextButton(
                onPressed: widget.onCancel,
                child: const Text('Back'),
              ),
              const SizedBox(width: AppSpacing.elementGap),
              Expanded(
                child: SizedBox(
                  height: AppSizes.buttonHeight,
                  child: FilledButton(
                    onPressed: () {
                      if (!_valid()) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Please complete all required fields and accept the policies.',
                            ),
                          ),
                        );
                        return;
                      }
                      widget.onContinue(
                        _PatientFormResult(
                          firstName: _firstNameCtrl.text.trim(),
                          lastName: _lastNameCtrl.text.trim(),
                          dob: _dob!,
                          phone: _phoneCtrl.text.trim(),
                          email: _emailCtrl.text.trim(),
                          address: _addressCtrl.text.trim(),
                          acceptsPolicies: _acceptsPolicies,
                        ),
                      );
                    },
                    child: const Text('Continue'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class BookingConfirmationScreen extends StatelessWidget {
  final DateTime slotStartLocal;
  final _AppointmentType apptType;
  final String bookingRequestId;
  final _PatientFormResult patient;
  final String clinicId;
  final VoidCallback onBackToBooking;
  final void Function(_PatientFormResult patient, String bookingRequestId)
      onContinue;
  final VoidCallback onGoHome;

  const BookingConfirmationScreen({
    super.key,
    required this.slotStartLocal,
    required this.apptType,
    required this.bookingRequestId,
    required this.patient,
    required this.clinicId,
    required this.onBackToBooking,
    required this.onContinue,
    required this.onGoHome,
  });

  static String _prettyDateTime(DateTime d) {
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    final hour = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$day/$month/${d.year} $hour:$min';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PublicShell(
      showBack: true,
      maxWidth: AppSizes.welcomeMaxWidth,
      showPoweredBy: false,
      title: null,
      subtitle: null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 56,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Your appointment is confirmed',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '${apptType.label} — ${apptType.priceText}\n'
            '${_prettyDateTime(slotStartLocal)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.black54,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: AppSizes.buttonHeight,
            child: FilledButton(
              onPressed: () {
                onBackToBooking();
                onContinue(patient, bookingRequestId);
              },
              child: const Text('Continue'),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onBackToBooking,
            child: const Text('Back to booking'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onGoHome,
            style: TextButton.styleFrom(
              foregroundColor: theme.textTheme.bodySmall?.color,
            ),
            child: Text(
              'Home',
              style: theme.textTheme.bodySmall?.copyWith(
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Dialogs / helpers
// -----------------------------------------------------------------------------
class _QuestionnaireChoiceDialog extends StatelessWidget {
  const _QuestionnaireChoiceDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Questionnaire'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Would you like to complete a questionnaire now?',
          ),
          const SizedBox(height: 10),
          Text(
            'Questionnaires help your clinician understand your goals and symptoms before you arrive.',
            style: theme.textTheme.bodySmall?.copyWith(
              height: 1.35,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton(
                  onPressed: () =>
                      Navigator.pop(context, _IntakeChoice.skip),
                  child: const Text('Skip and continue booking'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, _IntakeChoice.preassessment),
                  child:
                      const Text('Specific issue (Preassessment questionnaire)'),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: () =>
                      Navigator.pop(context, _IntakeChoice.general),
                  child: const Text(
                      'General issue (General questionnaire)'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PushNamedAfterFrame extends StatelessWidget {
  final String routeName;
  final Object? arguments;

  const _PushNamedAfterFrame({
    required this.routeName,
    this.arguments,
  });

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context)
          .pushReplacementNamed(routeName, arguments: arguments);
    });
    return const Scaffold(
        backgroundColor: Colors.white, body: SizedBox.shrink());
  }
}

class _PolicyPreviewDialog extends StatelessWidget {
  const _PolicyPreviewDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Policies (Preview)'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(kPrivacyPolicyText, style: TextStyle(fontSize: 13)),
            SizedBox(height: 16),
            Divider(),
            SizedBox(height: 12),
            Text(kTreatmentLiabilityText, style: TextStyle(fontSize: 13)),
            SizedBox(height: 16),
            Divider(),
            SizedBox(height: 12),
            Text(kCancellationPolicyText, style: TextStyle(fontSize: 13)),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: Navigator.of(context).pop,
          child: const Text('Close'),
        ),
      ],
    );
  }
}

// --- policy text constants unchanged ---
const String kPrivacyPolicyText = '''
Privacy & Data Protection Policy (Preview Version)

Fundamental Recovery
Operated by: Graeme Lawson
IČO: To be confirmed
Kolbenova 16, Praha 9, 190 00, Czech Republic
Email: admin@fundamentalrecovery.net
Phone: +420 773 076 872

Version 1.0 — Last updated: [date will be added]

This policy explains how your personal information is collected, stored, and used in compliance with the EU General Data Protection Regulation (GDPR) and Czech data privacy law.

1. What information is collected
• Name, contact information (email, phone)
• Health and medical history relevant to treatment
• Assessment findings, treatment notes, exercise plans
• Appointment and payment history

2. Why this information is collected
Your data is collected for the purpose of:
• Providing safe and appropriate manual therapy and rehabilitation services
• Booking and managing appointments
• Communicating regarding your care and follow-up recommendations
• Meeting legal or contractual obligations

3. Legal basis
Your data is processed under:
• Your explicit consent (Article 6 & 9 GDPR)
• Legitimate interest to provide continuity of care

4. Storage and security
Data may be stored:
• Securely via the clinical software platform KineticDx, which acts as a GDPR-compliant data processor, or
• In secure encrypted electronic systems or locked paper files controlled solely by the therapist.

Access to your data is restricted to the treating practitioner.

5. Retention
Records are kept for 5–10 years, depending on legal and clinical requirements, after which they will be securely deleted.

6. Your rights
You may request:
• A copy of your data
• Correction of inaccurate information
• Restricted processing
• Transfer of data to another provider
• Deletion where legally appropriate

7. Withdrawal of consent
You may withdraw consent for future processing at any time. However, treatment records already created may be retained as required by law.

8. Complaints
You may raise concerns with:
Úřad pro ochranu osobných údajů (Czech Data Protection Authority).
''';

const String kTreatmentLiabilityText = '''
Consent to Treatment & Liability Agreement (Preview)

By receiving services at Fundamental Recovery, you acknowledge and agree to the following:

• The therapy provided may include soft-tissue treatment, joint mobilisations, taping, and guided movement.
• This service is not medical diagnosis and does not replace medical care from a doctor or licensed physiotherapist.
• Results cannot be guaranteed as every individual responds differently.
• Temporary reactions may occur, including muscle soreness, fatigue, or short-term symptom aggravation.

You confirm that:
• The information you provide about your health is accurate to the best of your knowledge.
• You will inform the therapist of any change to your health or medication.
• You voluntarily consent to assessment and treatment.
''';

const String kCancellationPolicyText = '''
Cancellation & Scheduling Policy (Preview)

To ensure fair access to appointments, the following terms apply:

• Appointments cancelled with more than 24 hours' notice — no charge.
• Cancellations with less than 24 hours' notice — 50% fee applies.
• Missed appointments / no-shows — 80% of the session fee.
• Late arrivals will result in a shortened session; full fee still applies.

By booking an appointment, you confirm that you understand and accept this policy.
''';
