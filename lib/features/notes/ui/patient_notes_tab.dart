import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../../../app/clinic_context.dart';
import '../data/clinical_note.dart';
import '../data/notes_paths.dart';
import '../data/notes_permissions.dart';
import '../data/notes_templates.dart';
import 'note_editor_screen.dart';
import 'soap_note_edit_screen.dart';

class PatientNotesTab extends StatefulWidget {
  final String clinicId;
  final String patientId;

  const PatientNotesTab({
    super.key,
    required this.clinicId,
    required this.patientId,
  });

  @override
  State<PatientNotesTab> createState() => _PatientNotesTabState();
}

class _PatientNotesTabState extends State<PatientNotesTab> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final Map<String, String> _memberNameCache = {};
  final Map<String, bool> _memberLookupInFlight = {};

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

      // Legacy fallback (if membership doc lives under /memberships)
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

  @override
  Widget build(BuildContext context) {
    final clinicCtx = context.watch<ClinicContext>();
    if (!clinicCtx.hasSession) {
      return const Center(child: CircularProgressIndicator());
    }
    final perms = clinicCtx.session.permissions;
    final canView = canViewClinicalNotes(perms);
    final canEdit = canEditClinicalNotes(perms);

    if (!canView) {
      return const Center(child: Text('No access to clinical notes.'));
    }

    final notesQuery = clinicClinicalNotesCollection(_db, widget.clinicId)
        .where('patientId', isEqualTo: widget.patientId)
        .orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: notesQuery.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final notes = snap.data!.docs
            .map((d) => ClinicalNote.fromFirestore(d.id, d.data()))
            .toList();

        if (notes.isEmpty) {
          return _EmptyNotesState(
            canCreate: canEdit,
            onCreate: canEdit ? () => _showCreateMenu(context) : null,
          );
        }

        for (final n in notes) {
          final uid = (n.updatedByUid ?? n.createdByUid).trim();
          if (uid.isNotEmpty) {
            _ensureMemberName(widget.clinicId, uid);
          }
        }

        return Scaffold(
          body: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: notes.length,
            itemBuilder: (context, index) {
              final note = notes[index];
              final authorUid = (note.updatedByUid ?? note.createdByUid).trim();
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(_typeLabel(note.type)),
                  subtitle: Text(
                    'Created ${_formatDate(note.createdAt)}'
                    ' • Updated ${_formatDate(note.updatedAt)}'
                    ' • ${_displayNameFor(authorUid)}',
                  ),
                  onTap: () => _openNote(context, note.id),
                ),
              );
            },
          ),
          floatingActionButton: canEdit
              ? FloatingActionButton(
                  onPressed: () => _createNote(context),
                  child: const Icon(Icons.note_add),
                )
              : null,
        );
      },
    );
  }

  Future<void> _openNote(BuildContext context, String noteId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(
          clinicId: widget.clinicId,
          noteId: noteId,
          patientId: widget.patientId,
        ),
      ),
    );
  }

  Future<void> _createNote(BuildContext context) async {
    final kind = await _loadDefaultInitialKind(context);
    if (kind == 'initialAssessment') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SoapNoteEditScreen(
            clinicId: widget.clinicId,
            patientId: widget.patientId,
            noteId: null,
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen.create(
          clinicId: widget.clinicId,
          patientId: widget.patientId,
        ),
      ),
    );
  }

  Future<void> _showCreateMenu(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Basic SOAP note'),
              subtitle: const Text('Free-text subjective, objective, assessment, plan'),
              onTap: () => Navigator.pop(ctx, 'basicSoap'),
            ),
            ListTile(
              leading: const Icon(Icons.assignment_outlined),
              title: const Text('Initial Assessment'),
              subtitle: const Text('Structured, region-specific initial assessment'),
              onTap: () => Navigator.pop(ctx, 'initialAssessment'),
            ),
            ListTile(
              leading: const Icon(Icons.cancel),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(ctx, null),
            ),
          ],
        ),
      ),
    );

    if (choice == 'basicSoap') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => NoteEditorScreen.create(
            clinicId: widget.clinicId,
            patientId: widget.patientId,
          ),
        ),
      );
    } else if (choice == 'initialAssessment') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SoapNoteEditScreen(
            clinicId: widget.clinicId,
            patientId: widget.patientId,
            noteId: null,
          ),
        ),
      );
    }
  }

  Future<String> _loadDefaultInitialKind(BuildContext context) async {
    try {
      final doc = await clinicNotesSettingsDoc(
        FirebaseFirestore.instance,
        widget.clinicId,
      ).get();
      if (!doc.exists) return 'basicSoap';
      final settings = NotesSettings.fromMap(doc.data());
      return settings.defaultInitialNoteKind;
    } catch (_) {
      return 'basicSoap';
    }
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

  String _formatDate(DateTime? d) {
    if (d == null) return '--';
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}

class _EmptyNotesState extends StatelessWidget {
  final bool canCreate;
  final VoidCallback? onCreate;

  const _EmptyNotesState({
    required this.canCreate,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'No notes yet',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            if (canCreate)
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.note_add),
                label: const Text('Create note'),
              ),
          ],
        ),
      ),
    );
  }
}
