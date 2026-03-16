// lib/features/settings/screens/public_booking_settings_screen.dart
//
// Commit 15: Public booking config (private doc). Read from Firestore; write via callable only.

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/callable_error_mapping.dart';
import '../../../app/clinic_context.dart';
import '../../../data/repositories/locations_repository.dart';
import '../../../data/repositories/public_booking_settings_repository.dart';
import '../../../features/auth/permission_guard.dart';
import '../../../models/clinic_location.dart';
import '../../../models/public_booking_settings.dart';
import '../../../models/questionnaire_flow.dart';
import '../../booking/data/questionnaire_template_catalog_service.dart';

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
  bool _onlineBookingEnabled = true;
  int _slotStepMinutes = 15;
  int _minNoticeMinutes = 0;
  int _maxAdvanceDays = 90;
  bool _requirePhone = false;
  bool _requireEmail = true;
  bool _allowNewPatients = true;
  int _cancellationPolicyHours = 24;
  String _confirmationMessage = '';
  QuestionnaireFlowConfig _questionnaireFlow = const QuestionnaireFlowConfig();
  late final TextEditingController _confirmationController;
  bool _saving = false;
  String? _error;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _confirmationController = TextEditingController();
  }

  @override
  void dispose() {
    _confirmationController.dispose();
    super.dispose();
  }

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
      _onlineBookingEnabled = s.onlineBookingEnabled;
      _slotStepMinutes = s.slotStepMinutes;
      _minNoticeMinutes = s.minNoticeMinutes;
      _maxAdvanceDays = s.maxAdvanceDays;
      _requirePhone = s.requirePhone;
      _requireEmail = s.requireEmail;
      _allowNewPatients = s.allowNewPatients;
      _cancellationPolicyHours = s.cancellationPolicyHours;
      _confirmationMessage = s.confirmationMessage ?? '';
      _confirmationController.text = _confirmationMessage;
      _questionnaireFlow = s.questionnaireFlow;
      _initialized = true;
    });
  }

  Future<void> _save() async {
    setState(() => _error = null);
    setState(() => _saving = true);
    try {
      final repo = context.read<PublicBookingSettingsRepository>();
      final patch = PublicBookingSettings(
        onlineBookingEnabled: _onlineBookingEnabled,
        slotStepMinutes: _slotStepMinutes,
        minNoticeMinutes: _minNoticeMinutes,
        maxAdvanceDays: _maxAdvanceDays,
        requirePhone: _requirePhone,
        requireEmail: _requireEmail,
        allowNewPatients: _allowNewPatients,
        cancellationPolicyHours: _cancellationPolicyHours,
        confirmationMessage: _confirmationController.text.trim().isEmpty ? null : _confirmationController.text.trim(),
        questionnaireFlow: _questionnaireFlow,
      ).toPatch();
      await repo.updateSettings(widget.clinicId, patch).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException('Save timed out'),
      );
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved. Public booking will reflect changes shortly.')),
      );
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = messageForCallableError(
            e,
            fallback: 'You don\'t have permission to change these settings.',
            logHint: 'settingsUpdatePublicBookingConfig',
          );
        });
      }
    } catch (e, st) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = messageForCallableError(
            e,
            fallback: 'Failed to save. Check the Flutter run terminal for the error. For server errors see Firebase Console → Functions → settingsUpdatePublicBookingConfig (europe-west3).',
            logHint: 'settingsUpdatePublicBookingConfig',
          );
        });
        // So you can copy from terminal when debugging.
        debugPrint('PublicBookingSettings save error: $e');
        debugPrintStack(stackTrace: st);
      }
    }
  }

  Future<void> _showLocationPickerForTemplate(
    BuildContext context,
    QuestionnaireTemplateSummary template,
    List<String>? currentLocationIds,
    QuestionnaireTemplateCatalogService questionnaireService,
  ) async {
    final locationsRepo = context.read<LocationsRepository>();
    final result = await showDialog<_LocationPickerResult>(
      context: context,
      builder: (ctx) => _QuestionnaireLocationPickerDialog(
        clinicId: widget.clinicId,
        templateLabel: template.label,
        initialLocationIds: currentLocationIds,
        locationsStream: locationsRepo.watchLocations(widget.clinicId),
      ),
    );
    if (!mounted || result == null || result.cancelled) return;
    setState(() {
      _questionnaireFlow = questionnaireService.updateTemplateLocationIds(
        _questionnaireFlow,
        template.templateId,
        result.locationIds,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final guard = PermissionGuard(context.watch<ClinicContext>().permissions);
    final canWrite = guard.has('settings.write');
    final repo = context.read<PublicBookingSettingsRepository>();
    final questionnaireService =
        context.read<QuestionnaireTemplateCatalogService>();

    return StreamBuilder<PublicBookingSettings>(
      stream: repo.streamSettings(widget.clinicId),
      builder: (context, snap) {
        if (snap.hasData && !_initialized) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _apply(snap.data!);
          });
        }
        // Once we have loaded at least once, never show full-screen loading again so a
        // Firestore stream hiccup (e.g. web SDK internal assertion after save) doesn't trap the user.
        final loading = !_initialized &&
            !snap.hasData &&
            snap.connectionState == ConnectionState.waiting;
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
                Text(
                  'Online booking',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                SwitchListTile(
                  title: const Text('Online booking on'),
                  subtitle: const Text(
                    'When off, the public booking link and slots are unavailable; the landing page can show "Booking temporarily unavailable".',
                  ),
                  value: _onlineBookingEnabled,
                  onChanged: canWrite && !_saving
                      ? (v) => setState(() => _onlineBookingEnabled = v)
                      : null,
                ),
                const SizedBox(height: 24),
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
                const SizedBox(height: 24),
                Text(
                  'Confirmation message',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Optional text shown after a booking is confirmed (e.g. what to bring, cancellation reminder).',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _confirmationController,
                  onChanged: canWrite && !_saving ? (v) => setState(() => _confirmationMessage = v) : null,
                  maxLines: 3,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    hintText: 'e.g. Please bring your ID. Cancel at least 24 hours in advance.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Post-booking questionnaires',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose which patient-facing questionnaires can be launched after a booking is confirmed.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Enable questionnaire step'),
                  subtitle: const Text(
                    'When off, patients will skip straight past the questionnaire step after booking.',
                  ),
                  value: _questionnaireFlow.enabled,
                  onChanged: canWrite && !_saving
                      ? (v) => setState(() {
                            _questionnaireFlow = QuestionnaireFlowConfig(
                              enabled: v,
                              templates: _questionnaireFlow.templates,
                            );
                          })
                      : null,
                ),
                if (_questionnaireFlow.enabled)
                  StreamBuilder<List<QuestionnaireTemplateSummary>>(
                    stream: questionnaireService
                        .watchPatientFacingTemplates(widget.clinicId),
                    builder: (context, templateSnap) {
                      final raw = templateSnap.data ?? const <QuestionnaireTemplateSummary>[];
                      final list = raw.isEmpty
                          ? questionnaireService.builtInPatientFacingTemplates
                          : raw;
                      final templates = questionnaireService.sortByConfig(
                        list,
                        _questionnaireFlow,
                      );
                      final selectedTemplates =
                          questionnaireService.selectedTemplates(
                        templates,
                        _questionnaireFlow,
                      );
                      // Never show loading here: after setState we get a new stream so
                      // connectionState is briefly waiting and the section would collapse
                      // to a spinner. Always show the list (using fallback when no data).

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (templates.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                'No active patient-facing questionnaire templates are currently available.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            )
                          else
                            ...templates.map((template) {
                              final selected =
                                  questionnaireService.isSelected(
                                _questionnaireFlow,
                                template,
                              );
                              return Card(
                                margin: const EdgeInsets.only(top: 8),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  title: Text(template.label),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if ((template.description ?? '')
                                          .trim()
                                          .isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(template.description!),
                                        ),
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(top: 4),
                                        child: Text(
                                          template.isBuiltIn
                                              ? 'Built-in template'
                                              : 'Clinic template',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: Switch(
                                    value: selected,
                                    onChanged: canWrite && !_saving
                                        ? (v) => setState(() {
                                              _questionnaireFlow =
                                                  questionnaireService
                                                      .toggleTemplate(
                                                _questionnaireFlow,
                                                template,
                                                v,
                                              );
                                            })
                                        : null,
                                  ),
                                ),
                              );
                            }),
                          if (selectedTemplates.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              'Launch order',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            ...selectedTemplates.asMap().entries.map((entry) {
                              final index = entry.key;
                              final template = entry.value;
                              final refList = _questionnaireFlow.templates
                                  .where((r) => r.templateId == template.templateId)
                                  .toList();
                              final ref = refList.isEmpty ? null : refList.first;
                              final refIds = ref?.locationIds;
                              final locationLabel = refIds == null || refIds.isEmpty
                                  ? 'All locations'
                                  : '${refIds.length} location(s)';
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  title: Text(template.label),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('Position ${index + 1}'),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Locations: $locationLabel',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                  isThreeLine: true,
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Choose locations for this questionnaire',
                                        onPressed: canWrite && !_saving
                                            ? () => _showLocationPickerForTemplate(
                                                  context,
                                                  template,
                                                  ref?.locationIds,
                                                  questionnaireService,
                                                )
                                            : null,
                                        icon: const Icon(Icons.location_on_outlined),
                                      ),
                                      IconButton(
                                        tooltip: 'Move up',
                                        onPressed: canWrite &&
                                                !_saving &&
                                                index > 0
                                            ? () => setState(() {
                                                  _questionnaireFlow =
                                                      questionnaireService
                                                          .reorderSelectedTemplates(
                                                    _questionnaireFlow,
                                                    index,
                                                    index - 1,
                                                  );
                                                })
                                            : null,
                                        icon:
                                            const Icon(Icons.arrow_upward),
                                      ),
                                      IconButton(
                                        tooltip: 'Move down',
                                        onPressed: canWrite &&
                                                !_saving &&
                                                index <
                                                    selectedTemplates.length -
                                                        1
                                            ? () => setState(() {
                                                  _questionnaireFlow =
                                                      questionnaireService
                                                          .reorderSelectedTemplates(
                                                    _questionnaireFlow,
                                                    index,
                                                    index + 1,
                                                  );
                                                })
                                            : null,
                                        icon: const Icon(
                                          Icons.arrow_downward,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ],
                      );
                    },
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

class _LocationPickerResult {
  const _LocationPickerResult({required this.cancelled, this.locationIds});
  final bool cancelled;
  final List<String>? locationIds;
}

class _QuestionnaireLocationPickerDialog extends StatefulWidget {
  const _QuestionnaireLocationPickerDialog({
    required this.clinicId,
    required this.templateLabel,
    required this.initialLocationIds,
    required this.locationsStream,
  });

  final String clinicId;
  final String templateLabel;
  final List<String>? initialLocationIds;
  final Stream<List<ClinicLocation>> locationsStream;

  @override
  State<_QuestionnaireLocationPickerDialog> createState() =>
      _QuestionnaireLocationPickerDialogState();
}

class _QuestionnaireLocationPickerDialogState
    extends State<_QuestionnaireLocationPickerDialog> {
  late bool _allLocations;
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    final ids = widget.initialLocationIds;
    _allLocations = ids == null || ids.isEmpty;
    _selectedIds = ids != null && ids.isNotEmpty ? Set<String>.from(ids) : {};
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Locations for ${widget.templateLabel}'),
      content: StreamBuilder<List<ClinicLocation>>(
        stream: widget.locationsStream,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final locations = snap.data!.where((l) => l.active).toList();
          if (locations.isEmpty) {
            return const Text(
              'No active locations. Add locations in Settings → Locations.',
            );
          }
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RadioListTile<bool>(
                  title: const Text('All locations'),
                  value: true,
                  groupValue: _allLocations,
                  onChanged: (v) => setState(() {
                    _allLocations = true;
                    _selectedIds = {};
                  }),
                ),
                RadioListTile<bool>(
                  title: const Text('Only at selected locations'),
                  value: false,
                  groupValue: _allLocations,
                  onChanged: (v) => setState(() => _allLocations = false),
                ),
                if (!_allLocations) ...[
                  const SizedBox(height: 8),
                  ...locations.map((loc) => CheckboxListTile(
                        title: Text(loc.name),
                        value: _selectedIds.contains(loc.id),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selectedIds.add(loc.id);
                          } else {
                            _selectedIds.remove(loc.id);
                          }
                        }),
                      )),
                ],
              ],
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            List<String>? locationIds;
            if (_allLocations || _selectedIds.isEmpty) {
              locationIds = null;
            } else {
              final list = _selectedIds.toList();
              list.sort();
              locationIds = list;
            }
            Navigator.of(context).pop(_LocationPickerResult(
              cancelled: false,
              locationIds: locationIds,
            ));
          },
          child: const Text('OK'),
        ),
      ],
    );
  }
}
