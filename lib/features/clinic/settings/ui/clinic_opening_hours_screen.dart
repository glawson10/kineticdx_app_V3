import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/app_routes.dart';
import '../../../../data/repositories/clinic_repository.dart';
import '../../../../data/repositories/locations_repository.dart';
import '../../../../models/clinic_location.dart';

class ClinicOpeningHoursScreen extends StatefulWidget {
  const ClinicOpeningHoursScreen({super.key, required this.clinicId});

  final String clinicId;

  @override
  State<ClinicOpeningHoursScreen> createState() =>
      _ClinicOpeningHoursScreenState();
}

class _ClinicOpeningHoursScreenState extends State<ClinicOpeningHoursScreen> {
  bool _dirty = false;
  bool _saving = false;

  static const _days = <String>[
    'mon',
    'tue',
    'wed',
    'thu',
    'fri',
    'sat',
    'sun'
  ];

  static const _labels = <String, String>{
    'mon': 'Monday',
    'tue': 'Tuesday',
    'wed': 'Wednesday',
    'thu': 'Thursday',
    'fri': 'Friday',
    'sat': 'Saturday',
    'sun': 'Sunday',
  };

  // Local editable model:
  // day -> list of {start,end}
  final Map<String, List<Map<String, String>>> _weekly = {
    for (final d in _days) d: <Map<String, String>>[],
  };

  String _two(int v) => v.toString().padLeft(2, '0');

  String _fmtTimeOfDay(TimeOfDay t) => '${_two(t.hour)}:${_two(t.minute)}';

  int _hmToMin(String hm) {
    final m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(hm.trim());
    if (m == null) return -1;
    final hh = int.tryParse(m.group(1)!) ?? -1;
    final mm = int.tryParse(m.group(2)!) ?? -1;
    if (hh < 0 || hh > 23 || mm < 0 || mm > 59) return -1;
    return hh * 60 + mm;
  }

  bool _intervalsValid(List<Map<String, String>> list) {
    // sort check + overlap check
    final intervals = list
        .map((it) => Map<String, String>.from(it))
        .where((it) => it['start'] != null && it['end'] != null)
        .toList();

    for (final it in intervals) {
      final a = _hmToMin(it['start'] ?? '');
      final b = _hmToMin(it['end'] ?? '');
      if (a < 0 || b < 0) return false;
      if (b <= a) return false;
    }

    intervals.sort((x, y) => _hmToMin(x['start']!) - _hmToMin(y['start']!));

    for (int i = 1; i < intervals.length; i++) {
      final prev = intervals[i - 1];
      final cur = intervals[i];
      if (_hmToMin(cur['start']!) < _hmToMin(prev['end']!)) return false;
    }

    return true;
  }

  void _loadFromDoc(Map<String, dynamic> data) {
    // Prefer weeklyHours; fallback to legacy openingHours.days shape
    final rawWeekly = (data['weeklyHours'] is Map)
        ? Map<String, dynamic>.from(data['weeklyHours'] as Map)
        : <String, dynamic>{};

    bool loadedWeekly = false;

    for (final d in _days) {
      final v = rawWeekly[d];
      if (v is List) {
        loadedWeekly = true;
        _weekly[d] = v
            .whereType<Map>()
            .map((m) => {
                  'start': (m['start'] ?? '').toString(),
                  'end': (m['end'] ?? '').toString(),
                })
            .where((it) => it['start']!.isNotEmpty && it['end']!.isNotEmpty)
            .toList();
      } else {
        _weekly[d] = <Map<String, String>>[];
      }
    }

    if (loadedWeekly) return;

    // Legacy: openingHours.days (your dump shows this shape exists)
    final openingHours = (data['openingHours'] is Map)
        ? Map<String, dynamic>.from(data['openingHours'] as Map)
        : <String, dynamic>{};

    final daysArr = openingHours['days'];
    if (daysArr is List) {
      for (final row in daysArr) {
        if (row is! Map) continue;
        final day = (row['day'] ?? '').toString().trim().toLowerCase();
        if (!_days.contains(day)) continue;

        final open = row['open'] == true;
        final start = (row['start'] ?? '').toString();
        final end = (row['end'] ?? '').toString();

        _weekly[day] = (open && start.isNotEmpty && end.isNotEmpty)
            ? [
                {'start': start, 'end': end}
              ]
            : <Map<String, String>>[];
      }
    }
  }

  Future<TimeOfDay?> _pickTime(TimeOfDay initial) {
    return showTimePicker(context: context, initialTime: initial);
  }

  Future<void> _editInterval({
    required String day,
    required int index,
  }) async {
    final it = _weekly[day]![index];
    final startStr = it['start'] ?? '08:00';
    final endStr = it['end'] ?? '17:00';

    TimeOfDay start = TimeOfDay(
      hour: int.tryParse(startStr.split(':').first) ?? 8,
      minute: int.tryParse(startStr.split(':').last) ?? 0,
    );
    TimeOfDay end = TimeOfDay(
      hour: int.tryParse(endStr.split(':').first) ?? 17,
      minute: int.tryParse(endStr.split(':').last) ?? 0,
    );

    final pickedStart = await _pickTime(start);
    if (pickedStart == null) return;

    final pickedEnd = await _pickTime(end);
    if (pickedEnd == null) return;

    setState(() {
      _weekly[day]![index] = {
        'start': _fmtTimeOfDay(pickedStart),
        'end': _fmtTimeOfDay(pickedEnd),
      };
      _dirty = true;
    });
  }

  void _addInterval(String day) {
    setState(() {
      _weekly[day]!.add({'start': '08:00', 'end': '17:00'});
      _dirty = true;
    });
  }

  void _removeInterval(String day, int index) {
    setState(() {
      _weekly[day]!.removeAt(index);
      _dirty = true;
    });
  }

  bool get _allValid {
    for (final d in _days) {
      if (!_intervalsValid(_weekly[d]!)) return false;
    }
    return true;
  }

  Map<String, dynamic> _toWeeklyHoursPayload() {
    return {
      for (final d in _days)
        d: _weekly[d]!
            .map((it) => {'start': it['start'], 'end': it['end']})
            .toList(),
    };
  }

  Future<void> _save(ClinicRepository repo) async {
    if (_saving) return;

    if (!_allValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Fix invalid / overlapping time ranges first.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await repo.updateClinicWeeklyHours(
        clinicId: widget.clinicId,
        weeklyHours: _toWeeklyHoursPayload(),
      );

      if (!mounted) return;
      setState(() => _dirty = false);

      try {
        await repo.rebuildPublicBookingConfig(widget.clinicId);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Opening hours saved; public booking sync may lag.'),
            ),
          );
          return;
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Opening hours saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Format intervals for display, e.g. "9:00 – 17:00" or "9:00–12:00, 13:00–17:00".
  String _formatIntervals(List<Map<String, String>> intervals) {
    if (intervals.isEmpty) return '';
    return intervals
        .map((it) => '${it['start']} – ${it['end']}')
        .join(', ');
  }

  Future<void> _openDayEditor(String day) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _DayEditDialog(
        dayLabel: _labels[day] ?? day,
        intervals: List<Map<String, String>>.from(
          _weekly[day]!.map((e) => Map<String, String>.from(e))),
        onAdd: () {
          _addInterval(day);
          Navigator.of(dialogContext).pop();
          _openDayEditor(day);
        },
        onEdit: (i) async {
          Navigator.of(dialogContext).pop();
          await _editInterval(day: day, index: i);
          if (!mounted) return;
          _openDayEditor(day);
        },
        onRemove: (i) {
          _removeInterval(day, i);
          Navigator.of(dialogContext).pop();
          _openDayEditor(day);
        },
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ClinicRepository>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: repo.watchPublicBookingSettings(widget.clinicId),
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Clinic opening hours')),
            body: Center(child: Text('Error: ${snap.error}')),
          );
        }
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snap.data!.data() ?? <String, dynamic>{};

        if (!_dirty && !_saving) {
          _loadFromDoc(data);
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Clinic opening hours'),
            actions: [
              TextButton.icon(
                onPressed: (!_dirty || _saving) ? null : () => _save(repo),
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text('Save'),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Defines the clinic\'s maximum operating hours. Locations and practitioner availability can further restrict bookable times. Multiple time windows per day are supported.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              Card(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        color: colorScheme.surfaceContainerHighest,
                        child: Text(
                          'Weekly hours',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      for (final d in _days) ...[
                        _WeekRow(
                          dayLabel: _labels[d]!,
                          isOpen: _weekly[d]!.isNotEmpty,
                          intervalsText: _formatIntervals(_weekly[d]!),
                          valid: _intervalsValid(_weekly[d]!),
                          onEdit: () => _openDayEditor(d),
                        ),
                        if (d != _days.last)
                          Divider(
                            height: 1,
                            indent: 16,
                            endIndent: 16,
                            color: colorScheme.outlineVariant,
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              if (!_allValid)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'One or more days have invalid or overlapping intervals.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 28),
              _LocationsSummaryWidget(clinicId: widget.clinicId),
            ],
          ),
        );
      },
    );
  }
}

/// Single row in the week-at-a-glance table: day | status | times | Edit.
class _WeekRow extends StatelessWidget {
  const _WeekRow({
    required this.dayLabel,
    required this.isOpen,
    required this.intervalsText,
    required this.valid,
    required this.onEdit,
  });

  final String dayLabel;
  final bool isOpen;
  final String intervalsText;
  final bool valid;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 100,
                child: Text(
                  dayLabel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (!valid)
                Icon(
                  Icons.error_outline,
                  size: 18,
                  color: colorScheme.error,
                ),
              if (!valid) const SizedBox(width: 8),
              Expanded(
                child: isOpen
                    ? Text(
                        intervalsText,
                        style: theme.textTheme.bodyMedium,
                      )
                    : Text(
                        'Closed',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
              TextButton(
                onPressed: onEdit,
                child: const Text('Edit'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog to edit a single day's intervals (add/remove/edit times).
class _DayEditDialog extends StatelessWidget {
  const _DayEditDialog({
    required this.dayLabel,
    required this.intervals,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
  });

  final String dayLabel;
  final List<Map<String, String>> intervals;
  final VoidCallback onAdd;
  final void Function(int index) onEdit;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('$dayLabel – opening hours'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (intervals.isEmpty)
              Text(
                'Closed',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              ...List.generate(intervals.length, (i) {
                final it = intervals[i];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${it['start']} – ${it['end']}'),
                  leading: const Icon(Icons.schedule_outlined, size: 20),
                  onTap: () => onEdit(i),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => onRemove(i),
                  ),
                );
              }),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Add time window'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

/// Locations section: list of locations + link to Manage locations (Settings).
class _LocationsSummaryWidget extends StatelessWidget {
  const _LocationsSummaryWidget({required this.clinicId});

  final String clinicId;

  void _openManageLocations(BuildContext context) {
    Navigator.of(context).pushNamed(
      AppRoutes.settingsSection(clinicId, AppRoutes.settingsLocations),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final repo = context.read<LocationsRepository>();

    return StreamBuilder<List<ClinicLocation>>(
      stream: repo.watchLocations(clinicId),
      builder: (context, snap) {
        final locations = snap.data ?? [];
        final activeLocations =
            locations.where((l) => l.active).toList();

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Locations',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Used as the outer operating boundary for all booking. Locations and practitioner schedules may be more restrictive. Set per-location hours in Locations → select a location → Opening hours.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (activeLocations.length > 1) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${activeLocations.length} locations. Each can have its own opening hours.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (activeLocations.isEmpty)
                  Text(
                    'No locations set. Add locations in Settings → Locations to use them in booking.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  ...activeLocations.map(
                    (loc) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Icon(
                            Icons.place_outlined,
                            size: 16,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  loc.name,
                                  style: theme.textTheme.bodyMedium,
                                ),
                                if (loc.addressText.trim().isNotEmpty)
                                  Text(
                                    loc.addressText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => _openManageLocations(context),
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label: const Text('Manage locations'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
