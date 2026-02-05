import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class PublicBookingWeekendHoursScreen extends StatefulWidget {
  final String clinicId;

  const PublicBookingWeekendHoursScreen({
    super.key,
    required this.clinicId,
  });

  @override
  State<PublicBookingWeekendHoursScreen> createState() =>
      _PublicBookingWeekendHoursScreenState();
}

class _PublicBookingWeekendHoursScreenState
    extends State<PublicBookingWeekendHoursScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool _satOpen = false;
  bool _sunOpen = false;

  TimeOfDay _satStart = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _satEnd = const TimeOfDay(hour: 13, minute: 0);

  TimeOfDay _sunStart = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _sunEnd = const TimeOfDay(hour: 13, minute: 0);

  DocumentReference<Map<String, dynamic>> get _docRef =>
      FirebaseFirestore.instance
          .collection('clinics')
          .doc(widget.clinicId)
          .collection('settings')
          .doc('publicBooking');

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _two(int n) => n.toString().padLeft(2, '0');
  String _toHm(TimeOfDay t) => '${_two(t.hour)}:${_two(t.minute)}';

  int _toMinutes(TimeOfDay t) => (t.hour * 60) + t.minute;

  TimeOfDay _fromHm(String hm, TimeOfDay fallback) {
    final m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(hm.trim());
    if (m == null) return fallback;
    final h = int.tryParse(m.group(1) ?? '');
    final min = int.tryParse(m.group(2) ?? '');
    if (h == null || min == null) return fallback;
    if (h < 0 || h > 23 || min < 0 || min > 59) return fallback;
    return TimeOfDay(hour: h, minute: min);
  }

  List<Map<String, dynamic>> _readDayIntervals(dynamic v) {
    if (v is List) {
      return v
          .whereType<Map>()
          .map((x) => Map<String, dynamic>.from(x))
          .toList();
    }
    return const [];
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final snap = await _docRef.get();
      final data = snap.data() ?? {};

      final weeklyHours = (data['weeklyHours'] is Map)
          ? Map<String, dynamic>.from(data['weeklyHours'] as Map)
          : <String, dynamic>{};

      final satIntervals = _readDayIntervals(weeklyHours['sat']);
      final sunIntervals = _readDayIntervals(weeklyHours['sun']);

      // Saturday
      if (satIntervals.isNotEmpty) {
        _satOpen = true;
        final first = satIntervals.first;
        _satStart = _fromHm((first['start'] ?? '').toString(), _satStart);
        _satEnd = _fromHm((first['end'] ?? '').toString(), _satEnd);
      } else {
        _satOpen = false;
      }

      // Sunday
      if (sunIntervals.isNotEmpty) {
        _sunOpen = true;
        final first = sunIntervals.first;
        _sunStart = _fromHm((first['start'] ?? '').toString(), _sunStart);
        _sunEnd = _fromHm((first['end'] ?? '').toString(), _sunEnd);
      } else {
        _sunOpen = false;
      }

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load publicBooking settings: $e';
      });
    }
  }

  Future<TimeOfDay?> _pickTime(TimeOfDay initial) {
    return showTimePicker(
      context: context,
      initialTime: initial,
      helpText: 'Select time',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }

  Map<String, dynamic> _buildWeeklyHoursPatch() {
    // We only patch sat/sun (leave everything else untouched).
    final patch = <String, dynamic>{};

    patch['weeklyHours.sat'] = _satOpen
        ? [
            {'start': _toHm(_satStart), 'end': _toHm(_satEnd)}
          ]
        : [];

    patch['weeklyHours.sun'] = _sunOpen
        ? [
            {'start': _toHm(_sunStart), 'end': _toHm(_sunEnd)}
          ]
        : [];

    return patch;
  }

  String? _validate() {
    if (_satOpen && _toMinutes(_satEnd) <= _toMinutes(_satStart)) {
      return 'Saturday end time must be after start time.';
    }
    if (_sunOpen && _toMinutes(_sunEnd) <= _toMinutes(_sunStart)) {
      return 'Sunday end time must be after start time.';
    }
    return null;
  }

  Future<void> _save() async {
    final v = _validate();
    if (v != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(v)));
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      // Merge patch into existing doc
      final patch = _buildWeeklyHoursPatch();
      await _docRef.set(patch, SetOptions(merge: true));

      if (!mounted) return;
      setState(() => _saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Weekend hours saved')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Save failed: $e';
      });
    }
  }

  Widget _dayCard({
    required String title,
    required bool open,
    required ValueChanged<bool> onToggle,
    required TimeOfDay start,
    required TimeOfDay end,
    required VoidCallback onPickStart,
    required VoidCallback onPickEnd,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                Switch(
                  value: open,
                  onChanged: _saving ? null : onToggle,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (open) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : onPickStart,
                      child: Text('Start: ${_toHm(start)}'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : onPickEnd,
                      child: Text('End: ${_toHm(end)}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Bookings must fit fully inside these hours.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else ...[
              Text(
                'Closed',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey[700]),
              ),
            ]
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cid = widget.clinicId.trim();
    if (cid.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Missing clinicId')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekend opening hours'),
        actions: [
          TextButton(
            onPressed: (_loading || _saving) ? null : _save,
            child: _saving ? const Text('Saving…') : const Text('Save'),
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (_error != null) ...[
                  Card(
                    color: Colors.red.withValues(alpha: 0.07),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_error!),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                _dayCard(
                  title: 'Saturday',
                  open: _satOpen,
                  onToggle: (v) => setState(() => _satOpen = v),
                  start: _satStart,
                  end: _satEnd,
                  onPickStart: () async {
                    final t = await _pickTime(_satStart);
                    if (!mounted || t == null) return;
                    setState(() => _satStart = t);
                  },
                  onPickEnd: () async {
                    final t = await _pickTime(_satEnd);
                    if (!mounted || t == null) return;
                    setState(() => _satEnd = t);
                  },
                ),
                _dayCard(
                  title: 'Sunday',
                  open: _sunOpen,
                  onToggle: (v) => setState(() => _sunOpen = v),
                  start: _sunStart,
                  end: _sunEnd,
                  onPickStart: () async {
                    final t = await _pickTime(_sunStart);
                    if (!mounted || t == null) return;
                    setState(() => _sunStart = t);
                  },
                  onPickEnd: () async {
                    final t = await _pickTime(_sunEnd);
                    if (!mounted || t == null) return;
                    setState(() => _sunEnd = t);
                  },
                ),
                const SizedBox(height: 10),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'This updates clinics/{clinicId}/settings/publicBooking.weeklyHours.sat/sun.\n'
                      'Your public slot listing + booking validation will reflect it immediately.',
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
