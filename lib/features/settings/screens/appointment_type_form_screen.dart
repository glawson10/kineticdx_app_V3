// lib/features/settings/screens/appointment_type_form_screen.dart
//
// Settings → Appointment types → Add/Edit. Writes via settingsUpsertAppointmentType callable.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/callable_error_mapping.dart';
import '../../../data/repositories/appointment_types_repository.dart';
import '../../../data/repositories/locations_repository.dart';
import '../../../models/appointment_type.dart';
import '../../../models/clinic_location.dart';

class AppointmentTypeFormScreen extends StatefulWidget {
  const AppointmentTypeFormScreen({
    super.key,
    required this.clinicId,
    this.type,
    this.onSaved,
    this.onCancel,
  });

  final String clinicId;
  final AppointmentType? type;
  final VoidCallback? onSaved;
  final VoidCallback? onCancel;

  @override
  State<AppointmentTypeFormScreen> createState() => _AppointmentTypeFormScreenState();
}

class _AppointmentTypeFormScreenState extends State<AppointmentTypeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _durationController = TextEditingController();
  final _priceController = TextEditingController();
  final _colorHexController = TextEditingController();
  bool _active = true;
  bool _showInOnlineBooking = false;
  List<String> _allowedLocationIds = [];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  void _hydrate() {
    final t = widget.type;
    if (t != null) {
      _nameController.text = t.name;
      _descriptionController.text = t.description ?? '';
      _durationController.text = '${t.durationMinutes}';
      _priceController.text = t.defaultPrice != null ? t.defaultPrice.toString() : '';
      _colorHexController.text = t.colorHex ?? '';
      _active = t.active;
      _showInOnlineBooking = t.showInOnlineBooking;
      _allowedLocationIds = List.from(t.allowedLocationIds);
      return;
    }
    _durationController.text = '30';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _durationController.dispose();
    _priceController.dispose();
    _colorHexController.dispose();
    super.dispose();
  }

  bool _isValidHex(String? s) {
    if (s == null || s.isEmpty) return true;
    final h = s.replaceFirst('#', '');
    return h.length == 6 && int.tryParse(h, radix: 16) != null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _error = null);
    setState(() => _saving = true);
    final name = _nameController.text.trim();
    if (name.length < 2) {
      setState(() {
        _saving = false;
        _error = 'Name must be at least 2 characters.';
      });
      return;
    }
    final durationStr = _durationController.text.trim();
    final duration = int.tryParse(durationStr);
    if (duration == null || duration < 5 || duration > 480 || duration % 5 != 0) {
      setState(() {
        _saving = false;
        _error = 'Duration must be between 5 and 480 minutes, in steps of 5.';
      });
      return;
    }
    final priceStr = _priceController.text.trim();
    double? defaultPrice;
    if (priceStr.isNotEmpty) {
      defaultPrice = double.tryParse(priceStr);
      if (defaultPrice == null || defaultPrice < 0) {
        setState(() {
          _saving = false;
          _error = 'Price must be a non-negative number.';
        });
        return;
      }
    }
    final colorHex = _colorHexController.text.trim();
    if (colorHex.isNotEmpty && !_isValidHex(colorHex)) {
      setState(() {
        _saving = false;
        _error = 'Color must be a 6-digit hex code (e.g. #FF5733).';
      });
      return;
    }
    try {
      final repo = context.read<AppointmentTypesRepository>();
      final patch = <String, dynamic>{
        'name': name,
        'durationMinutes': duration,
        'description': _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        'defaultPrice': defaultPrice,
        'colorHex': colorHex.isEmpty ? null : (colorHex.startsWith('#') ? colorHex : '#$colorHex'),
        'active': _active,
        'showInOnlineBooking': _showInOnlineBooking,
        'allowedLocationIds': _allowedLocationIds.isEmpty ? null : _allowedLocationIds,
      };
      await repo.upsert(widget.clinicId, appointmentTypeId: widget.type?.id, patch: patch);
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.type != null ? 'Appointment type updated.' : 'Appointment type created.')),
      );
      widget.onSaved?.call();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = messageForCallableError(e, fallback: 'Failed to save appointment type.');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = messageForCallableError(e, fallback: 'Failed to save.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.type != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onErrorContainer),
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Initial consultation',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) {
                final s = (v ?? '').trim();
                if (s.isEmpty) return 'Name is required.';
                if (s.length < 2) return 'Name must be at least 2 characters.';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _durationController,
              decoration: const InputDecoration(
                labelText: 'Duration (minutes)',
                hintText: '30',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                final n = int.tryParse((v ?? '').trim());
                if (n == null) return 'Enter a number (5–480, step 5).';
                if (n < 5 || n > 480) return 'Duration must be 5–480.';
                if (n % 5 != 0) return 'Must be divisible by 5.';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Optional; shown on public booking and price list',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _priceController,
              decoration: const InputDecoration(
                labelText: 'Default price',
                hintText: 'Optional; e.g. 50.00',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _colorHexController,
              decoration: const InputDecoration(
                labelText: 'Color (hex)',
                hintText: '#FF5733 or FF5733',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final s = (v ?? '').trim();
                if (s.isEmpty) return null;
                return _isValidHex(s) ? null : 'Use 6-digit hex (e.g. #FF5733).';
              },
            ),
            const SizedBox(height: 24),
            SwitchListTile(
              title: const Text('Active'),
              subtitle: const Text('Inactive types are hidden from calendar and booking.'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            SwitchListTile(
              title: const Text('Show in online booking'),
              subtitle: const Text('Include in public booking and price list.'),
              value: _showInOnlineBooking,
              onChanged: (v) => setState(() => _showInOnlineBooking = v),
            ),
            const SizedBox(height: 16),
            const Text('Allowed locations', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            const Text(
              'Leave empty for all locations. Or select specific locations where this type is offered.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<ClinicLocation>>(
              stream: context.read<LocationsRepository>().watchLocations(widget.clinicId),
              builder: (context, snap) {
                final locations = snap.data ?? [];
                if (locations.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No locations. Add locations in Settings → Locations.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  );
                }
                return Column(
                  children: locations.map((loc) {
                    final selected = _allowedLocationIds.contains(loc.id);
                    return CheckboxListTile(
                      title: Text(loc.name),
                      value: selected,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _allowedLocationIds = List.from(_allowedLocationIds)..add(loc.id);
                          } else {
                            _allowedLocationIds = List.from(_allowedLocationIds)..remove(loc.id);
                          }
                        });
                      },
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.onPrimary),
                        )
                      : Text(isEdit ? 'Update' : 'Create'),
                ),
                const SizedBox(width: 16),
                if (widget.onCancel != null)
                  TextButton(
                    onPressed: _saving ? null : widget.onCancel,
                    child: const Text('Cancel'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
