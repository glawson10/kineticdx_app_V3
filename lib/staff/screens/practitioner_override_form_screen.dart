// lib/staff/screens/practitioner_override_form_screen.dart
//
// Add or edit one override (sickness, holiday, training).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/practitioner_overrides_repository.dart';
import '../../models/clinic_location.dart';
import '../../models/availability_override.dart';

class PractitionerOverrideFormScreen extends StatefulWidget {
  const PractitionerOverrideFormScreen({
    super.key,
    required this.clinicId,
    required this.practitionerId,
    required this.locations,
    this.existing,
    this.presetReason,
  });

  final String clinicId;
  final String practitionerId;
  final List<ClinicLocation> locations;
  final PractitionerOverride? existing;
  final OverrideReason? presetReason;

  @override
  State<PractitionerOverrideFormScreen> createState() =>
      _PractitionerOverrideFormScreenState();
}

class _PractitionerOverrideFormScreenState
    extends State<PractitionerOverrideFormScreen> {
  late String _reason;
  late DateTime _fromAt;
  late DateTime _toAt;
  String? _locationId; // null = all locations
  late bool _isAvailable;
  final _descriptionCtl = TextEditingController();
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  static String _reasonToString(OverrideReason r) {
    switch (r) {
      case OverrideReason.sickness:
        return 'sickness';
      case OverrideReason.holiday:
        return 'holiday';
      case OverrideReason.training:
        return 'training';
      case OverrideReason.other:
        return 'other';
    }
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final preset = widget.presetReason;
    if (existing != null) {
      _reason = existing.reason ?? 'other';
      _fromAt = existing.fromAt;
      _toAt = existing.toAt;
      _locationId = existing.locationId;
      _isAvailable = existing.isAvailable;
      _descriptionCtl.text = existing.description ?? '';
    } else {
      _reason = preset != null ? _reasonToString(preset) : 'holiday';
      final now = DateTime.now();
      _fromAt = DateTime(now.year, now.month, now.day, 9, 0);
      _toAt = DateTime(now.year, now.month, now.day, 17, 0);
      _locationId = null;
      _isAvailable = false; // sickness/holiday default unavailable
      if (preset == OverrideReason.training) _isAvailable = true;
    }
  }

  @override
  void dispose() {
    _descriptionCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_toAt.isBefore(_fromAt) || _toAt.isAtSameMomentAs(_fromAt)) {
      setState(() => _error = 'To date/time must be after from.');
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      final repo = context.read<PractitionerOverridesRepository>();
      final patch = {
        'fromAt': _fromAt.millisecondsSinceEpoch,
        'toAt': _toAt.millisecondsSinceEpoch,
        'isAvailable': _isAvailable,
        'locationId': _locationId,
        'description': _descriptionCtl.text.trim(),
        'reason': _reason,
      };
      await repo.upsertOverride(
        clinicId: widget.clinicId,
        practitionerId: widget.practitionerId,
        overrideId: widget.existing?.id,
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

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete override?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await context.read<PractitionerOverridesRepository>().deleteOverride(
            clinicId: widget.clinicId,
            practitionerId: widget.practitionerId,
            overrideId: existing.id,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deleted.')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null ? 'Add override' : 'Edit override',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: _reason,
            decoration: const InputDecoration(labelText: 'Type'),
            items: const [
              DropdownMenuItem(value: 'sickness', child: Text('Sickness')),
              DropdownMenuItem(value: 'holiday', child: Text('Holiday')),
              DropdownMenuItem(value: 'training', child: Text('Training')),
              DropdownMenuItem(value: 'other', child: Text('Other')),
            ],
            onChanged: (v) => setState(() => _reason = v ?? 'other'),
          ),
          const SizedBox(height: 12),
          ListTile(
            title: const Text('From date and time'),
            subtitle: Text(
              '${_fromAt.year}-${_fromAt.month.toString().padLeft(2, '0')}-${_fromAt.day.toString().padLeft(2, '0')} '
              '${_fromAt.hour.toString().padLeft(2, '0')}:${_fromAt.minute.toString().padLeft(2, '0')}',
            ),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _fromAt,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (date != null && mounted) {
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(_fromAt),
                );
                if (time != null && mounted) {
                  setState(() {
                    _fromAt = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      time.hour,
                      time.minute,
                    );
                  });
                }
              }
            },
          ),
          ListTile(
            title: const Text('To date and time'),
            subtitle: Text(
              '${_toAt.year}-${_toAt.month.toString().padLeft(2, '0')}-${_toAt.day.toString().padLeft(2, '0')} '
              '${_toAt.hour.toString().padLeft(2, '0')}:${_toAt.minute.toString().padLeft(2, '0')}',
            ),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _toAt,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (date != null && mounted) {
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(_toAt),
                );
                if (time != null && mounted) {
                  setState(() {
                    _toAt = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      time.hour,
                      time.minute,
                    );
                  });
                }
              }
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            value: _locationId,
            decoration: const InputDecoration(
              labelText: 'Applies to',
              hintText: 'All locations',
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All locations'),
              ),
              ...widget.locations.map(
                (l) => DropdownMenuItem<String?>(
                  value: l.id,
                  child: Text(l.name.isNotEmpty ? l.name : l.id),
                ),
              ),
            ],
            onChanged: (v) => setState(() => _locationId = v),
          ),
          const SizedBox(height: 12),
          RadioListTile<bool>(
            title: const Text('Unavailable'),
            subtitle: const Text('You are not available in this period'),
            value: false,
            groupValue: _isAvailable,
            onChanged: (v) => setState(() => _isAvailable = false),
          ),
          RadioListTile<bool>(
            title: const Text('Available'),
            subtitle: const Text('Extra available (e.g. training day)'),
            value: true,
            groupValue: _isAvailable,
            onChanged: (v) => setState(() => _isAvailable = true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionCtl,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
              hintText: 'e.g. Annual leave, Course at HQ',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: (_saving || _deleting) ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: Text(_saving ? 'Saving…' : 'Save'),
          ),
          if (widget.existing != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _deleting ? null : _delete,
              icon: _deleting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
              label: const Text('Delete override'),
            ),
          ],
        ],
      ),
    );
  }
}
