import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/clinic_context.dart';
import '../../models/membership_index.dart';
import '../../app/last_clinic_store.dart';

class HomePage extends StatelessWidget {
  final List<MembershipIndex> memberships;
  final Future<void> Function(String clinicId) onPick;

  const HomePage({
    super.key,
    required this.memberships,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    // ✅ Safer default: don’t show invited/suspended clinics in picker
    final visible = memberships.where((m) => m.active == true).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select clinic'),
        actions: [
          IconButton(
            onPressed: () async {
              final uid = user?.uid;
              await FirebaseAuth.instance.signOut();
              if (!context.mounted) return;
              context.read<ClinicContext>().clear();
              if (uid != null) await LastClinicStore.clearLastClinic(uid);
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: visible.isEmpty
          ? const Center(child: Text('No active clinics yet.'))
          : ListView.separated(
              itemCount: visible.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final m = visible[i];
                final title = (m.clinicNameCache?.trim().isNotEmpty == true)
                    ? m.clinicNameCache!.trim()
                    : m.clinicId;

                final status = (m.status ?? '').trim();
                final subtitleParts = <String>[
                  'Role: ${m.roleId}',
                  if (status.isNotEmpty) 'Status: $status',
                ];

                return ListTile(
                  title: Text(title),
                  subtitle: Text(subtitleParts.join(' • ')),
                  onTap: () async {
                    await onPick(m.clinicId);
                  },
                );
              },
            ),
    );
  }
}
