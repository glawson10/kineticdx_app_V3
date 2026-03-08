// lib/staff/invite_staff_form.dart
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app/callable_error_mapping.dart';
import '../config/permission_keys.dart';
import '../data/repositories/staff_repository.dart';
import 'team_member_display_helpers.dart';
import 'team_settings_widgets.dart';

class InviteStaffForm extends StatefulWidget {
  const InviteStaffForm({
    super.key,
    required this.clinicId,
    required this.onSuccess,
    this.clearFormOnSuccess = false,
  });

  final String clinicId;
  final void Function(bool sent, String? inviteLink) onSuccess;
  final bool clearFormOnSuccess;

  @override
  State<InviteStaffForm> createState() => _InviteStaffFormState();
}

class _InviteStaffFormState extends State<InviteStaffForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtl = TextEditingController();

  String _roleId = RoleTemplateIds.practitioner;
  bool _sending = false;
  String? _error;
  bool? _lastSent;
  String? _lastInviteLink;

  @override
  void dispose() {
    _emailCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending) return;
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final result = await context.read<StaffRepository>().inviteMember(
            clinicId: widget.clinicId,
            email: _emailCtl.text.trim(),
            roleId: _roleId,
          );

      final sent = result['sent'] == true;
      final inviteLink = (result['inviteLink'] ?? '').toString().trim();

      if (!mounted) return;
      setState(() {
        _lastSent = sent;
        _lastInviteLink = inviteLink.isEmpty ? null : inviteLink;
      });

      if (widget.clearFormOnSuccess) {
        _emailCtl.clear();
        setState(() => _roleId = RoleTemplateIds.practitioner);
      }

      widget.onSuccess(sent, inviteLink.isEmpty ? null : inviteLink);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = messageForCallableError(
          e,
          fallback: 'Failed to send invite.',
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = messageForCallableError(
          e,
          fallback: 'Failed to send invite.',
        );
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roleMeta = _roleMeta[_roleId]!;
    final preview = permissionDisplayFromKeys(roleMeta.permissionPreview);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _emailCtl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Email address',
              hintText: 'name@clinic.com',
              prefixIcon: Icon(Icons.mail_outline),
            ),
            validator: (value) {
              final email = (value ?? '').trim().toLowerCase();
              if (email.isEmpty) return 'Enter an email address.';
              final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
              if (!ok) return 'Enter a valid email address.';
              return null;
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _roleId,
            decoration: const InputDecoration(
              labelText: 'Role',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
            items: _roleMeta.entries
                .map(
                  (entry) => DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(entry.value.label),
                  ),
                )
                .toList(),
            onChanged: _sending
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() => _roleId = value);
                  },
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    TeamMetadataChip(
                      label: roleMeta.label,
                      icon: roleMeta.icon,
                      tone: TeamChipTone.info,
                    ),
                    const SizedBox(width: 8),
                    if (roleMeta.bookable)
                      const TeamMetadataChip(
                        label: 'Shows in calendar',
                        icon: Icons.calendar_month_outlined,
                        tone: TeamChipTone.success,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  roleMeta.description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final label in preview.displayLabels)
                      TeamMetadataChip(label: label),
                    if (preview.overflowCount > 0)
                      TeamMetadataChip(
                        label: '+${preview.overflowCount} more',
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (_lastInviteLink != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _lastSent == true
                        ? 'Invite sent successfully'
                        : 'Invite created - share this link manually',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _lastInviteLink!,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: _lastInviteLink!),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Invite link copied'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_all_outlined),
                      label: const Text('Copy link'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _sending ? null : _submit,
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.person_add_alt_1),
            label: Text(_sending ? 'Sending invite...' : 'Send invite'),
          ),
        ],
      ),
    );
  }
}

class _InviteRoleMeta {
  const _InviteRoleMeta({
    required this.label,
    required this.description,
    required this.icon,
    required this.permissionPreview,
    required this.bookable,
  });

  final String label;
  final String description;
  final IconData icon;
  final List<String> permissionPreview;
  final bool bookable;
}

const Map<String, _InviteRoleMeta> _roleMeta = {
  RoleTemplateIds.owner: _InviteRoleMeta(
    label: 'Owner',
    description:
        'Full clinic access including settings, team management, scheduling, clinical work, and audit visibility.',
    icon: Icons.workspace_premium_outlined,
    permissionPreview: [
      PermissionKeys.settingsWrite,
      PermissionKeys.membersManage,
      PermissionKeys.scheduleWrite,
      PermissionKeys.clinicalWrite,
      PermissionKeys.auditRead,
    ],
    bookable: true,
  ),
  RoleTemplateIds.manager: _InviteRoleMeta(
    label: 'Manager',
    description:
        'Operational access for running the clinic day to day, including team management, scheduling, and clinical oversight.',
    icon: Icons.manage_accounts_outlined,
    permissionPreview: [
      PermissionKeys.settingsWrite,
      PermissionKeys.membersManage,
      PermissionKeys.scheduleWrite,
      PermissionKeys.notesWriteAny,
      PermissionKeys.servicesManage,
    ],
    bookable: true,
  ),
  RoleTemplateIds.practitioner: _InviteRoleMeta(
    label: 'Clinician',
    description:
        'For bookable clinicians who need calendar access, patient access, and clinical documentation permissions.',
    icon: Icons.medical_services_outlined,
    permissionPreview: [
      PermissionKeys.scheduleRead,
      PermissionKeys.scheduleWrite,
      PermissionKeys.patientsRead,
      PermissionKeys.clinicalRead,
      PermissionKeys.notesWriteOwn,
    ],
    bookable: true,
  ),
  RoleTemplateIds.receptionist: _InviteRoleMeta(
    label: 'Reception',
    description:
        'For front-desk or admin staff who manage bookings and patients without clinical note access.',
    icon: Icons.support_agent_outlined,
    permissionPreview: [
      PermissionKeys.membersRead,
      PermissionKeys.scheduleWrite,
      PermissionKeys.patientsRead,
      PermissionKeys.patientsWrite,
      PermissionKeys.registriesManage,
    ],
    bookable: true,
  ),
  RoleTemplateIds.billing: _InviteRoleMeta(
    label: 'Billing',
    description:
        'For finance-focused staff who mainly need billing workflows and limited operational access.',
    icon: Icons.receipt_long_outlined,
    permissionPreview: [
      PermissionKeys.settingsRead,
      PermissionKeys.scheduleRead,
      PermissionKeys.patientsRead,
    ],
    bookable: false,
  ),
  RoleTemplateIds.viewer: _InviteRoleMeta(
    label: 'Viewer',
    description:
        'Read-only access for staff who need visibility into schedules and clinic activity without editing rights.',
    icon: Icons.visibility_outlined,
    permissionPreview: [
      PermissionKeys.settingsRead,
      PermissionKeys.scheduleRead,
      PermissionKeys.patientsRead,
      PermissionKeys.notesRead,
    ],
    bookable: false,
  ),
};
