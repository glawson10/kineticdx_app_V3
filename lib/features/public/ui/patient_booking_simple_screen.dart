// lib/features/public/ui/patient_booking_simple_screen.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_routes.dart';

/// ---------------------------------------------------------------------------
/// Public contact actions (top-right icons)
///
/// Reads from public mirror:
///   clinics/{clinicId}/public/config/publicBooking/publicBooking
///
/// ✅ Supports BOTH schemas:
/// A) Nested map:
///   contact: { landingUrl?, websiteUrl?, email?, phone?, whatsapp? }
/// B) Root keys (legacy/new):
///   landingUrl, websiteUrl, email, phone, whatsapp
///
/// Icons shown:
/// - Website (landingUrl else websiteUrl)
/// - Email
/// - WhatsApp (whatsapp if present; else phone used to build wa.me/digits)
///
/// If NOTHING is configured:
/// - returns SizedBox.shrink() in release
/// - in debug mode it can show a small "no links" pill so you can confirm it
///   is mounted and the issue is data, not layout.
/// ---------------------------------------------------------------------------
class _PublicContactActions extends StatelessWidget {
  final String clinicId;

  /// When true, shows a small debug pill when no links are found.
  /// Useful while wiring.
  final bool debugWhenEmpty;

  const _PublicContactActions({
    required this.clinicId,
    this.debugWhenEmpty = false,
  });

  DocumentReference<Map<String, dynamic>> get _publicBookingDoc =>
      FirebaseFirestore.instance
          .collection('clinics')
          .doc(clinicId)
          .collection('public')
          .doc('config')
          .collection('publicBooking')
          .doc('publicBooking');

  static String _s(dynamic v) => (v ?? '').toString().trim();

  static Uri? _tryParseUrl(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;

    final hasScheme = s.startsWith('http://') || s.startsWith('https://');
    final normalized = hasScheme ? s : 'https://$s';

    try {
      final u = Uri.parse(normalized);
      if (!u.hasScheme) return null;
      return u;
    } catch (_) {
      return null;
    }
  }

  static Uri? _mailto(String email) {
    final e = email.trim();
    if (e.isEmpty || !e.contains('@')) return null;
    return Uri(scheme: 'mailto', path: e);
  }

  static Uri? _whatsappFrom(String whatsappOrPhone) {
    final s = whatsappOrPhone.trim();
    if (s.isEmpty) return null;

    // Allow full links
    if (s.startsWith('http://') || s.startsWith('https://')) {
      return _tryParseUrl(s);
    }
    // Allow wa.me/...
    if (s.startsWith('wa.me/')) return _tryParseUrl('https://$s');

    // Otherwise treat as phone-like
    final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return Uri.parse('https://wa.me/$digits');
  }

  static Future<void> _launch(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open: $uri')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _publicBookingDoc.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? const <String, dynamic>{};

        // ✅ Prefer nested contact map, but support root keys too.
        final contact = (data['contact'] is Map)
            ? Map<String, dynamic>.from(data['contact'] as Map)
            : const <String, dynamic>{};

        String pick(String key) {
          final fromContact = _s(contact[key]);
          if (fromContact.isNotEmpty) return fromContact;
          return _s(data[key]);
        }

        final landingUrl = pick('landingUrl');
        final websiteUrl = pick('websiteUrl');
        final email = pick('email');
        final phone = pick('phone');
        final whatsapp = pick('whatsapp');

        final Uri? webUri =
            _tryParseUrl(landingUrl.isNotEmpty ? landingUrl : websiteUrl);
        final Uri? mailUri = _mailto(email);

        // ✅ WhatsApp preference: whatsapp field, else phone field
        final waSource = whatsapp.isNotEmpty ? whatsapp : phone;
        final Uri? waUri = _whatsappFrom(waSource);

        final actions = <Widget>[];

        if (webUri != null) {
          actions.add(
            IconButton(
              tooltip: 'Website',
              icon: const Icon(Icons.public),
              onPressed: () => _launch(context, webUri),
            ),
          );
        }

        if (mailUri != null) {
          actions.add(
            IconButton(
              tooltip: 'Email',
              icon: const Icon(Icons.email_outlined),
              onPressed: () => _launch(context, mailUri),
            ),
          );
        }

        if (waUri != null) {
          actions.add(
            IconButton(
              tooltip: 'WhatsApp',
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: () => _launch(context, waUri),
            ),
          );
        }

        // Nothing configured
        if (actions.isEmpty) {
          if (kDebugMode && debugWhenEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border:
                      Border.all(color: Colors.orange.withValues(alpha: 0.35)),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(
                    'No public links',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            );
          }
          return const SizedBox.shrink();
        }

        return DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: actions),
          ),
        );
      },
    );
  }
}

class PatientBookingSimpleScreen extends StatefulWidget {
  static const String routeName = AppRoutes.patientBookSimple;

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
  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

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

  // --- Day metadata (from Cloud Function response dayFlags) ---
  bool _loadingDayMeta = false;
  String? _dayMetaError;

  bool _isCorporateDay = false;
  String _locationLabel = '';
  CorporateMode? _corpMode;
  String? _corpDisplayName;

  // User-entered / deep-linked corporate code
  String _corporateCode = '';

  // --- Slots ---
  bool _loadingSlots = false;
  String? _slotsError;
  List<_PublicSlot> _slots = [];
  Map<String, dynamic> _dayFlags = {};

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
    _corporateCode = (widget.initialCorporateCodeFromUrl ?? '').trim();

    // If deep-linked clinicianId exists, set initial selection immediately.
    final deepLinked = (widget.clinicianId ?? '').trim();
    if (deepLinked.isNotEmpty) {
      _selectedPractitionerId = deepLinked;
    }

    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    setState(() {
      _authReady = false;
      _authError = null;
      _slotsError = null;
      _dayMetaError = null;
      _practitionersError = null;
    });

    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }

      if (!mounted) return;
      setState(() => _authReady = true);

      await _refreshAll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _authError = 'Anonymous sign-in failed: $e';
        _authReady = false;
      });
    }
  }

  Future<void> _refreshAll() async {
    // ✅ practitioners must be loaded before slots (needs practitionerId)
    await _loadPractitionersIfNeeded();
    await _loadSlots();
    await _loadDayMetaFromDayFlags();
  }

  Future<void> _loadDayMetaFromDayFlags() async {
    setState(() {
      _loadingDayMeta = true;
      _dayMetaError = null;
      _isCorporateDay = false;
      _locationLabel = '';
      _corpMode = null;
      _corpDisplayName = null;
    });

    try {
      final ymd = _ymdFromLocalDay(_selectedDay);
      final raw = _dayFlags[ymd];

      if (raw is Map) {
        final corporateOnly = raw['corporateOnly'] == true;
        final mode = (raw['mode'] ?? '').toString().trim();
        final displayName = (raw['displayName'] ?? '').toString().trim();
        final locationLabel = (raw['locationLabel'] ?? '').toString().trim();

        setState(() {
          _isCorporateDay = corporateOnly;
          _corpMode = (mode == 'CODE_UNLOCK')
              ? CorporateMode.codeUnlock
              : (mode == 'LINK_ONLY')
                  ? CorporateMode.linkOnly
                  : null;
          _corpDisplayName = displayName.isEmpty ? null : displayName;
          _locationLabel = locationLabel;
        });
      } else {
        setState(() {
          _isCorporateDay = false;
          _locationLabel = '';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dayMetaError = 'Failed to load day details: $e';
        _isCorporateDay = false;
        _locationLabel = '';
      });
    } finally {
      if (mounted) setState(() => _loadingDayMeta = false);
    }
  }

  static String _ymdFromLocalDay(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
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

    // Practitioner affects slots (and may affect "openingWindows" semantics), so reload.
    await _refreshAll();
  }

  List<_PublicSlot> _applySlotFilters(List<_PublicSlot> input) {
    final now = DateTime.now();
    final cutoff = now.add(_minLeadTime);

    bool isHourlyStart(DateTime d) =>
        d.minute == 0 &&
        d.second == 0 &&
        d.millisecond == 0 &&
        d.microsecond == 0;

    final selectedDate = _dateOnly(_selectedDay);
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
    setState(() {
      _loadingSlots = true;
      _slotsError = null;
      _slots = [];
      _dayFlags = {};
    });

    final startLocal = _selectedDay;
    final startUtc =
        DateTime.utc(startLocal.year, startLocal.month, startLocal.day, 0, 0);
    final endUtc = startUtc.add(const Duration(days: 1));

    try {
      // Ensure practitioners are ready and we have a practitionerId
      await _loadPractitionersIfNeeded();
      final practitionerId = (_selectedPractitionerId ?? '').trim();
      if (practitionerId.isEmpty) {
        throw StateError(
            'Booking not available: Missing practitioner selection.');
      }

      final functions = FirebaseFunctions.instanceFor(region: 'europe-west3');
      final fn = functions.httpsCallable('listPublicSlotsFn');

      final payload = <String, dynamic>{
        'clinicId': widget.clinicId.trim(),
        'serviceId': 'default',
        'practitionerId': practitionerId,
        'rangeStartMs': startUtc.millisecondsSinceEpoch,
        'rangeEndMs': endUtc.millisecondsSinceEpoch,
        'tz': 'Europe/Prague',
        if (_corporateCode.trim().isNotEmpty) 'corpCode': _corporateCode.trim(),
      };

      final res = await fn.call(payload).timeout(_confirmTimeout);

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

      final df = data['dayFlags'];
      final dayFlags =
          (df is Map) ? Map<String, dynamic>.from(df) : <String, dynamic>{};

      if (!mounted) return;
      setState(() {
        _slots = filtered;
        _dayFlags = dayFlags;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _slotsError = 'Failed to load availability: $e');
    } finally {
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: _dateOnly(now),
      lastDate: _dateOnly(now.add(const Duration(days: 365))),
    );
    if (picked != null) {
      setState(() => _selectedDay = _dateOnly(picked));
      await _refreshAll();
    }
  }

  void _clearCorporateCode() {
    setState(() => _corporateCode = '');
    _refreshAll();
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _prettyDate(DateTime d) =>
      '${_two(d.day)}/${_two(d.month)}/${d.year}';
  static String _prettyTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';
  static String _prettyDateTime(DateTime d) =>
      '${_prettyDate(d)} ${_prettyTime(d)}';

  Future<_AppointmentType?> _askAppointmentType() async {
    return showDialog<_AppointmentType>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Choose appointment type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Initial consultation (60 mins) — 1300 Kč'),
              subtitle: const Text(
                'Initial consultation, mobility assessment & manual techniques',
              ),
              onTap: () => Navigator.pop(
                context,
                const _AppointmentType(
                  minutes: 60,
                  kind: BookingKind.newPatient,
                  label: 'Initial consultation (60 mins)',
                  priceText: '1300 Kč',
                  description:
                      'Initial consultation, mobility assessment & manual techniques',
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.timer),
              title: const Text('Follow-up (45 mins) — 1000 Kč'),
              subtitle: const Text(
                'Follow-up focusing on movement progression & soft-tissue work',
              ),
              onTap: () => Navigator.pop(
                context,
                const _AppointmentType(
                  minutes: 45,
                  kind: BookingKind.followUp,
                  label: 'Follow-up (45 mins)',
                  priceText: '1000 Kč',
                  description:
                      'Follow-up focusing on movement progression & soft-tissue work',
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<bool> _promptForCorporateCode() async {
    final controller = TextEditingController(text: _corporateCode);
    String? errorText;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: const Text('Corporate booking code'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This day is reserved for corporate appointments.\n'
                    'Enter your company booking code to continue.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Enter code',
                      errorText: errorText,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final entered = controller.text.trim();
                    if (entered.isEmpty) {
                      setState(() => errorText = 'Please enter a code');
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
                  child: const Text('Continue'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok == true) {
      setState(() => _corporateCode = controller.text.trim());
      _refreshAll();
      return true;
    }
    return false;
  }

  Future<bool> _ensureCorporateAccessForSelectedDay() async {
    if (!_isCorporateDay) return true;

    final needsCode = (_corpMode == CorporateMode.codeUnlock);

    if (!needsCode) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(
            _corpDisplayName?.isNotEmpty == true
                ? _corpDisplayName!
                : 'Corporate day',
          ),
          content: const Text(
            'This day is reserved for corporate appointments.\n\n'
            'If you are not a corporate client, please choose another date or contact the clinic.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Choose another date'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('I am a corporate client'),
            ),
          ],
        ),
      );
      return proceed == true;
    }

    if (_corporateCode.trim().isNotEmpty) return true;
    return _promptForCorporateCode();
  }

  Future<_PatientFormResult?> _askPatientDetailsPopup(BookingKind kind) async {
    final firstNameCtrl = TextEditingController();
    final lastNameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addressCtrl = TextEditingController();

    DateTime? dob;
    bool acceptsPolicies = false;

    Future<void> pickDob(StateSetter setState) async {
      final now = DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate: DateTime(now.year - 30, now.month, now.day),
        firstDate: DateTime(1900, 1, 1),
        lastDate: now,
      );
      if (picked != null) setState(() => dob = picked);
    }

    bool valid() {
      if (firstNameCtrl.text.trim().isEmpty) return false;
      if (lastNameCtrl.text.trim().isEmpty) return false;
      if (dob == null) return false;
      if (emailCtrl.text.trim().isEmpty) return false;
      if (phoneCtrl.text.trim().isEmpty) return false;
      if (!acceptsPolicies) return false;
      return true;
    }

    final result = await showDialog<_PatientFormResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(
            kind == BookingKind.newPatient
                ? 'New client details'
                : 'Client details',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: firstNameCtrl,
                  decoration: const InputDecoration(labelText: 'First name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: lastNameCtrl,
                  decoration: const InputDecoration(labelText: 'Last name'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.cake_outlined),
                        onPressed: () => pickDob(setState),
                        label: Text(
                          dob == null ? 'Date of birth' : _prettyDate(dob!),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: addressCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Address (optional)'),
                ),
                const SizedBox(height: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: acceptsPolicies,
                          onChanged: (v) =>
                              setState(() => acceptsPolicies = v ?? false),
                        ),
                        const Expanded(
                          child: Text(
                            'I have read and understand the policies (privacy, consent & cancellation).',
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 48, top: 4),
                      child: InkWell(
                        onTap: () {
                          showDialog<void>(
                            context: context,
                            builder: (_) => const _PolicyPreviewDialog(),
                          );
                        },
                        child: Text(
                          'View policies (Preview)',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                    if (!acceptsPolicies)
                      const Padding(
                        padding: EdgeInsets.only(left: 48, top: 6),
                        child: Text(
                          'Required to continue.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!valid()) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Please complete all required fields and accept the policies.',
                      ),
                    ),
                  );
                  return;
                }
                Navigator.pop(
                  ctx,
                  _PatientFormResult(
                    firstName: firstNameCtrl.text.trim(),
                    lastName: lastNameCtrl.text.trim(),
                    dob: dob!,
                    phone: phoneCtrl.text.trim(),
                    email: emailCtrl.text.trim(),
                    address: addressCtrl.text.trim(),
                    acceptsPolicies: acceptsPolicies,
                  ),
                );
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );

    firstNameCtrl.dispose();
    lastNameCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
    addressCtrl.dispose();

    return result;
  }

  Future<bool> _confirmBookingPopup({
    required DateTime slotStartLocal,
    required _AppointmentType apptType,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm booking'),
        content: Text(
          'You are booking:\n\n'
          '${apptType.label} (${apptType.priceText})\n'
          '${_prettyDateTime(slotStartLocal)}\n\n'
          'Proceed?',
        ),
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
    );
    return ok == true;
  }

  Future<void> _showSubmittingDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        title: Text('Submitting booking…'),
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
                child: Text('Please wait while we confirm your appointment.'),
              ),
            ],
          ),
        ),
      ),
    );
  }

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

  Future<void> _bookingConfirmedPopup({
    required DateTime slotStartLocal,
    required _AppointmentType apptType,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Booking confirmed'),
        content: Text(
          'Your appointment (${apptType.label}, ${apptType.priceText}) has been booked on '
          '${_prettyDateTime(slotStartLocal)}.\n\n',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
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

      if (_isCorporateDay)
        'corporate': {
          'corporateOnly': true,
          'corporateCodeUsed': _corporateCode.trim(),
          if (_locationLabel.trim().isNotEmpty)
            'locationLabel': _locationLabel.trim(),
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

    final okCorp = await _ensureCorporateAccessForSelectedDay();
    if (!mounted || !okCorp) return;

    final apptType = await _askAppointmentType();
    if (!mounted || apptType == null) return;

    final patient = await _askPatientDetailsPopup(apptType.kind);
    if (!mounted || patient == null) return;

    final confirmed = await _confirmBookingPopup(
      slotStartLocal: slot.startLocal,
      apptType: apptType,
    );
    if (!mounted || !confirmed) return;

    try {
      final reqRef = await _createBookingRequest(
        startLocal: slot.startLocal,
        appt: apptType,
        patient: patient,
      );

      // show spinner without awaiting
      unawaited(_showSubmittingDialog());

      try {
        final data = await _waitForBookingRequestResult(reqRef);
        if (!mounted) return;

        final status = (data['status'] ?? '').toString();

        if (status == 'rejected') {
          final reason =
              (data['rejectionReason'] ?? 'Booking rejected.').toString();

          _closeDialogIfOpen();
          if (!mounted) return;

          await showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Booking not available'),
              content: Text(reason),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          return;
        }
      } catch (e) {
        _closeDialogIfOpen();
        rethrow;
      } finally {
        _closeDialogIfOpen();
      }

      if (!mounted) return;
      await _bookingConfirmedPopup(
        slotStartLocal: slot.startLocal,
        apptType: apptType,
      );

      await _askPreassessmentNextStep(
        patient,
        bookingRequestId: reqRef.id,
      );

      await _refreshAll();
    } catch (e) {
      _closeDialogIfOpen();
      if (!mounted) return;

      final msg = e.toString().replaceFirst('Exception: ', '').trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg.isEmpty ? 'Booking failed.' : msg)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cid = widget.clinicId.trim();
    if (cid.isEmpty) {
      return Scaffold(
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
        appBar: AppBar(title: const Text('Book an appointment')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final showCorporateBanner = _isCorporateDay && !_loadingDayMeta;

    final now = DateTime.now();
    final leadCutoff = now.add(_minLeadTime);

    final selectedPractitionerLabel = (() {
      final id = (_selectedPractitionerId ?? '').trim();
      if (id.isEmpty) return '';
      final match =
          _practitioners.where((p) => p.id == id).toList(growable: false);
      if (match.isEmpty) return _shortId(id);
      return match.first.displayName;
    })();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Book an appointment'),
        actions: [
          _PublicContactActions(
            clinicId: cid,
            debugWhenEmpty: kDebugMode,
          ),
          IconButton(
            tooltip: 'Home',
            icon: const Icon(Icons.home_outlined),
            onPressed: () {
              Navigator.of(context).pushNamedAndRemoveUntil(
                AppRoutes.publicHome,
                (r) => false,
                arguments: {'clinicId': widget.clinicId},
              );
            },
          ),
          if (_corporateCode.trim().isNotEmpty)
            IconButton(
              tooltip: 'Clear corporate code',
              icon: const Icon(Icons.filter_alt_off),
              onPressed: _clearCorporateCode,
            ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => _refreshAll(),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),

          // Date picker
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: _pickDay,
              icon: const Icon(Icons.calendar_today),
              label: Text('Date: ${_prettyDate(_selectedDay)}'),
            ),
          ),

          // Practitioner selector
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Clinician',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: (_selectedPractitionerId ?? '').trim().isEmpty
                      ? null
                      : _selectedPractitionerId,
                  hint: const Text('Select a clinician'),
                  items: _practitioners
                      .map(
                        (p) => DropdownMenuItem<String>(
                          value: p.id,
                          child: Text(p.displayName),
                        ),
                      )
                      .toList(),
                  onChanged:
                      _loadingPractitioners ? null : _onPractitionerChanged,
                ),
              ),
            ),
          ),

          // Helper text (lead time)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(
              'Clinician: ${selectedPractitionerLabel.isEmpty ? '—' : selectedPractitionerLabel}\n'
              'Showing hourly start times only. '
              '${_dateOnly(_selectedDay) == _dateOnly(now) ? 'Earliest bookable: ${_prettyTime(leadCutoff)}' : 'Book at least ${_minLeadTime.inMinutes} mins in advance.'}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          if (_loadingPractitioners)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (_practitionersError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(
                _practitionersError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),

          if (_loadingDayMeta)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (_dayMetaError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(
                _dayMetaError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),

          if (showCorporateBanner)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orangeAccent),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.business, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          _corpDisplayName?.isNotEmpty == true
                              ? _corpDisplayName!
                              : 'Corporate day',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        if (_corpMode == CorporateMode.codeUnlock)
                          OutlinedButton(
                            onPressed: _promptForCorporateCode,
                            child: Text(
                              _corporateCode.trim().isEmpty
                                  ? 'Enter code'
                                  : 'Change code',
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      (_corpMode == CorporateMode.codeUnlock)
                          ? 'This day is reserved for corporate appointments. You need a booking code.'
                          : 'This day is reserved for corporate appointments.',
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (_locationLabel.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Location: ${_locationLabel.trim()}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

          const SizedBox(height: 8),

          Expanded(
            child: _loadingSlots
                ? const Center(child: CircularProgressIndicator())
                : (_slotsError != null)
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline, size: 40),
                              const SizedBox(height: 10),
                              Text(_slotsError!, textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: _refreshAll,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Try again'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : (_slots.isEmpty)
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(18),
                              child: Text(
                                'No available hourly slots for this day.\n\nPlease choose another date.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            itemCount: _slots.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final s = _slots[i];
                              return ListTile(
                                leading: const Icon(Icons.schedule),
                                title: Text(_prettyTime(s.startLocal)),
                                subtitle: Text(_prettyDate(s.startLocal)),
                                trailing: _isCorporateDay
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            color: Colors.orangeAccent,
                                          ),
                                        ),
                                        child: const Text(
                                          'Corporate',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      )
                                    : null,
                                onTap: () => _onTapSlot(s),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
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
