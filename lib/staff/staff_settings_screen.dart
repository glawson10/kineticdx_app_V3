// lib/staff/staff_settings_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/app/callable_error_mapping.dart';
import '/app/clinic_context.dart';
import '/data/repositories/staff_repository.dart';
import '/features/auth/permission_guard.dart';
import '/staff/screens/staff_member_screen.dart';

class StaffSettingsScreen extends StatefulWidget {
  const StaffSettingsScreen({super.key});

  @override
  State<StaffSettingsScreen> createState() => _StaffSettingsScreenState();
}

class _StaffSettingsScreenState extends State<StaffSettingsScreen> {
  Future<void> _showInviteDialog(BuildContext context, String clinicId) async {
    final repo = context.read<StaffRepository>();

    final emailCtrl = TextEditingController();
    String roleId = 'reception';

    String? error;
    bool loading = false;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setD) {
          Future<void> submit() async {
            final messenger = ScaffoldMessenger.of(context);
            final email = emailCtrl.text.trim().toLowerCase();
            if (email.isEmpty || !email.contains('@')) {
              setD(() => error = 'Enter a valid email.');
              return;
            }
            if (roleId.trim().isEmpty) {
              setD(() => error = 'Pick a role.');
              return;
            }

            setD(() {
              error = null;
              loading = true;
            });

            try {
              final data = await repo.inviteMember(
                clinicId: clinicId,
                email: email,
                roleId: roleId,
              );

              final sent = data['sent'] == true;
              final inviteLink = (data['inviteLink'] ?? data['token'] ?? '').toString();

              if (ctx.mounted) Navigator.of(ctx).pop();
              if (!mounted) return;

              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    sent
                        ? 'Invite email sent.'
                        : 'Invite created but email not sent. Share the invite link with the recipient.',
                  ),
                ),
              );
              if (!sent && inviteLink.isNotEmpty) {
                debugPrint('Invite link (share with recipient): $inviteLink');
              }
            } on FirebaseFunctionsException catch (e) {
              setD(() => error = messageForCallableError(e, fallback: 'Failed to send invite.'));
            } catch (e) {
              setD(() => error = messageForCallableError(e, fallback: 'Failed to send invite.'));
            } finally {
              setD(() => loading = false);
            }
          }

          return AlertDialog(
            title: const Text('Invite staff member'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: roleId,
                  items: const [
                    DropdownMenuItem(value: 'owner', child: Text('Owner')),
                    DropdownMenuItem(value: 'manager', child: Text('Manager')),
                    DropdownMenuItem(value: 'clinician', child: Text('Clinician')),
                    DropdownMenuItem(value: 'reception', child: Text('Reception')),
                    DropdownMenuItem(value: 'billing', child: Text('Billing')),
                    DropdownMenuItem(value: 'readOnly', child: Text('Read only')),
                  ],
                  onChanged: (v) => setD(() => roleId = v ?? roleId),
                  decoration: const InputDecoration(labelText: 'Role'),
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
                    : const Text('Send invite'),
              ),
            ],
          );
        });
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

  void _openStaffMember({
    required BuildContext context,
    required String memberUid,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StaffMemberScreen(memberUid: memberUid),
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
      body: clinicId.trim().isEmpty
          ? const Center(child: Text('No clinic selected.'))
          : !canRead
              ? const Center(
                  child: Text('You do not have permission to view staff.'),
                )
              : StreamBuilder<
                  List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
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

                        final role = (data['role'] ?? data['roleId'] ?? '')
                            .toString()
                            .trim();

                        final status = (data['status'] ?? '').toString().trim();
                        final activeBool = data['active'] == true;

                        final effectiveStatus = status.isNotEmpty
                            ? status
                            : (activeBool ? 'active' : 'suspended');

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
                          if (role.isNotEmpty) 'Role: $role',
                          'Status: $effectiveStatus',
                          if (invitedEmail.isNotEmpty) 'Email: $invitedEmail',
                        ];

                        final fallbackLabel =
                            invitedEmail.isNotEmpty ? invitedEmail : uid;

                        return ListTile(
                          title: Text(titleText),
                          subtitle: Text(subtitleBits.join(' • ')),

                          // ✅ tap opens StaffMemberScreen (tabs)
                          onTap: () => _openStaffMember(
                            context: context,
                            memberUid: uid,
                          ),

                          trailing: canManage
                              ? PopupMenuButton<String>(
                                  onSelected: (v) {
                                    if (v == 'open') {
                                      _openStaffMember(
                                        context: context,
                                        memberUid: uid,
                                      );
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
                                        currentStatus: effectiveStatus,
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
                ),
    );
  }
}
