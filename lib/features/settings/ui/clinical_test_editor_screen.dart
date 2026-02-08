import 'package:flutter/material.dart';

import '../../../data/repositories/clinic_registry_repository.dart';
import '../../../models/clinical_test_registry_item.dart';

/// Wrapper editor for clinic-scoped clinical tests.
///
/// Writes exclusively via Cloud Function:
/// clinics/{clinicId}/clinicalTestRegistry/{testId}
class ClinicalTestEditorScreen extends StatefulWidget {
  final String clinicId;
  final ClinicalTestRegistryItem? existing;

  const ClinicalTestEditorScreen({
    super.key,
    required this.clinicId,
    required this.existing,
  });

  @override
  State<ClinicalTestEditorScreen> createState() =>
      _ClinicalTestEditorScreenState();
}

class _ClinicalTestEditorScreenState extends State<ClinicalTestEditorScreen> {
  final ClinicRegistryRepository _repo = ClinicRegistryRepository();

  final TextEditingController _name = TextEditingController();
  final TextEditingController _short = TextEditingController();
  final TextEditingController _category = TextEditingController();
  final TextEditingController _regions = TextEditingController();
  final TextEditingController _tags = TextEditingController();

  final TextEditingController _instructions = TextEditingController();
  final TextEditingController _positive = TextEditingController();
  final TextEditingController _contra = TextEditingController();
  final TextEditingController _interpretation = TextEditingController();

  final TextEditingController _resultType = TextEditingController();
  final TextEditingController _allowedResults = TextEditingController();

  bool _active = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.name;
      _short.text = e.shortName ?? '';
      _category.text = e.category;
      _regions.text = e.bodyRegions.join(', ');
      _tags.text = e.tags.join(', ');
      _instructions.text = e.instructions ?? '';
      _positive.text = e.positiveCriteria ?? '';
      _contra.text = e.contraindications ?? '';
      _interpretation.text = e.interpretation ?? '';
      _resultType.text = e.resultType;
      _allowedResults.text = e.allowedResults.join(', ');
      _active = e.active;
    } else {
      _category.text = 'special_test';
      _resultType.text = 'ternary';
      _allowedResults.text = 'pos, neg, nt';
      _active = true;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _short.dispose();
    _category.dispose();
    _regions.dispose();
    _tags.dispose();
    _instructions.dispose();
    _positive.dispose();
    _contra.dispose();
    _interpretation.dispose();
    _resultType.dispose();
    _allowedResults.dispose();
    super.dispose();
  }

  List<String> _splitCsv(String s) => s
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final name = _name.text.trim();
      if (name.isEmpty) throw 'Name is required';

      await _repo.upsertClinicalTest(
        clinicId: widget.clinicId,
        testId: widget.existing?.id,
        name: name,
        shortName: _short.text.trim().isEmpty ? null : _short.text.trim(),
        category: _category.text.trim().isEmpty ? null : _category.text.trim(),
        bodyRegions: _splitCsv(_regions.text),
        tags: _splitCsv(_tags.text),
        instructions: _instructions.text.trim().isEmpty
            ? null
            : _instructions.text.trim(),
        positiveCriteria: _positive.text.trim().isEmpty
            ? null
            : _positive.text.trim(),
        contraindications: _contra.text.trim().isEmpty
            ? null
            : _contra.text.trim(),
        interpretation: _interpretation.text.trim().isEmpty
            ? null
            : _interpretation.text.trim(),
        resultType:
            _resultType.text.trim().isEmpty ? null : _resultType.text.trim(),
        allowedResults: _splitCsv(_allowedResults.text),
        active: _active,
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit test' : 'Add test'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          SwitchListTile(
            title: const Text('Active'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name *'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _short,
            decoration: const InputDecoration(labelText: 'Short name'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _category,
            decoration: const InputDecoration(
              labelText: 'Category',
              helperText: 'Example: special_test, outcome_measure',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _regions,
            decoration: const InputDecoration(
              labelText: 'Body regions (csv)',
              helperText:
                  'Example: cervical, shoulder, lumbar (use BodyRegion keys)',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _tags,
            decoration: const InputDecoration(
              labelText: 'Tags (csv)',
              helperText: 'Example: radiculopathy, provocation, common',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _instructions,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Instructions'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _positive,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Positive criteria'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _contra,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Contraindications'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _interpretation,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Interpretation'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _resultType,
            decoration: const InputDecoration(
              labelText: 'Result type',
              helperText: 'Default: ternary',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _allowedResults,
            decoration: const InputDecoration(
              labelText: 'Allowed results (csv)',
              helperText: 'Default: pos, neg, nt',
            ),
          ),
        ],
      ),
    );
  }
}

