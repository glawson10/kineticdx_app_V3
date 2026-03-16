// Location opening hours. Same pattern as clinic opening hours; hours must be within clinic hours.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/locations_repository.dart';

class LocationOpeningHoursScreen extends StatefulWidget {
  const LocationOpeningHoursScreen({
    super.key,
    required this.clinicId,
    required this.locationId,
    required this.locationName,
    required this.initialWeeklyHours,
  });

  final String clinicId;
  final String locationId;
  final String locationName;
  /// Day key -> list of { start, end }. Use empty lists for closed.
  final Map<String, List<Map<String, String>>> initialWeeklyHours;

  @override
  State<LocationOpeningHoursScreen> createState() =>
      _LocationOpeningHoursScreenState();
}

class _LocationOpeningHoursScreenState extends State<LocationOpeningHoursScreen> {
  bool _dirty = false;
  bool _saving = false;

  static const _days = <String>[
    'mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'
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

  final Map<String, List<Map<String, String>>> _weekly = {
    for (final d in _days) d: <Map<String, String>>[],
  };

  bool _loaded = false;

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

  void _loadInitial() {
    if (_loaded) return;
    _loaded = true;
    for (final d in _days) {
      final v = widget.initialWeeklyHours[d];
      if (v != null && v.isNotEmpty) {
        _weekly[d] = v
            .map((m) => {
                  'start': (m['start'] ?? '').toString(),
                  'end': (m['end'] ?? '').toString(),
                })
            .where((it) => it['start']!.isNotEmpty && it['end']!.isNotEmpty)
            .toList();
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

  Map<String, List<Map<String, String>>> _toPayload() {
    return {
      for (final d in _days)
        d: _weekly[d]!
            .map((it) => {
                  'start': it['start'] ?? '',
                  'end': it['end'] ?? '',
                })
            .toList(),
    };
  }

  Future<void> _save(LocationsRepository repo) async {
    if (_saving) return;
    if (!_allValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fix invalid or overlapping time ranges first.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await repo.updateLocationWeeklyHours(
        widget.clinicId,
        widget.locationId,
        _toPayload(),
      );
      if (!mounted) return;
      setState(() => _dirty = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location opening hours saved')),
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
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  Widget build(BuildContext context) {
    _loadInitial();
    final repo = context.read<LocationsRepository>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.locationName} – Opening hours'),
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
            'Defines when this location can accept bookings within clinic opening hours. Leave a day empty to mark it closed.',
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
        ],
      ),
    );
  }
}

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
                Icon(Icons.error_outline, size: 18, color: colorScheme.error),
              if (!valid) const SizedBox(width: 8),
              Expanded(
                child: isOpen
                    ? Text(intervalsText, style: theme.textTheme.bodyMedium)
                    : Text(
                        'Closed',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
              TextButton(onPressed: onEdit, child: const Text('Edit')),
            ],
          ),
        ),
      ),
    );
  }
}

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
