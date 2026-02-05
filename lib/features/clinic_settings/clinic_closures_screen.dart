import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/clinic_context.dart';
import '../../data/repositories/clinic_repository.dart';
import '../../data/repositories/memberships_repository.dart';

class ClinicClosuresScreen extends StatefulWidget {
  const ClinicClosuresScreen({super.key});

  @override
  State<ClinicClosuresScreen> createState() => _ClinicClosuresScreenState();
}

class _ClinicClosuresScreenState extends State<ClinicClosuresScreen> {
  bool _creating = false;

  // ---------- Helpers ----------

  String _errMsg(Object e) {
    if (e is FirebaseFunctionsException) {
      final details = e.details == null ? '' : ' (${e.details})';
      return '${e.code}: ${e.message ?? ''}$details'.trim();
    }
    return e.toString();
  }

  static DateTime _tsToDt(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  // Simple formatting without intl dependency
  static String _fmt(DateTime dt) {
    return '${dt.year}-${_two(dt.month)}-${_two(dt.day)} ${_two(dt.hour)}:${_two(dt.minute)}';
  }

  Future<DateTime?> _pickDateTime({
    required BuildContext context,
    required DateTime initial,
  }) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null) return null;

    final time = await showTimePicker(
      // ignore: use_build_context_synchronously
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _openCreateDialog({
    required String clinicId,
    required ClinicRepository repo,
  }) async {
    if (_creating) return;

    final now = DateTime.now();
    DateTime fromAt = DateTime(now.year, now.month, now.day, 9, 0);
    DateTime toAt = DateTime(now.year, now.month, now.day, 17, 0);
    final reasonCtrl = TextEditingController();

    Future<void> pickFrom(StateSetter setModal) async {
      final picked = await _pickDateTime(context: context, initial: fromAt);
      if (picked == null) return;
      setModal(() {
        fromAt = picked;
        if (!toAt.isAfter(fromAt)) {
          toAt = fromAt.add(const Duration(hours: 1));
        }
      });
    }

    Future<void> pickTo(StateSetter setModal) async {
      final picked = await _pickDateTime(context: context, initial: toAt);
      if (picked == null) return;
      setModal(() {
        toAt = picked;
      });
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return AlertDialog(
              title: const Text('Add closure'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('From'),
                    subtitle: Text(_fmt(fromAt)),
                    trailing: const Icon(Icons.edit_calendar),
                    onTap: () => pickFrom(setModal),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('To'),
                    subtitle: Text(_fmt(toAt)),
                    trailing: const Icon(Icons.edit_calendar),
                    onTap: () => pickTo(setModal),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: reasonCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Reason (optional)',
                    ),
                    maxLength: 200,
                  ),
                  if (!toAt.isAfter(fromAt))
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        '“To” must be after “From”.',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: toAt.isAfter(fromAt)
                      ? () => Navigator.of(ctx).pop(true)
                      : null,
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != true) {
      reasonCtrl.dispose();
      return;
    }

    setState(() => _creating = true);
    try {
      await repo.createClosure(
        clinicId: clinicId,
        fromAt: fromAt,
        toAt: toAt,
        reason: reasonCtrl.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Closure created')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Create failed: ${_errMsg(e)}')),
      );
    } finally {
      reasonCtrl.dispose();
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _deleteClosure({
    required String clinicId,
    required String closureId,
    required ClinicRepository repo,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete closure?'),
        content: const Text('This will deactivate the closure (soft delete).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await repo.deleteClosure(clinicId: clinicId, closureId: closureId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Closure deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: ${_errMsg(e)}')),
      );
    }
  }

  // ---------- Self-check UI ----------

  Widget _selfCheckCard({
    required String clinicId,
    required String uid,
  }) {
    final membershipsRepo = context.watch<MembershipsRepository>();

    return StreamBuilder<Map<String, dynamic>?>(
      stream: membershipsRepo.watchClinicMemberDoc(clinicId: clinicId, uid: uid),
      builder: (context, snap) {
        final exists = snap.hasData && snap.data != null;
        final data = snap.data ?? const <String, dynamic>{};

        final active = data['active'] == true;
        final permsRaw = (data['permissions'] is Map)
            ? Map<String, dynamic>.from(data['permissions'] as Map)
            : <String, dynamic>{};

        final settingsWrite = permsRaw['settings.write'] == true;
        final settingsRead = permsRaw['settings.read'] == true;

        final permKeys = permsRaw.keys.toList()..sort();

        Color dot(bool ok) => ok ? Colors.green : Colors.red;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Self-check',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),

                Text('clinicId: $clinicId'),
                Text('uid: $uid'),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Icon(Icons.circle, size: 10, color: dot(exists)),
                    const SizedBox(width: 8),
                    Text(exists ? 'Member doc found' : 'Member doc NOT found'),
                  ],
                ),
                const SizedBox(height: 6),

                Row(
                  children: [
                    Icon(Icons.circle, size: 10, color: dot(active)),
                    const SizedBox(width: 8),
                    Text('active: $active'),
                  ],
                ),
                const SizedBox(height: 6),

                Row(
                  children: [
                    Icon(Icons.circle, size: 10, color: dot(settingsRead)),
                    const SizedBox(width: 8),
                    Text('settings.read: $settingsRead'),
                  ],
                ),
                const SizedBox(height: 6),

                Row(
                  children: [
                    Icon(Icons.circle, size: 10, color: dot(settingsWrite)),
                    const SizedBox(width: 8),
                    Text('settings.write: $settingsWrite'),
                  ],
                ),

                if (!exists)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'Fix: ensure clinics/{clinicId}/members/{uid} exists.',
                      style: TextStyle(fontSize: 12),
                    ),
                  )
                else if (!active)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'Fix: set member.active = true.',
                      style: TextStyle(fontSize: 12),
                    ),
                  )
                else if (!settingsWrite)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'Fix: set member.permissions["settings.write"] = true.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),

                if (permKeys.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Permission keys on member doc:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: permKeys
                        .map((k) => Chip(
                              label: Text(k, style: const TextStyle(fontSize: 12)),
                              visualDensity: VisualDensity.compact,
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final clinicCtx = context.watch<ClinicContext>();
    if (!clinicCtx.hasClinic) {
      return const Scaffold(
        body: Center(child: Text('No clinic selected')),
      );
    }

    final clinicId = clinicCtx.clinicId;
    final repo = context.read<ClinicRepository>();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Not signed in')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Closures'),
        actions: [
          IconButton(
            tooltip: 'Add closure',
            icon: _creating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
            onPressed: _creating
                ? null
                : () => _openCreateDialog(clinicId: clinicId, repo: repo),
          ),
        ],
      ),
      body: Column(
        children: [
          // ✅ Self-check panel at top
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _selfCheckCard(clinicId: clinicId, uid: uid),
          ),
          const SizedBox(height: 8),

          // Closures list
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: repo.watchActiveClosures(clinicId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const Center(
                    child: Text('No closures yet. Tap + to add one.'),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final data = d.data();

                    final fromAt = _tsToDt(data['fromAt']);
                    final toAt = _tsToDt(data['toAt']);
                    final reason = (data['reason'] ?? '').toString().trim();

                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.block),
                        title: Text('${_fmt(fromAt)} → ${_fmt(toAt)}'),
                        subtitle: reason.isEmpty ? null : Text(reason),
                        trailing: IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _deleteClosure(
                            clinicId: clinicId,
                            closureId: d.id,
                            repo: repo,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
