import 'package:flutter/material.dart';

import '../../../../data/repositories/clinic_registry_repository.dart';
import '../../../../models/outcome_measure.dart';

class EditOutcomeMeasureScreen extends StatefulWidget {
  final String clinicId;
  final OutcomeMeasure? existing;

  const EditOutcomeMeasureScreen({
    super.key,
    required this.clinicId,
    required this.existing,
  });

  @override
  State<EditOutcomeMeasureScreen> createState() => _EditOutcomeMeasureScreenState();
}

class _EditOutcomeMeasureScreenState extends State<EditOutcomeMeasureScreen> {
  final _repo = ClinicRegistryRepository();

  final _name = TextEditingController();
  final _fullName = TextEditingController();
  final _tags = TextEditingController();
  final _scoreHint = TextEditingController();

  bool _active = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.name;
      _fullName.text = e.fullName ?? '';
      _tags.text = e.tags.join(', ');
      _scoreHint.text = e.scoreFormatHint ?? '';
      _active = e.active;
    } else {
      _active = true;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _fullName.dispose();
    _tags.dispose();
    _scoreHint.dispose();
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

      await _repo.upsertOutcomeMeasure(
        clinicId: widget.clinicId,
        measureId: widget.existing?.id,
        name: name,
        fullName: _fullName.text.trim().isEmpty ? null : _fullName.text.trim(),
        tags: _splitCsv(_tags.text),
        scoreFormatHint: _scoreHint.text.trim().isEmpty ? null : _scoreHint.text.trim(),
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
        title: Text(isEdit ? 'Edit measure' : 'Add measure'),
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
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          SwitchListTile(
            title: const Text('Active'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name * (e.g. NDI)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _fullName,
            decoration: const InputDecoration(labelText: 'Full name'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _scoreHint,
            decoration: const InputDecoration(
              labelText: 'Score format hint',
              helperText: 'Example: 0-50 (convert to % if needed)',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _tags,
            decoration: const InputDecoration(
              labelText: 'Tags (csv)',
              helperText: 'Example: cervical, function',
            ),
          ),
        ],
      ),
    );
  }
}
