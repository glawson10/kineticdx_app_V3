import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/clinic_context.dart';
import '../../../models/clinic_permissions.dart';
import '../../../models/patient.dart';
import '../data/clinical_note.dart';
import '../data/notes_paths.dart';
import '../data/notes_permissions.dart';
import '../data/notes_templates.dart';

class NoteEditorScreen extends StatefulWidget {
  final String clinicId;
  final String patientId;
  final String? noteId;
  final String? appointmentId;
  final String? relatedIntakeSessionId;

  const NoteEditorScreen({
    super.key,
    required this.clinicId,
    required this.patientId,
    required this.noteId,
    this.appointmentId,
    this.relatedIntakeSessionId,
  });

  factory NoteEditorScreen.create({
    required String clinicId,
    required String patientId,
    String? appointmentId,
    String? relatedIntakeSessionId,
  }) {
    return NoteEditorScreen(
      clinicId: clinicId,
      patientId: patientId,
      noteId: null,
      appointmentId: appointmentId,
      relatedIntakeSessionId: relatedIntakeSessionId,
    );
  }

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final _subjective = TextEditingController();
  final _objective = TextEditingController();
  final _assessment = TextEditingController();
  final _plan = TextEditingController();

  String? _noteId;
  ClinicalNote? _note;
  bool _loadedOnce = false;
  bool _saving = false;

  NotesSettings? _settings;
  NotesTemplate? _selectedTemplate;
  String _selectedType = 'initial';

  final Map<String, String> _memberNameCache = {};
  final Map<String, bool> _memberLookupInFlight = {};

  @override
  void initState() {
    super.initState();
    _noteId = widget.noteId;
    _loadSettings();

    if (_noteId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _selectTemplateIfNeeded();
      });
    }
  }

  @override
  void dispose() {
    _subjective.dispose();
    _objective.dispose();
    _assessment.dispose();
    _plan.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    if (_settings != null) return;
    try {
      final doc = await clinicNotesSettingsDoc(_db, widget.clinicId).get();
      if (doc.exists) {
        _settings = NotesSettings.fromMap(doc.data());
      } else {
        _settings = NotesSettings.fallback();
      }
    } catch (_) {
      _settings = NotesSettings.fallback();
    }
    if (mounted) setState(() {});
  }

  NotesTemplate _templateForId(String templateId) {
    final settings = _settings;
    if (settings == null) return NotesSettings.defaultTemplate;
    for (final t in settings.templates) {
      if (t.id == templateId) return t;
    }
    if (templateId == NotesSettings.defaultTemplate.id) {
      return NotesSettings.defaultTemplate;
    }
    return NotesTemplate(
      id: templateId,
      name: templateId,
      type: 'soap',
      isDefault: false,
    );
  }

  Future<void> _selectTemplateIfNeeded() async {
    if (_noteId != null) return;
    if (_selectedTemplate != null) return;

    await _loadSettings();
    final settings = _settings ?? NotesSettings.fallback();
    final defaultTemplate = settings.pickDefaultTemplate();

    final result = await showDialog<_TemplateSelectionResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _TemplateSelectionDialog(
        templates: settings.templates,
        initialTemplate: defaultTemplate,
        initialType: _selectedType,
      ),
    );

    if (!mounted) return;
    if (result == null) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _selectedTemplate = result.template;
      _selectedType = result.type;
    });
  }

  Future<void> _ensureMemberName(String clinicId, String uid) async {
    final u = uid.trim();
    if (u.isEmpty) return;
    if (_memberNameCache.containsKey(u)) return;
    if (_memberLookupInFlight[u] == true) return;

    _memberLookupInFlight[u] = true;
    try {
      final memberDoc = await _db
          .collection('clinics')
          .doc(clinicId)
          .collection('members')
          .doc(u)
          .get();

      String? displayName;
      if (memberDoc.exists) {
        final data = memberDoc.data() ?? const <String, dynamic>{};
        displayName = (data['displayName'] ?? data['name'] ?? '').toString();
      }

      if (displayName == null || displayName.trim().isEmpty) {
        final legacyDoc = await _db
            .collection('clinics')
            .doc(clinicId)
            .collection('memberships')
            .doc(u)
            .get();
        if (legacyDoc.exists) {
          final data = legacyDoc.data() ?? const <String, dynamic>{};
          displayName = (data['displayName'] ?? data['name'] ?? '').toString();
        }
      }

      setState(() {
        _memberNameCache[u] = (displayName ?? '').trim();
      });
    } catch (_) {
      setState(() {
        _memberNameCache[u] = '';
      });
    } finally {
      _memberLookupInFlight[u] = false;
    }
  }

  String _displayNameFor(String uid) {
    final v = _memberNameCache[uid];
    if (v != null && v.trim().isNotEmpty) return v.trim();
    return uid.length <= 10 ? uid : '${uid.substring(0, 10)}...';
  }

  String _patientName(Patient p) {
    final n = '${p.firstName} ${p.lastName}'.trim();
    return n.isEmpty ? 'Unnamed patient' : n;
  }

  bool _isReadOnly(ClinicPermissions perms, ClinicalNote? note) {
    if (!canEditClinicalNotes(perms)) return true;
    if (note == null) return false;
    return note.status == 'final';
  }

  @override
  Widget build(BuildContext context) {
    final clinicCtx = context.watch<ClinicContext>();
    if (!clinicCtx.hasSession) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final perms = clinicCtx.session.permissions;
    final canView = canViewClinicalNotes(perms);
    if (!canView) {
      return const Scaffold(body: Center(child: Text('No access to notes.')));
    }

    final patientDoc = _db
        .collection('clinics')
        .doc(widget.clinicId)
        .collection('patients')
        .doc(widget.patientId)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: patientDoc,
      builder: (context, patientSnap) {
        if (patientSnap.hasError) {
          return Scaffold(body: Center(child: Text('Error: ${patientSnap.error}')));
        }
        if (!patientSnap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final patientData = patientSnap.data!.data() ?? const <String, dynamic>{};
        final patient = Patient.fromFirestore(widget.patientId, patientData);
        final patientName = _patientName(patient);

        if (_noteId == null) {
          final readOnly = _isReadOnly(perms, null);
          return _buildEditorScaffold(
            patientName: patientName,
            note: null,
            readOnly: readOnly,
          );
        }

        final noteDoc = clinicClinicalNoteDoc(_db, widget.clinicId, _noteId!);
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: noteDoc.snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Scaffold(body: Center(child: Text('Error: ${snap.error}')));
            }
            if (!snap.hasData) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }
            if (!snap.data!.exists) {
              return const Scaffold(body: Center(child: Text('Note not found.')));
            }

            final note = ClinicalNote.fromFirestore(
              snap.data!.id,
              snap.data!.data() ?? const <String, dynamic>{},
            );

            if (!_loadedOnce) {
              _loadedOnce = true;
              _note = note;
              _subjective.text = note.soap.subjective;
              _objective.text = note.soap.objective;
              _assessment.text = note.soap.assessment;
              _plan.text = note.soap.plan;
            }

            final updatedBy = (note.updatedByUid ?? note.createdByUid).trim();
            if (updatedBy.isNotEmpty) {
              _ensureMemberName(widget.clinicId, updatedBy);
            }

            final readOnly = _isReadOnly(perms, note);
            return _buildEditorScaffold(
              patientName: patientName,
              note: note,
              readOnly: readOnly,
            );
          },
        );
      },
    );
  }

  Scaffold _buildEditorScaffold({
    required String patientName,
    required ClinicalNote? note,
    required bool readOnly,
  }) {
    final noteType = note?.type ?? _selectedType;
    final templateId = note?.templateId ?? _selectedTemplate?.id ?? 'basicSoap';
    final templateName = _templateForId(templateId).name;

    final updatedByUid = note?.updatedByUid ?? note?.createdByUid ?? '';
    final updatedByName =
        updatedByUid.isNotEmpty ? _displayNameFor(updatedByUid) : '--';

    final createdAtLabel = _formatDateTime(note?.createdAt);
    final updatedAtLabel = _formatDateTime(note?.updatedAt);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinical note'),
        actions: [
          IconButton(
            tooltip: 'Mark final (stub)',
            icon: const Icon(Icons.check_circle_outline),
            onPressed: readOnly ? null : _markFinalStub,
          ),
          IconButton(
            tooltip: 'Save',
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            onPressed: (readOnly || _saving) ? null : () => _save(note),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HeaderCard(
            patientName: patientName,
            noteType: _typeLabel(noteType),
            templateName: templateName,
            createdAt: createdAtLabel,
            updatedAt: updatedAtLabel,
            updatedBy: updatedByName,
          ),
          const SizedBox(height: 12),
          _SectionField(
            label: 'Subjective',
            controller: _subjective,
            readOnly: readOnly,
          ),
          _SectionField(
            label: 'Objective',
            controller: _objective,
            readOnly: readOnly,
          ),
          _SectionField(
            label: 'Assessment',
            controller: _assessment,
            readOnly: readOnly,
          ),
          _SectionField(
            label: 'Plan',
            controller: _plan,
            readOnly: readOnly,
          ),
          const SizedBox(height: 12),
          if (readOnly)
            const Text(
              'Read-only: you do not have edit permission for notes.',
              style: TextStyle(color: Colors.grey),
            ),
        ],
      ),
    );
  }

  Future<void> _save(ClinicalNote? existing) async {
    final clinicCtx = context.read<ClinicContext>();
    final uid = clinicCtx.uidOrNull?.trim() ?? '';
    if (uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing user identity.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final soap = SoapPayload(
        subjective: _subjective.text.trim(),
        objective: _objective.text.trim(),
        assessment: _assessment.text.trim(),
        plan: _plan.text.trim(),
      );

      if (_noteId == null) {
        final doc = clinicClinicalNotesCollection(_db, widget.clinicId).doc();
        final templateId = _selectedTemplate?.id ?? 'basicSoap';
        final appointmentId = (widget.appointmentId ?? '').trim();
        final intakeId = (widget.relatedIntakeSessionId ?? '').trim();
        final data = <String, dynamic>{
          'schemaVersion': 1,
          'clinicId': widget.clinicId,
          'patientId': widget.patientId,
          'appointmentId': appointmentId.isEmpty ? null : appointmentId,
          'type': _selectedType,
          'templateId': templateId,
          'status': 'draft',
          'soap': soap.toMap(),
          'relatedIntakeSessionId': intakeId.isEmpty ? null : intakeId,
          'createdByUid': uid,
          'updatedByUid': uid,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        await doc.set(data);
        setState(() {
          _noteId = doc.id;
          _loadedOnce = false;
        });
      } else {
        final doc = clinicClinicalNoteDoc(_db, widget.clinicId, _noteId!);
        await doc.update({
          'soap': soap.toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedByUid': uid,
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _markFinalStub() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Finalization is not available in v1.')),
    );
  }

  String _typeLabel(String raw) {
    switch (raw) {
      case 'followup':
        return 'Follow up';
      case 'initial':
      default:
        return 'Initial';
    }
  }

  String _formatDateTime(DateTime? d) {
    if (d == null) return '--';
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$y-$m-$day $hh:$mm';
  }
}

class _TemplateSelectionResult {
  final NotesTemplate template;
  final String type;

  _TemplateSelectionResult({required this.template, required this.type});
}

class _TemplateSelectionDialog extends StatefulWidget {
  final List<NotesTemplate> templates;
  final NotesTemplate initialTemplate;
  final String initialType;

  const _TemplateSelectionDialog({
    required this.templates,
    required this.initialTemplate,
    required this.initialType,
  });

  @override
  State<_TemplateSelectionDialog> createState() =>
      _TemplateSelectionDialogState();
}

class _TemplateSelectionDialogState extends State<_TemplateSelectionDialog> {
  late NotesTemplate _template;
  late String _type;

  @override
  void initState() {
    super.initState();
    _template = widget.initialTemplate;
    _type = widget.initialType;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New note'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            value: _type,
            decoration: const InputDecoration(labelText: 'Note type'),
            items: const [
              DropdownMenuItem(value: 'initial', child: Text('Initial')),
              DropdownMenuItem(value: 'followup', child: Text('Follow up')),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _type = v);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<NotesTemplate>(
            value: _template,
            decoration: const InputDecoration(labelText: 'Template'),
            items: [
              for (final t in widget.templates)
                DropdownMenuItem(
                  value: t,
                  child: Text(t.name),
                ),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _template = v);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop<_TemplateSelectionResult>(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop<_TemplateSelectionResult>(
            _TemplateSelectionResult(template: _template, type: _type),
          ),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final String patientName;
  final String noteType;
  final String templateName;
  final String createdAt;
  final String updatedAt;
  final String updatedBy;

  const _HeaderCard({
    required this.patientName,
    required this.noteType,
    required this.templateName,
    required this.createdAt,
    required this.updatedAt,
    required this.updatedBy,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              patientName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text('Type: $noteType'),
            Text('Template: $templateName'),
            const SizedBox(height: 6),
            Text('Created: $createdAt'),
            Text('Updated: $updatedAt'),
            Text('Updated by: $updatedBy'),
          ],
        ),
      ),
    );
  }
}

class _SectionField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool readOnly;

  const _SectionField({
    required this.label,
    required this.controller,
    required this.readOnly,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        maxLines: 6,
        minLines: 3,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
