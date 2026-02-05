import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // ✅ for mapEquals

class WeeklyHoursEditor extends StatefulWidget {
  const WeeklyHoursEditor({
    super.key,
    required this.initialWeekly,
    required this.onChanged,
    this.readOnly = false,
  });

  /// Map dayKey -> list of {start,end}
  final Map<String, List<Map<String, String>>> initialWeekly;
  final void Function(Map<String, List<Map<String, String>>> weekly) onChanged;
  final bool readOnly;

  @override
  State<WeeklyHoursEditor> createState() => _WeeklyHoursEditorState();
}

class _WeeklyHoursEditorState extends State<WeeklyHoursEditor> {
  static const _days = <String>['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

  static const _labels = <String, String>{
    'mon': 'Mon',
    'tue': 'Tue',
    'wed': 'Wed',
    'thu': 'Thu',
    'fri': 'Fri',
    'sat': 'Sat',
    'sun': 'Sun',
  };

  late Map<String, List<Map<String, String>>> _weekly;

  // ─────────────────────────────
  // Init
  // ─────────────────────────────
  @override
  void initState() {
    super.initState();
    _syncFromWidget();
  }

  // ✅ CRITICAL FIX:
  // Resync local state when Firestore stream updates initialWeekly
  @override
  void didUpdateWidget(covariant WeeklyHoursEditor oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!mapEquals(oldWidget.initialWeekly, widget.initialWeekly)) {
      _syncFromWidget();
    }
  }

  void _syncFromWidget() {
    setState(() {
      _weekly = {
        for (final d in _days)
          d: (widget.initialWeekly[d] ?? const <Map<String, String>>[])
              .map(
                (e) => {
                  'start': (e['start'] ?? ''),
                  'end': (e['end'] ?? ''),
                },
              )
              .toList(),
      };
    });
  }

  // ─────────────────────────────
  // Helpers
  // ─────────────────────────────
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
        .where((it) =>
            (it['start'] ?? '').isNotEmpty &&
            (it['end'] ?? '').isNotEmpty)
        .toList();

    for (final it in intervals) {
      final a = _hmToMin(it['start'] ?? '');
      final b = _hmToMin(it['end'] ?? '');
      if (a < 0 || b < 0) return false;
      if (b <= a) return false;
    }

    intervals.sort(
      (x, y) => _hmToMin(x['start']!) - _hmToMin(y['start']!),
    );

    for (int i = 1; i < intervals.length; i++) {
      final prev = intervals[i - 1];
      final cur = intervals[i];
      if (_hmToMin(cur['start']!) < _hmToMin(prev['end']!)) return false;
    }

    return true;
  }

  bool get allValid => _days.every((d) => _intervalsValid(_weekly[d]!));

  Future<TimeOfDay?> _pickTime(TimeOfDay initial) {
    return showTimePicker(context: context, initialTime: initial);
  }

  // ─────────────────────────────
  // Mutations
  // ─────────────────────────────
  Future<void> _editInterval({
    required String day,
    required int index,
  }) async {
    if (widget.readOnly) return;

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
    });

    widget.onChanged(_weekly);
  }

  void _addInterval(String day) {
    if (widget.readOnly) return;

    setState(() {
      _weekly[day]!.add({'start': '08:00', 'end': '17:00'});
    });

    widget.onChanged(_weekly);
  }

  void _removeInterval(String day, int index) {
    if (widget.readOnly) return;

    setState(() {
      _weekly[day]!.removeAt(index);
    });

    widget.onChanged(_weekly);
  }

  // ─────────────────────────────
  // UI
  // ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final d in _days) ...[
          _DayCard(
            label: _labels[d] ?? d,
            intervals: _weekly[d]!,
            valid: _intervalsValid(_weekly[d]!),
            readOnly: widget.readOnly,
            onAdd: () => _addInterval(d),
            onEdit: (i) => _editInterval(day: d, index: i),
            onRemove: (i) => _removeInterval(d, i),
          ),
          const SizedBox(height: 10),
        ],
        if (!allValid)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'One or more days have invalid or overlapping intervals.',
              style: TextStyle(color: Colors.red),
            ),
          ),
      ],
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.label,
    required this.intervals,
    required this.valid,
    required this.readOnly,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
  });

  final String label;
  final List<Map<String, String>> intervals;
  final bool valid;
  final bool readOnly;

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
                  onPressed: readOnly ? null : onAdd,
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
                        '${intervals[i]['start']} → ${intervals[i]['end']}',
                      ),
                      leading: const Icon(Icons.schedule),
                      onTap: readOnly ? null : () => onEdit(i),
                      trailing: IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: readOnly ? null : () => onRemove(i),
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
