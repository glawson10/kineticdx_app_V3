// lib/staff/screens/practitioner_availability_rule_form_screen.dart
// Add or edit one base recurring availability rule.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/practitioner_availability_repository.dart';
import '../../models/clinic_location.dart';
import '../../models/practitioner_availability.dart';

class PractitionerAvailabilityRuleFormScreen extends StatefulWidget {
  const PractitionerAvailabilityRuleFormScreen({
    super.key,
    required this.clinicId,
    required this.practitionerId,
    required this.locations,
    this.existing,
  });

  final String clinicId;
  final String practitionerId;
  final List<ClinicLocation> locations;
  final PractitionerAvailability? existing;

  @override
  State<PractitionerAvailabilityRuleFormScreen> createState() =>
      _PractitionerAvailabilityRuleFormScreenState();
}

class _PractitionerAvailabilityRuleFormScreenState
    extends State<PractitionerAvailabilityRuleFormScreen> {
  late String _locationId;
  late String _startDate;
  String _endDate = '';
  late String _frequency;
  late int _interval;
  final List<AvailabilityBlock> _blocks = [];
  final _descriptionCtl = TextEditingController();
  bool _active = true;
  bool _saving = false;
  String? _error;

  static String _todayIso() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _locationId = existing.locationId;
      _startDate = existing.startDate;
      _endDate = existing.endDate ?? '';
      _frequency = existing.recurrenceRule.frequency;
      _interval = existing.recurrenceRule.interval;
      _blocks.addAll(existing.blocks);
      _descriptionCtl.text = existing.description ?? '';
      _active = existing.active;
    } else {
      _locationId = widget.locations.isNotEmpty ? widget.locations.first.id : '';
      _startDate = _todayIso();
      _frequency = 'weekly';
      _interval = 1;
    }
  }

  @override
  void dispose() {
    _descriptionCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_locationId.isEmpty) {
      setState(() => _error = 'Please select a location.');
      return;
    }
    if (_blocks.isEmpty && _active) {
      setState(() => _error = 'Add at least one time block when the rule is active.');
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      final repo = context.read<PractitionerAvailabilityRepository>();
      final patch = {
        'locationId': _locationId,
        'startDate': _startDate,
        'endDate': _endDate,
        'recurrenceRule': {'frequency': _frequency, 'interval': _interval},
        'blocks': _blocks.map((b) => b.toJson()).toList(),
        'description': _descriptionCtl.text.trim(),
        'active': _active,
      };
      await repo.upsertAvailability(
        clinicId: widget.clinicId,
        practitionerId: widget.practitionerId,
        availabilityId: widget.existing?.id,
        patch: patch,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved.')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addBlock(int dayOfWeek, String start, String end, {bool bookable = true}) {
    setState(() {
      _blocks.add(AvailabilityBlock(
        dayOfWeek: dayOfWeek,
        startTime: start,
        endTime: end,
        bookableOnline: bookable,
      ));
    });
  }

  void _removeBlock(int index) {
    setState(() => _blocks.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Add availability rule' : 'Edit availability rule'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'When are you normally at this location? Add a break (e.g. lunch) as a separate time block.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _locationId.isEmpty ? null : _locationId,
            decoration: const InputDecoration(labelText: 'Location *'),
            items: widget.locations
                .map((l) => DropdownMenuItem(
                      value: l.id,
                      child: Text(l.name.isNotEmpty ? l.name : l.id),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _locationId = v ?? ''),
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: _startDate,
            decoration: const InputDecoration(
              labelText: 'Valid from *',
              hintText: 'YYYY-MM-DD',
            ),
            onChanged: (v) => setState(() => _startDate = v.trim()),
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: _endDate,
            decoration: const InputDecoration(
              labelText: 'Valid to (optional)',
              hintText: 'YYYY-MM-DD or leave empty',
            ),
            onChanged: (v) => setState(() => _endDate = v.trim()),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _frequency,
                  decoration: const InputDecoration(labelText: 'Recurrence'),
                  items: const [
                    DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                    DropdownMenuItem(value: 'biweekly', child: Text('Every 2 weeks')),
                    DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                  ],
                  onChanged: (v) => setState(() => _frequency = v ?? 'weekly'),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 80,
                child: DropdownButtonFormField<int>(
                  value: _interval,
                  decoration: const InputDecoration(labelText: 'Interval'),
                  items: List.generate(12, (i) => i + 1)
                      .map((i) => DropdownMenuItem(value: i, child: Text('$i')))
                      .toList(),
                  onChanged: (v) => setState(() => _interval = v ?? 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Time blocks (per day)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ..._blocks.asMap().entries.map((e) {
            final b = e.value;
            const dayNames = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
            return ListTile(
              title: Text(
                '${dayNames[b.dayOfWeek]} ${b.startTime}–${b.endTime}'
                '${b.bookableOnline ? '' : ' (not bookable online)'}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => _removeBlock(e.key),
              ),
            );
          }),
          OutlinedButton.icon(
            onPressed: () => _showAddBlockDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('Add time block'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionCtl,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
              hintText: 'e.g. Clinic A regular hours',
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Active'),
            subtitle: const Text('When off, this rule is not applied'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddBlockDialog(BuildContext context) async {
    int dayOfWeek = 1;
    var start = '09:00';
    var end = '17:00';
    var bookable = true;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Add time block'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      value: dayOfWeek,
                      decoration: const InputDecoration(labelText: 'Day'),
                      items: [1, 2, 3, 4, 5, 6, 7]
                          .map((d) => DropdownMenuItem(
                                value: d,
                                child: Text(
                                  ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d - 1],
                                ),
                              ))
                          .toList(),
                      onChanged: (v) => setDialogState(() => dayOfWeek = v ?? 1),
                    ),
                    TextFormField(
                      initialValue: start,
                      decoration: const InputDecoration(labelText: 'Start (HH:mm)'),
                      onChanged: (v) => start = v.trim(),
                    ),
                    TextFormField(
                      initialValue: end,
                      decoration: const InputDecoration(labelText: 'End (HH:mm)'),
                      onChanged: (v) => end = v.trim(),
                    ),
                    SwitchListTile(
                      title: const Text('Bookable online'),
                      value: bookable,
                      onChanged: (v) => setDialogState(() => bookable = v),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (start.isEmpty) start = '09:00';
                    if (end.isEmpty) end = '17:00';
                    _addBlock(dayOfWeek, start, end, bookable: bookable);
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
