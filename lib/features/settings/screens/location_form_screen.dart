// lib/features/settings/screens/location_form_screen.dart
// Create/edit location via settingsUpsertLocation callable.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/callable_error_mapping.dart';
import '../../../data/repositories/locations_repository.dart';
import '../../../models/clinic_location.dart';

class LocationFormScreen extends StatefulWidget {
  const LocationFormScreen({
    super.key,
    required this.clinicId,
    this.location,
    required this.onSaved,
    required this.onCancel,
  });

  final String clinicId;
  final ClinicLocation? location;
  final VoidCallback onSaved;
  final VoidCallback onCancel;

  @override
  State<LocationFormScreen> createState() => _LocationFormScreenState();
}

class _LocationFormScreenState extends State<LocationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _colorHexController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();
  bool _showInOnlineBooking = true;
  bool _active = true;
  String? _error;
  bool _saving = false;

  bool _isValidHex(String? s) {
    if (s == null || s.isEmpty) return true;
    final h = s.replaceFirst('#', '').trim();
    return h.length == 6 && int.tryParse(h, radix: 16) != null;
  }

  @override
  void initState() {
    super.initState();
    final loc = widget.location;
    if (loc != null) {
      _nameController.text = loc.name;
      _addressController.text = loc.addressText;
      _colorHexController.text = loc.colorHex ?? '';
      _phoneController.text = loc.phone ?? '';
      _notesController.text = loc.notes ?? '';
      _showInOnlineBooking = loc.showInOnlineBooking;
      _active = loc.active;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _colorHexController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = context.read<LocationsRepository>();
      await repo.upsert(
        widget.clinicId,
        locationId: widget.location?.id,
        patch: {
          'name': _nameController.text.trim(),
          'addressText': _addressController.text.trim(),
          'colorHex': _colorHexController.text.trim().isEmpty ? null : (_colorHexController.text.trim().startsWith('#') ? _colorHexController.text.trim() : '#${_colorHexController.text.trim()}'),
          'phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
          'notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
          'showInOnlineBooking': _showInOnlineBooking,
          'active': _active,
        },
      );
      if (!mounted) return;
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = messageForCallableError(e, fallback: 'Failed to save location');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            ],
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _addressController,
              decoration: const InputDecoration(
                labelText: 'Address',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
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
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone (optional)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Show in online booking'),
              value: _showInOnlineBooking,
              onChanged: (v) => setState(() => _showInOnlineBooking = v),
            ),
            SwitchListTile(
              title: const Text('Active'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
                ),
                const SizedBox(width: 12),
                TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
