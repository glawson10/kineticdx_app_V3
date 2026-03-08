// lib/features/settings/screens/public_booking_settings_screen.dart
//
// Commit 15: Public booking config (private doc). Read from Firestore; write via callable only.

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/callable_error_mapping.dart';
import '../../../app/clinic_context.dart';
import '../../../data/repositories/public_booking_settings_repository.dart';
import '../../../features/auth/permission_guard.dart';
import '../../../models/public_booking_settings.dart';

class PublicBookingSettingsScreen extends StatefulWidget {
  const PublicBookingSettingsScreen({
    super.key,
    required this.clinicId,
  });

  final String clinicId;

  @override
  State<PublicBookingSettingsScreen> createState() => _PublicBookingSettingsScreenState();
}

class _PublicBookingSettingsScreenState extends State<PublicBookingSettingsScreen> {
  int _slotStepMinutes = 15;
  int _minNoticeMinutes = 0;
  int _maxAdvanceDays = 90;
  bool _requirePhone = false;
  bool _requireEmail = true;
  bool _allowNewPatients = true;
  int _cancellationPolicyHours = 24;
  bool _saving = false;
  String? _error;
  bool _initialized = false;

  static const List<int> minNoticeOptions = [
    0,
    60,
    120,
    240,
    480,
    1440,
    2880,
    10080,
  ]; // up to 7 days

  void _apply(PublicBookingSettings s) {
    if (_initialized) return;
    setState(() {
      _slotStepMinutes = s.slotStepMinutes;
      _minNoticeMinutes = s.minNoticeMinutes;
      _maxAdvanceDays = s.maxAdvanceDays;
      _requirePhone = s.requirePhone;
      _requireEmail = s.requireEmail;
      _allowNewPatients = s.allowNewPatients;
      _cancellationPolicyHours = s.cancellationPolicyHours;
      _initialized = true;
    });
  }

  Future<void> _save() async {
    setState(() => _error = null);
    setState(() => _saving = true);
    try {
      final repo = context.read<PublicBookingSettingsRepository>();
      final patch = PublicBookingSettings(
        slotStepMinutes: _slotStepMinutes,
        minNoticeMinutes: _minNoticeMinutes,
        maxAdvanceDays: _maxAdvanceDays,
        requirePhone: _requirePhone,
        requireEmail: _requireEmail,
        allowNewPatients: _allowNewPatients,
        cancellationPolicyHours: _cancellationPolicyHours,
      ).toPatch();
      await repo.updateSettings(widget.clinicId, patch).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException('Save timed out'),
      );
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Public booking settings saved.')),
      );
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = messageForCallableError(
            e,
            fallback: 'You don\'t have permission to change these settings.',
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = messageForCallableError(
            e,
            fallback: 'Failed to save.',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final guard = PermissionGuard(context.watch<ClinicContext>().permissions);
    final canWrite = guard.has('settings.write');
    final repo = context.read<PublicBookingSettingsRepository>();

    return StreamBuilder<PublicBookingSettings>(
      stream: repo.streamSettings(widget.clinicId),
      builder: (context, snap) {
        if (snap.hasData && !_initialized) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _apply(snap.data!);
          });
        }
        final loading = !snap.hasData && snap.connectionState == ConnectionState.waiting;
        if (loading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Failed to load: ${snap.error}'),
            ),
          );
        }

        final maxAdvanceOptions = <int>[
          for (int d = PublicBookingSettings.maxAdvanceDaysMin;
              d <= PublicBookingSettings.maxAdvanceDaysMax;
              d += (d <= 30 ? 1 : (d <= 90 ? 7 : 30)))
            d,
        ];
        if (!maxAdvanceOptions.contains(_maxAdvanceDays)) {
          maxAdvanceOptions.add(_maxAdvanceDays);
          maxAdvanceOptions.sort((a, b) => a.compareTo(b));
        }

        return PopScope(
          canPop: !_saving,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Hint so admins know why public booking may show no slots.
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Material(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'Available times on the public booking page come from Opening hours (Settings → Clinic → Opening hours). Save weekly hours there so patients see bookable slots.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
                Text(
                  'Booking window',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _maxAdvanceDays,
                  decoration: const InputDecoration(
                    labelText: 'Max advance (days)',
                  ),
                  items: maxAdvanceOptions.map((d) => DropdownMenuItem(value: d, child: Text('$d days'))).toList(),
                  onChanged: canWrite && !_saving
                      ? (v) => setState(() => _maxAdvanceDays = v ?? _maxAdvanceDays)
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: minNoticeOptions.contains(_minNoticeMinutes)
                      ? _minNoticeMinutes
                      : minNoticeOptions.first,
                  decoration: const InputDecoration(
                    labelText: 'Minimum notice (minutes)',
                  ),
                  items: minNoticeOptions
                      .map((m) => DropdownMenuItem(
                            value: m,
                            child: Text(m == 0 ? '0' : '${m ~/ 60} h'),
                          ))
                      .toList(),
                  onChanged: canWrite && !_saving
                      ? (v) => setState(() => _minNoticeMinutes = v ?? 0)
                      : null,
                ),
                const SizedBox(height: 24),
                Text(
                  'Slot step',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: PublicBookingSettings.slotStepOptions.map((m) {
                    final selected = _slotStepMinutes == m;
                    return ChoiceChip(
                      label: Text('$m min'),
                      selected: selected,
                      onSelected: canWrite && !_saving
                          ? (v) => setState(() => _slotStepMinutes = m)
                          : null,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                Text(
                  'New patient policy',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                SwitchListTile(
                  title: const Text('Allow new patients'),
                  value: _allowNewPatients,
                  onChanged: canWrite && !_saving
                      ? (v) => setState(() => _allowNewPatients = v)
                      : null,
                ),
                const SizedBox(height: 16),
                Text(
                  'Required contact fields',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                SwitchListTile(
                  title: const Text('Require email'),
                  value: _requireEmail,
                  onChanged: canWrite && !_saving
                      ? (v) => setState(() => _requireEmail = v)
                      : null,
                ),
                SwitchListTile(
                  title: const Text('Require phone'),
                  value: _requirePhone,
                  onChanged: canWrite && !_saving
                      ? (v) => setState(() => _requirePhone = v)
                      : null,
                ),
                if (!_requireEmail && !_requirePhone)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, top: 4),
                    child: Text(
                      'At least one contact field is recommended.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                    ),
                  ),
                const SizedBox(height: 24),
                Text(
                  'Cancellation policy',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Hours before appointment that cancellation is required (0 = no policy).',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: [0, 24, 48, 72, 168].contains(_cancellationPolicyHours)
                      ? _cancellationPolicyHours
                      : 24,
                  decoration: const InputDecoration(
                    labelText: 'Cancellation policy (hours)',
                  ),
                  items: [0, 24, 48, 72, 168]
                      .map((h) => DropdownMenuItem(
                            value: h,
                            child: Text(h == 0 ? 'No policy' : '$h h'),
                          ))
                      .toList(),
                  onChanged: canWrite && !_saving
                      ? (v) => setState(() => _cancellationPolicyHours = v ?? 0)
                      : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: (canWrite && !_saving) ? _save : null,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
