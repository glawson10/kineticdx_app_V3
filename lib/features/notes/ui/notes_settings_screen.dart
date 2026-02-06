import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/clinic_context.dart';
import '../data/notes_paths.dart';
import '../data/notes_permissions.dart';
import '../data/notes_templates.dart';

class NotesSettingsScreen extends StatelessWidget {
  final String clinicId;

  const NotesSettingsScreen({super.key, required this.clinicId});

  @override
  Widget build(BuildContext context) {
    final clinicCtx = context.watch<ClinicContext>();
    if (!clinicCtx.hasSession) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final perms = clinicCtx.session.permissions;
    final canRead = canViewClinicalNotes(perms);
    final canManage = canManageNotesSettings(perms);

    if (!canRead) {
      return const Scaffold(
        body: Center(child: Text('No access to notes settings.')),
      );
    }

    final docRef = clinicNotesSettingsDoc(FirebaseFirestore.instance, clinicId);

    return Scaffold(
      appBar: AppBar(title: const Text('Notes settings')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docRef.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final settings = snap.data!.exists
              ? NotesSettings.fromMap(snap.data!.data())
              : NotesSettings.fallback();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!snap.data!.exists)
                const _InfoBanner(
                  message:
                      'Notes settings doc not found. Using default template.',
                ),
              const SizedBox(height: 8),
              for (final t in settings.templates)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(t.name),
                    subtitle: Text('id: ${t.id} • type: ${t.type}'),
                    trailing: t.isDefault
                        ? const Chip(label: Text('Default'))
                        : null,
                  ),
                ),
              if (settings.templates.isEmpty)
                const Center(child: Text('No templates configured.')),
              const SizedBox(height: 8),
              if (!canManage)
                const Text(
                  'Read-only. Manage templates requires settings.write.',
                  style: TextStyle(color: Colors.grey),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final String message;

  const _InfoBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(message),
      ),
    );
  }
}
