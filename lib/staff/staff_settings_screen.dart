// lib/staff/staff_settings_screen.dart
//
// Staff list + invite + open profile + suspend/edit. Used in two places:
// - Settings → Team → Members (embedded: true, no AppBar).
// - Clinic profile → Staff tile (embedded: false, full screen with AppBar).
// Legacy entrypoint: Clinic profile → Staff. Remove when Settings → Team has
// invite (09), practitioner profile (10), suspend/edit, and smoke tests (19) done.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/app/callable_error_mapping.dart';
import '/app/clinic_context.dart';
import '/data/repositories/staff_repository.dart';
import '/features/auth/permission_guard.dart';
import '/staff/invite_staff_form.dart';
import '/staff/screens/staff_member_screen.dart';
import '/staff/team_member_display_helpers.dart';

class StaffSettingsScreen extends StatefulWidget {
  const StaffSettingsScreen({
    super.key,
    this.embedded = false,
    this.enableRowTap = true,
  });

  /// When true, used inside Settings → Team → Members: no AppBar (Settings shell provides header).
  /// When false, standalone (e.g. from Clinic profile): full Scaffold with AppBar.
  final bool embedded;
  /// When true, tapping a row opens StaffMemberScreen (Commit 10). Legacy can set false if needed.
  final bool enableRowTap;

  @override
  State<StaffSettingsScreen> createState() => _StaffSettingsScreenState();
}

class _StaffSettingsScreenState extends State<StaffSettingsScreen> {
  Future<void> _showInviteDialog(BuildContext context, String clinicId) async {
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Invite staff member'),
          content: InviteStaffForm(
            clinicId: clinicId,
            onSuccess: (sent, inviteLink) {
              if (ctx.mounted) Navigator.of(ctx).pop(ctx);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    sent
                        ? 'Invite email sent.'
                        : 'Invite created but email not sent. Share the invite link with the recipient.',
                  ),
                ),
              );
              if (!sent && (inviteLink ?? '').isNotEmpty) {
                debugPrint('Invite link (share with recipient): $inviteLink');
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _toggleStatus({
    required String clinicId,
    required String memberUid,
    required String currentStatus,
  }) async {
    final repo = context.read<StaffRepository>();

    final next = currentStatus == 'active' ? 'suspended' : 'active';

    try {
      await repo.setMembershipStatus(
        clinicId: clinicId,
        memberUid: memberUid,
        status: next,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Status updated to $next')),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messageForCallableError(e, fallback: 'Failed to update status.'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messageForCallableError(e, fallback: 'Failed to update status.'))),
      );
    }
  }

  Future<void> _showEditProfileDialog({
    required BuildContext context,
    required String clinicId,
    required String memberUid,
    required String initialDisplayName,
    required String fallbackLabel,
  }) async {
    final repo = context.read<StaffRepository>();

    final nameCtrl = TextEditingController(text: initialDisplayName);
    String? error;
    bool loading = false;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setD) {
          Future<void> submit() async {
            final messenger = ScaffoldMessenger.of(context);
            final name = nameCtrl.text.trim();
            if (name.isEmpty) {
              setD(() => error = 'Display name cannot be empty.');
              return;
            }

            setD(() {
              error = null;
              loading = true;
            });

            try {
              await repo.updateMemberDisplayName(
                clinicId: clinicId,
                memberUid: memberUid,
                displayName: name,
              );

              if (ctx.mounted) Navigator.of(ctx).pop();
              if (!mounted) return;

              messenger.showSnackBar(
                const SnackBar(content: Text('✅ Staff display name updated')),
              );
            } catch (e) {
              setD(() => error = e.toString());
            } finally {
              setD(() => loading = false);
            }
          }

          return AlertDialog(
            title: const Text('Edit staff display name'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fallbackLabel,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    hintText: 'e.g. Graeme Lawson',
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: loading ? null : () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: loading ? null : submit,
                child: loading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          );
        });
      },
    );
  }

  void _openMember(BuildContext context, String clinicId, String uid) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StaffMemberScreen(
          clinicId: clinicId,
          memberUid: uid,
          embeddedInSettings: widget.embedded,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clinicCtx = context.watch<ClinicContext>();
    final clinicId = clinicCtx.hasClinic ? clinicCtx.clinicId : '';

    final guard = PermissionGuard(clinicCtx.permissions);
    final canManage = guard.has('members.manage');
    final canRead = guard.has('members.read') || canManage;

    final repo = context.read<StaffRepository>();

    final body = clinicId.trim().isEmpty
        ? const Center(child: Text('No clinic selected.'))
        : !canRead
            ? const Center(
                child: Text(
                  'You don\'t have permission to view team members (members.read required).',
                ),
              )
            : StreamBuilder<
                List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                // Merge: canonical members/{uid} wins over memberships/{uid}; no duplicates (see StaffRepository.watchMembershipsWithFallback).
                stream: repo.watchMembershipsWithFallback(clinicId),
                builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(child: Text('Error: ${snap.error}'));
                    }
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final docs = snap.data ??
                        const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                    if (docs.isEmpty) {
                      return const Center(child: Text('No staff yet.'));
                    }

                    return ListView.separated(
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final d = docs[i];
                        final data = d.data();

                        final uid = d.id;

                        final roleId = (data['role'] ?? data['roleId'] ?? '')
                            .toString()
                            .trim();
                        final roleName = (data['roleName'] ?? '').toString().trim();
                        final roleLabel = roleDisplayLabel(roleId: roleId, roleName: roleName.isEmpty ? null : roleName);

                        final status = (data['status'] ?? '').toString().trim();
                        final activeBool = data['active'] == true;
                        final effectiveStatus = status.isNotEmpty
                            ? status
                            : (activeBool ? 'active' : 'suspended');
                        final statusLabel = statusDisplayLabel(status: effectiveStatus, active: activeBool);

                        final invitedEmail =
                            (data['invitedEmail'] ?? data['email'] ?? '')
                                .toString()
                                .trim();

                        final displayName = (data['displayName'] ??
                                data['fullName'] ??
                                data['name'] ??
                                '')
                            .toString()
                            .trim();

                        final titleText = displayName.isNotEmpty
                            ? displayName
                            : (invitedEmail.isNotEmpty ? invitedEmail : uid);

                        final subtitleBits = <String>[
                          if (roleLabel.isNotEmpty) 'Role: $roleLabel',
                          'Status: $statusLabel',
                          if (invitedEmail.isNotEmpty) 'Email: $invitedEmail',
                        ];

                        final fallbackLabel =
                            invitedEmail.isNotEmpty ? invitedEmail : uid;

                        return ListTile(
                          title: Text(titleText),
                          subtitle: Text(subtitleBits.join(' • ')),

                          onTap: widget.enableRowTap
                              ? () => _openMember(context, clinicId, uid)
                              : null,

                          trailing: canManage
                              ? PopupMenuButton<String>(
                                  onSelected: (v) {
                                    if (v == 'open') {
                                      _openMember(context, clinicId, uid);
                                    }
                                    if (v == 'editName') {
                                      _showEditProfileDialog(
                                        context: context,
                                        clinicId: clinicId,
                                        memberUid: uid,
                                        initialDisplayName:
                                            displayName.isNotEmpty
                                                ? displayName
                                                : titleText,
                                        fallbackLabel:
                                            'Account: $fallbackLabel',
                                      );
                                    }
                                    if (v == 'toggle') {
                                      _toggleStatus(
                                        clinicId: clinicId,
                                        memberUid: uid,
                                        currentStatus: effectiveStatus, // internal value for API
                                      );
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'open',
                                      child: Text('Open profile'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'editName',
                                      child: Text('Edit display name'),
                                    ),
                                    PopupMenuItem(
                                      value: 'toggle',
                                      child: Text(
                                        effectiveStatus == 'active'
                                            ? 'Suspend'
                                            : 'Reactivate',
                                      ),
                                    ),
                                  ],
                                )
                              : null,
                        );
                      },
                    );
                  },
                );

    if (widget.embedded) {
      return Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (canManage && clinicId.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Team members',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    IconButton.filled(
                      onPressed: () => _showInviteDialog(context, clinicId),
                      icon: const Icon(Icons.person_add, size: 20),
                      tooltip: 'Invite staff',
                    ),
                  ],
                ),
              ),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff'),
        actions: [
          IconButton(
            onPressed: (!canManage || clinicId.trim().isEmpty)
                ? null
                : () => _showInviteDialog(context, clinicId),
            icon: const Icon(Icons.person_add),
            tooltip: 'Invite staff',
          ),
        ],
      ),
      body: body,
    );
  }
}
