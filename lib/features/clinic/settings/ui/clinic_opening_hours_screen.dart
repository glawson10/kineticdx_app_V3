import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/clinic_repository.dart';

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
    'mon': 'Mon',
    'tue': 'Tue',
    'wed': 'Wed',
    'thu': 'Thu',
    'fri': 'Fri',
    'sat': 'Sat',
    'sun': 'Sun',
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
        // meta optional – not editing in this scaffold:
        // weeklyHoursMeta: ...
      );

      if (!mounted) return;
      setState(() => _dirty = false);

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

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ClinicRepository>();

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

        // Load once when not dirty/saving
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
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Set opening hours for each day. Multiple windows per day are supported.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              for (final d in _days) ...[
                _DayCard(
                  label: _labels[d] ?? d,
                  intervals: _weekly[d]!,
                  valid: _intervalsValid(_weekly[d]!),
                  onAdd: () => _addInterval(d),
                  onEdit: (i) => _editInterval(day: d, index: i),
                  onRemove: (i) => _removeInterval(d, i),
                ),
                const SizedBox(height: 10),
              ],
              if (!_allValid)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'One or more days have invalid or overlapping intervals.',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.label,
    required this.intervals,
    required this.valid,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
  });

  final String label;
  final List<Map<String, String>> intervals;
  final bool valid;

  final VoidCallback onAdd;
  final void Function(int index) onEdit;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Icon(
                  Icons.circle,
                  size: 10,
                  color: valid ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (intervals.isEmpty)
              const Text('Closed', style: TextStyle(color: Colors.black54))
            else
              Column(
                children: [
                  for (int i = 0; i < intervals.length; i++)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                          '${intervals[i]['start']} → ${intervals[i]['end']}'),
                      leading: const Icon(Icons.schedule),
                      onTap: () => onEdit(i),
                      trailing: IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => onRemove(i),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
