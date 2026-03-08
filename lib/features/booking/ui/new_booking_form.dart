// lib/features/booking/ui/new_booking_form.dart
//
// Single cohesive booking form: Location → Type & duration → Clinician →
// Date & time → Patient → Confirm. Replaces the multi-dialog create flow.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/appointments_repository.dart'
    show AppointmentsRepository, ClinicClosureConflictException, PractitionerOverlapException;
import '../../../data/repositories/appointment_types_repository.dart';
import '../../../data/repositories/locations_repository.dart';
import '../../../data/repositories/staff_repository.dart';
import '../../../models/appointment_type.dart';
import '../../../models/clinic_location.dart';
import '../../../models/practitioner_booking_meta.dart';
import '../../../models/waitlist_entry.dart';

/// Result of picking or creating a patient (returned by callbacks from calendar screen).
class BookingPatientResult {
  final String id;
  final String displayLabel;
  const BookingPatientResult({required this.id, required this.displayLabel});
}

enum _BookingFormAction { newPatient, followUp, adminBlock }

class NewBookingForm extends StatefulWidget {
  final String clinicId;
  final DateTime slotStart;
  final int defaultSlotMinutes;
  final int adminGridMinutes;
  final String? initialLocationId;
  final WaitlistEntry? waitlistEntry;
  final Future<BookingPatientResult?> Function(BuildContext context) onFindPatient;
  final Future<BookingPatientResult?> Function(BuildContext context) onCreatePatient;

  const NewBookingForm({
    super.key,
    required this.clinicId,
    required this.slotStart,
    required this.defaultSlotMinutes,
    required this.adminGridMinutes,
    this.initialLocationId,
    this.waitlistEntry,
    required this.onFindPatient,
    required this.onCreatePatient,
  });

  static Future<bool?> open(
    BuildContext context, {
    required String clinicId,
    required DateTime slotStart,
    required int defaultSlotMinutes,
    required int adminGridMinutes,
    String? initialLocationId,
    WaitlistEntry? waitlistEntry,
    required Future<BookingPatientResult?> Function(BuildContext context) onFindPatient,
    required Future<BookingPatientResult?> Function(BuildContext context) onCreatePatient,
  }) {
    return Navigator.push<bool?>(
      context,
      MaterialPageRoute<bool?>(
        builder: (_) => NewBookingForm(
          clinicId: clinicId,
          slotStart: slotStart,
          defaultSlotMinutes: defaultSlotMinutes,
          adminGridMinutes: adminGridMinutes,
          initialLocationId: initialLocationId,
          waitlistEntry: waitlistEntry,
          onFindPatient: onFindPatient,
          onCreatePatient: onCreatePatient,
        ),
      ),
    );
  }

  @override
  State<NewBookingForm> createState() => _NewBookingFormState();
}

class _NewBookingFormState extends State<NewBookingForm> {
  _BookingFormAction _action = _BookingFormAction.followUp;
  String? _locationId;
  String? _serviceId;
  int _durationMinutes = 30;
  String? _practitionerId;
  late DateTime _start;
  String? _patientId;
  String _patientDisplayLabel = '';

  @override
  void initState() {
    super.initState();
    _start = widget.slotStart;
    _durationMinutes = widget.defaultSlotMinutes;
    final loc = widget.initialLocationId?.trim();
    _locationId = (loc == null || loc.isEmpty) ? null : loc;
    if (widget.waitlistEntry != null) {
      _patientId = widget.waitlistEntry!.patientId ?? '';
      _patientDisplayLabel = widget.waitlistEntry!.displayLabel;
    }
  }

  DateTime get _end => _start.add(Duration(minutes: _durationMinutes));

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

  Future<void> _submit() async {
    final apptRepo = context.read<AppointmentsRepository>();
    final clinicId = widget.clinicId;

    if (_action == _BookingFormAction.adminBlock) {
      try {
        await apptRepo.createAppointment(
          clinicId: clinicId,
          kind: 'admin',
          start: _start,
          end: _end,
          locationId: _locationId,
        );
        if (!mounted) return;
        Navigator.pop(context, true);
      } on ClinicClosureConflictException {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clinic closure conflict.')),
        );
      } on PractitionerOverlapException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      } on FirebaseFunctionsException catch (e) {
        if (!mounted) return;
        final msg = _callableErrorMessage(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 5)),
        );
      }
      return;
    }

    if (_patientId == null || _patientId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a patient')),
      );
      return;
    }
    final kind = _action == _BookingFormAction.newPatient ? 'new' : 'followup';
    final serviceId = _serviceId?.trim();
    final practitionerId = _practitionerId?.trim();
    if (serviceId == null || serviceId.isEmpty || practitionerId == null || practitionerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select appointment type and clinician')),
      );
      return;
    }

    try {
      await apptRepo.createAppointment(
        clinicId: clinicId,
        kind: kind,
        patientId: _patientId!,
        serviceId: serviceId,
        practitionerId: practitionerId,
        locationId: _locationId,
        start: _start,
        end: _end,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ClinicClosureConflictException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clinic closure conflict.')),
      );
    } on PractitionerOverlapException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final msg = _callableErrorMessage(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 5)),
      );
    }
  }

  static String _callableErrorMessage(FirebaseFunctionsException e) {
    final message = e.message?.trim();
    if (message != null && message.isNotEmpty) return message;
    final details = e.details;
    if (details is Map && details['original'] != null) {
      return details['original'].toString();
    }
    return 'Request failed (${e.code})';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAdmin = _action == _BookingFormAction.adminBlock;

    return Scaffold(
      appBar: AppBar(
        title: const Text('New booking'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Action
            Text('Booking type', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<_BookingFormAction>(
              segments: const [
                ButtonSegment(value: _BookingFormAction.newPatient, label: Text('New patient'), icon: Icon(Icons.person_add_alt_1)),
                ButtonSegment(value: _BookingFormAction.followUp, label: Text('Follow up'), icon: Icon(Icons.person_search)),
                ButtonSegment(value: _BookingFormAction.adminBlock, label: Text('Admin block'), icon: Icon(Icons.event_busy)),
              ],
              selected: {_action},
              onSelectionChanged: (s) => setState(() => _action = s.first),
            ),
            const SizedBox(height: 24),

            // 2. Location (hidden for admin or show as optional)
            if (!isAdmin) ...[
              Text('Location', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              StreamBuilder<List<ClinicLocation>>(
                stream: context.read<LocationsRepository>().watchLocations(widget.clinicId).map(
                    (list) => list.where((l) => l.active).toList()),
                builder: (context, snap) {
                  final locations = snap.data ?? [];
                  final allowedIds = locations.map((l) => l.id).toSet();
                  final safeValue = (_locationId != null && allowedIds.contains(_locationId))
                      ? _locationId
                      : null;
                  return DropdownButtonFormField<String?>(
                    value: safeValue,
                    decoration: const InputDecoration(
                      hintText: 'No location',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('No location')),
                      for (final loc in locations)
                        DropdownMenuItem<String?>(value: loc.id, child: Text(loc.name)),
                    ],
                    onChanged: (v) => setState(() {
                      _locationId = v;
                      // Clear incompatible downstream selections
                      _serviceId = null;
                      _practitionerId = null;
                    }),
                  );
                },
              ),
              const SizedBox(height: 24),
            ],

            // 3. Appointment type (hidden for admin) — filtered by selected location
            if (!isAdmin) ...[
              Text('Appointment type', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              StreamBuilder<List<AppointmentType>>(
                stream: context.read<AppointmentTypesRepository>().watchActiveTypes(widget.clinicId),
                builder: (context, snap) {
                  var types = snap.data ?? [];
                  // Filter by selected location if set
                  if (_locationId != null && _locationId!.isNotEmpty) {
                    types = types.where((t) {
                      if (t.allowedLocationIds.isEmpty) return true;
                      return t.allowedLocationIds.contains(_locationId);
                    }).toList();
                  }
                  if (types.isEmpty) {
                    return const Text('No active appointment types for this location. Add them in Settings → Scheduling.');
                  }
                  final allowedIds = types.map((t) => t.id).toSet();
                  final safeValue = (_serviceId != null && allowedIds.contains(_serviceId))
                      ? _serviceId
                      : null;
                  return DropdownButtonFormField<String>(
                    value: safeValue,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: [
                      for (final t in types)
                        DropdownMenuItem<String>(
                          value: t.id,
                          child: Text('${t.name} — ${t.durationMinutes} min'),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        final t = types.firstWhere((x) => x.id == v);
                        setState(() {
                          _serviceId = v;
                          _durationMinutes = t.durationMinutes;
                        });
                      }
                    },
                  );
                },
              ),
              const SizedBox(height: 24),
            ],

            // 4. Duration
            Text('Duration (minutes)', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in _buildLengthOptions(
                  adminGridMinutes: widget.adminGridMinutes,
                  include: const {15, 20, 30, 45, 60, 90, 120},
                  maxMinutes: 240,
                ))
                  ChoiceChip(
                    label: Text('$m min'),
                    selected: _durationMinutes == m,
                    onSelected: (_) => setState(() => _durationMinutes = m),
                  ),
              ],
            ),
            const SizedBox(height: 24),

            // 5. Clinician (hidden for admin) — filtered by booking meta, appointment type, and location
            if (!isAdmin) ...[
              Text('Clinician', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              _CompatibleClinicianDropdown(
                clinicId: widget.clinicId,
                selectedServiceId: _serviceId,
                selectedLocationId: _locationId,
                selectedPractitionerId: _practitionerId,
                onChanged: (v) => setState(() => _practitionerId = v),
              ),
              const SizedBox(height: 24),
            ],

            // 6. Date & time
            Text('Date & time', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    leading: const Icon(Icons.calendar_today_outlined),
                    title: Text('${_start.day}/${_start.month}/${_start.year}'),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _start,
                        firstDate: DateTime(_start.year - 1),
                        lastDate: DateTime(_start.year + 2),
                      );
                      if (date != null && mounted) {
                        setState(() => _start = DateTime(
                          date.year, date.month, date.day,
                          _start.hour, _start.minute,
                        ));
                      }
                    },
                  ),
                ),
                Expanded(
                  child: ListTile(
                    leading: const Icon(Icons.access_time_outlined),
                    title: Text(
                      '${_start.hour.toString().padLeft(2, '0')}:${_start.minute.toString().padLeft(2, '0')}'
                      ' – ${_end.hour.toString().padLeft(2, '0')}:${_end.minute.toString().padLeft(2, '0')}',
                    ),
                    onTap: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(hour: _start.hour, minute: _start.minute),
                      );
                      if (time != null && mounted) {
                        setState(() => _start = DateTime(
                          _start.year, _start.month, _start.day,
                          time.hour, time.minute,
                        ));
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 7. Patient (hidden for admin)
            if (!isAdmin) ...[
              Text('Patient', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              if (widget.waitlistEntry != null)
                ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(_patientDisplayLabel.isNotEmpty ? _patientDisplayLabel : 'From waitlist'),
                  subtitle: const Text('Pre-filled from waitlist'),
                )
              else ...[
                ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(_patientDisplayLabel.isEmpty ? 'Select patient' : _patientDisplayLabel),
                  onTap: () async {
                    final mode = await showDialog<String>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Select patient'),
                        content: const Text('Find existing patient or create a new one?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, null),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, 'find'),
                            child: const Text('Find patient'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, 'new'),
                            child: const Text('New patient'),
                          ),
                        ],
                      ),
                    );
                    if (mode == null || !mounted) return;
                    final result = mode == 'find'
                        ? await widget.onFindPatient(context)
                        : await widget.onCreatePatient(context);
                    if (result != null && mounted) {
                      setState(() {
                        _patientId = result.id;
                        _patientDisplayLabel = result.displayLabel;
                      });
                    }
                  },
                ),
              ],
              const SizedBox(height: 24),
            ],

            const SizedBox(height: 32),
            FilledButton(
              onPressed: _submit,
              child: Text(isAdmin ? 'Create admin block' : 'Create booking'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dropdown that filters clinicians by schedule permission and booking metadata
/// (activeForBooking, allowed locations/types). Availability rules (recurring or overrides)
/// do NOT filter this list — they only affect which slots are bookable.
class _CompatibleClinicianDropdown extends StatelessWidget {
  final String clinicId;
  final String? selectedServiceId;
  final String? selectedLocationId;
  final String? selectedPractitionerId;
  final ValueChanged<String?> onChanged;

  const _CompatibleClinicianDropdown({
    required this.clinicId,
    required this.selectedServiceId,
    required this.selectedLocationId,
    required this.selectedPractitionerId,
    required this.onChanged,
  });

  /// Must have Schedule read or Schedule write to appear in the clinician list.
  static bool _hasScheduleAccess(Map<String, dynamic> data) {
    final permsRaw = data['permissions'];
    if (permsRaw is! Map) return false;
    final perms = Map<String, dynamic>.from(permsRaw);
    final write = perms['schedule.write'];
    final read = perms['schedule.read'];
    return write == true ||
        read == true ||
        write?.toString() == 'true' ||
        read?.toString() == 'true';
  }

  static String _label(Map<String, dynamic> memberData, Map<String, dynamic>? metaData) {
    final metaName = (metaData?['displayName'] ?? '').toString().trim();
    if (metaName.isNotEmpty) return metaName;
    final name = (memberData['displayName'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final email = (memberData['invitedEmail'] ?? memberData['email'] ?? '').toString().trim();
    if (email.isNotEmpty) return email;
    return 'Member';
  }

  @override
  Widget build(BuildContext context) {
    final staffRepo = context.read<StaffRepository>();

    return StreamBuilder<List<MemberDocSnapshot>>(
      stream: staffRepo.watchMembershipsWithFallback(clinicId),
      builder: (context, memberSnap) {
        return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
          stream: staffRepo.watchPractitionerBookingMetas(clinicId),
          builder: (context, metaSnap) {
            final members = memberSnap.data ?? [];
            final metas = metaSnap.data ?? [];

            final metaById = <String, Map<String, dynamic>>{};
            for (final m in metas) {
              metaById[m.id] = m.data();
            }

            final eligible = <MemberDocSnapshot>[];
            final fallback = <MemberDocSnapshot>[];
            for (final member in members) {
              final metaData = metaById[member.id];
              final hasScheduleAccess = _hasScheduleAccess(member.data());

              if (metaData != null) {
                final meta = PractitionerBookingMeta.fromMap(member.id, metaData);
                final canShow = hasScheduleAccess || meta.activeForBooking;
                if (canShow) fallback.add(member);
                if (!meta.isEligibleFor(
                  serviceId: selectedServiceId,
                  locationId: selectedLocationId,
                )) continue;
                if (canShow) eligible.add(member);
              } else {
                if (hasScheduleAccess) {
                  fallback.add(member);
                  eligible.add(member);
                }
              }
            }

            final toShow = eligible.isNotEmpty ? eligible : fallback;
            if (toShow.isEmpty) {
              return Text(
                'No clinicians available for this combination. Each clinician needs: '
                '(1) Schedule read or Schedule write permission, '
                '(2) Booking visibility → Active for internal booking ON, '
                '(3) Allowed locations/types that include your selection (or leave empty for all).',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              );
            }

            final allowedIds = toShow.map((d) => d.id).toSet();
            final safeValue = (selectedPractitionerId != null && allowedIds.contains(selectedPractitionerId))
                ? selectedPractitionerId
                : null;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: safeValue,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: [
                    for (final d in toShow)
                      DropdownMenuItem<String>(
                        value: d.id,
                        child: Text(_label(d.data(), metaById[d.id])),
                      ),
                  ],
                  onChanged: onChanged,
                ),
                if (eligible.isEmpty && fallback.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'No clinician matches this location/type; showing all with booking visibility. '
                      'Update Booking visibility if someone is missing.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
