// lib/features/settings/screens/questionnaire_templates_list_screen.dart
//
// OBS-P2: List clinic questionnaire templates (built-in + clinic) with governance.
// Shows templateId, label, description, active, patientFacing, category, version,
// flowDefinitionId, clinicalProfileId; "In use in Online booking" when selected.
// Built-in vs clinic sections; metadata editor (name, description, active, patientFacing, category) for clinic only.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/public_booking_settings_repository.dart';
import '../../../models/public_booking_settings.dart';

class QuestionnaireTemplatesListScreen extends StatefulWidget {
  const QuestionnaireTemplatesListScreen({
    super.key,
    required this.clinicId,
  });

  final String clinicId;

  @override
  State<QuestionnaireTemplatesListScreen> createState() =>
      _QuestionnaireTemplatesListScreenState();
}

class _QuestionnaireTemplatesListScreenState
    extends State<QuestionnaireTemplatesListScreen> {
  List<Map<String, dynamic>> _templates = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'europe-west3');
      final result = await fn
          .httpsCallable('listQuestionnaireTemplatesFn')
          .call({'clinicId': widget.clinicId});
      final data = result.data as Map<String, dynamic>?;
      final list = (data?['templates'] as List<dynamic>?) ?? [];
      setState(() {
        _templates = list
            .map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _updateToggle(String templateId, String field, bool value) async {
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'europe-west3');
      await fn.httpsCallable('updateQuestionnaireTemplateFn').call({
        'clinicId': widget.clinicId,
        'templateId': templateId,
        field: value,
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e')),
        );
      }
    }
  }

  Future<void> _updateMetadata({
    required String templateId,
    String? label,
    String? description,
    bool? active,
    bool? patientFacing,
    String? category,
  }) async {
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'europe-west3');
      final payload = <String, dynamic>{
        'clinicId': widget.clinicId,
        'templateId': templateId,
      };
      if (label != null) payload['label'] = label;
      if (description != null) payload['description'] = description;
      if (active != null) payload['active'] = active;
      if (patientFacing != null) payload['patientFacing'] = patientFacing;
      if (category != null) payload['category'] = category;
      await fn.httpsCallable('updateQuestionnaireTemplateFn').call(payload);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Template updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e')),
        );
      }
      rethrow;
    }
  }

  void _openEditDialog(Map<String, dynamic> template) {
    showDialog<void>(
      context: context,
      builder: (context) => _TemplateEditDialog(
        clinicId: widget.clinicId,
        template: template,
        onSave: _updateMetadata,
        onClosed: () => Navigator.of(context).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final repo = context.read<PublicBookingSettingsRepository>();
    return StreamBuilder<PublicBookingSettings>(
      stream: repo.streamSettings(widget.clinicId),
      builder: (context, settingsSnap) {
        final selectedTemplateIds = <String>{
          ...?settingsSnap.data?.questionnaireFlow.templates
              .map((r) => r.templateId),
        };
        final builtIn = _templates
            .where((t) =>
                (t['source'] as String? ?? '').toLowerCase() == 'builtin')
            .toList();
        final clinic = _templates
            .where((t) =>
                (t['source'] as String? ?? '').toLowerCase() != 'builtin')
            .toList()
          ..sort((a, b) =>
              ((a['label'] as String?) ?? '')
                  .toLowerCase()
                  .compareTo(((b['label'] as String?) ?? '').toLowerCase()));

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Questionnaire templates',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Built-in and clinic templates. Active and patient-facing control visibility in booking and links.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 24),
              // Built-in templates
              Text(
                'Built-in templates',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              if (builtIn.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No built-in templates.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                )
              else
                ...builtIn.map((t) => _TemplateCard(
                      template: t,
                      selectedInBooking: selectedTemplateIds.contains(t['templateId'] as String?),
                      onUpdate: _updateToggle,
                      onEdit: null,
                    )),
              const SizedBox(height: 24),
              // Clinic templates
              Text(
                'Clinic templates',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              if (clinic.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No clinic-created templates.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                )
              else
                ...clinic.map((t) => _TemplateCard(
                      template: t,
                      selectedInBooking: selectedTemplateIds.contains(t['templateId'] as String?),
                      onUpdate: _updateToggle,
                      onEdit: () => _openEditDialog(t),
                    )),
            ],
          ),
        );
      },
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.selectedInBooking,
    required this.onUpdate,
    this.onEdit,
  });

  final Map<String, dynamic> template;
  final bool selectedInBooking;
  final Future<void> Function(String templateId, String field, bool value) onUpdate;
  final VoidCallback? onEdit;

  bool get _isBuiltIn =>
      (template['source'] as String? ?? '').toLowerCase() == 'builtin';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final templateId = template['templateId'] as String? ?? '';
    final label = template['label'] as String? ?? templateId;
    final description = template['description'] as String?;
    final active = template['active'] as bool? ?? true;
    final patientFacing = template['patientFacing'] as bool? ?? true;
    final flowDefinitionId = template['flowDefinitionId'] as String?;
    final clinicalProfileId = template['clinicalProfileId'] as String?;
    final version = template['version'] as int?;
    final category = template['category'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                if (_isBuiltIn)
                  Chip(
                    label: Text(
                      'Built-in',
                      style: theme.textTheme.labelSmall,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                if (selectedInBooking) ...[
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(
                      'In use in Online booking',
                      style: theme.textTheme.labelSmall,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
                if (onEdit != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: onEdit,
                    tooltip: 'Edit metadata',
                  ),
                ],
              ],
            ),
            if (templateId.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  templateId,
                  style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                        fontFamily: 'monospace',
                      ),
                ),
              ),
            if (category != null && category.isNotEmpty || version != null) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (category != null && category.isNotEmpty)
                    Text(
                      'Category: $category',
                      style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                    ),
                  if (version != null)
                    Text(
                      'Version: $version',
                      style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                    ),
                ],
              ),
            ],
            if (description != null && description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            if (flowDefinitionId != null && flowDefinitionId.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Flow: $flowDefinitionId',
                  style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                ),
              ),
            if (clinicalProfileId != null && clinicalProfileId.isNotEmpty)
              Text(
                'Profile: $clinicalProfileId',
                style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Active', style: theme.textTheme.labelMedium),
                const SizedBox(width: 8),
                if (_isBuiltIn)
                  Icon(
                    active ? Icons.check_circle : Icons.cancel,
                    size: 20,
                    color: theme.colorScheme.outline,
                  )
                else
                  Switch(
                    value: active,
                    onChanged: (v) => onUpdate(templateId, 'active', v),
                  ),
                const SizedBox(width: 24),
                Text('Patient-facing', style: theme.textTheme.labelMedium),
                const SizedBox(width: 8),
                if (_isBuiltIn)
                  Icon(
                    patientFacing ? Icons.check_circle : Icons.cancel,
                    size: 20,
                    color: theme.colorScheme.outline,
                  )
                else
                  Switch(
                    value: patientFacing,
                    onChanged: (v) => onUpdate(templateId, 'patientFacing', v),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateEditDialog extends StatefulWidget {
  const _TemplateEditDialog({
    required this.clinicId,
    required this.template,
    required this.onSave,
    required this.onClosed,
  });

  final String clinicId;
  final Map<String, dynamic> template;
  final Future<void> Function({
    required String templateId,
    String? label,
    String? description,
    bool? active,
    bool? patientFacing,
    String? category,
  }) onSave;
  final VoidCallback onClosed;

  @override
  State<_TemplateEditDialog> createState() => _TemplateEditDialogState();
}

class _TemplateEditDialogState extends State<_TemplateEditDialog> {
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _categoryController;
  late bool _active;
  late bool _patientFacing;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.template['label'] as String? ?? widget.template['templateId'] as String? ?? '',
    );
    _descriptionController = TextEditingController(
      text: widget.template['description'] as String? ?? '',
    );
    _categoryController = TextEditingController(
      text: widget.template['category'] as String? ?? '',
    );
    _active = widget.template['active'] as bool? ?? true;
    _patientFacing = widget.template['patientFacing'] as bool? ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final label = _nameController.text.trim();
    if (label.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name is required')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSave(
        templateId: widget.template['templateId'] as String,
        label: label,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        active: _active,
        patientFacing: _patientFacing,
        category: _categoryController.text.trim().isEmpty
            ? null
            : _categoryController.text.trim(),
      );
      widget.onClosed();
    } catch (_) {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final templateId = widget.template['templateId'] as String? ?? '';
    final version = widget.template['version'] as int?;
    final flowDefinitionId = widget.template['flowDefinitionId'] as String?;
    final clinicalProfileId = widget.template['clinicalProfileId'] as String?;

    return AlertDialog(
      title: const Text('Edit template metadata'),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Template ID (read-only)', style: theme.textTheme.labelSmall),
              const SizedBox(height: 4),
              SelectableText(
                templateId,
                style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
              ),
              if (version != null) ...[
                const SizedBox(height: 12),
                Text('Version (read-only)', style: theme.textTheme.labelSmall),
                const SizedBox(height: 4),
                SelectableText('$version', style: theme.textTheme.bodyMedium),
              ],
              if (flowDefinitionId != null && flowDefinitionId.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Flow definition (read-only)', style: theme.textTheme.labelSmall),
                const SizedBox(height: 4),
                SelectableText(
                  flowDefinitionId,
                  style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                ),
              ],
              if (clinicalProfileId != null && clinicalProfileId.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Clinical profile (read-only)', style: theme.textTheme.labelSmall),
                const SizedBox(height: 4),
                SelectableText(
                  clinicalProfileId,
                  style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                ),
              ],
              const SizedBox(height: 20),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _categoryController,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Active'),
                value: _active,
                onChanged: _saving ? null : (v) => setState(() => _active = v),
              ),
              SwitchListTile(
                title: const Text('Patient-facing'),
                value: _patientFacing,
                onChanged: _saving ? null : (v) => setState(() => _patientFacing = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : widget.onClosed,
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
        ),
      ],
    );
  }
}
