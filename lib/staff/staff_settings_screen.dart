import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/app/callable_error_mapping.dart';
import '/app/clinic_context.dart';
import '/data/repositories/staff_profile_repository.dart';
import '/data/repositories/staff_repository.dart';
import '/features/auth/permission_guard.dart';
import '/staff/screens/staff_member_screen.dart';
import '/staff/team_member_display_helpers.dart';
import '/staff/team_settings_widgets.dart';
import '/ui/design_tokens.dart';

class StaffSettingsScreen extends StatefulWidget {
  const StaffSettingsScreen({
    super.key,
    this.embedded = false,
    this.enableRowTap = true,
  });

  final bool embedded;
  final bool enableRowTap;

  @override
  State<StaffSettingsScreen> createState() => _StaffSettingsScreenState();
}

class _StaffSettingsScreenState extends State<StaffSettingsScreen> {
  int _listRetryKey = 0;
  final TextEditingController _searchCtl = TextEditingController();
  _TeamMemberFilter _filter = _TeamMemberFilter.all;

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
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
        SnackBar(content: Text('Status updated to ${next == 'active' ? 'Active' : 'Suspended'}')),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            messageForCallableError(e, fallback: 'Failed to update status.'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            messageForCallableError(e, fallback: 'Failed to update status.'),
          ),
        ),
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

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setD) {
            Future<void> submit() async {
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Display name updated')),
                );
              } catch (e) {
                setD(() {
                  error = messageForCallableError(
                    e,
                    fallback: 'Failed to update display name.',
                  );
                });
              } finally {
                setD(() => loading = false);
              }
            }

            return AlertDialog(
              title: const Text('Edit display name'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fallbackLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      enabled: !loading,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                        hintText: 'e.g. Graeme Lawson',
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: loading ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: loading ? null : submit,
                  child: loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openMember(BuildContext context, String clinicId, String uid) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StaffMemberScreen(
          clinicId: clinicId,
          memberUid: uid,
          embeddedInSettings: widget.embedded,
        ),
      ),
    );
  }

  void _retry(String clinicId) {
    context.read<StaffRepository>().clearMembershipListCache(clinicId);
    setState(() => _listRetryKey++);
  }

  @override
  Widget build(BuildContext context) {
    final clinicCtx = context.watch<ClinicContext>();
    final clinicId = clinicCtx.hasClinic ? clinicCtx.clinicId : '';
    final guard = PermissionGuard(clinicCtx.permissions);
    final canManage = guard.has('members.manage');
    final canRead = guard.has('members.read') || canManage;
    final repo = context.read<StaffRepository>();

    final body = _buildBody(
      context: context,
      clinicId: clinicId,
      canRead: canRead,
      canManage: canManage,
      repo: repo,
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Team'),
      ),
      body: body,
    );
  }

  Widget _buildBody({
    required BuildContext context,
    required String clinicId,
    required bool canRead,
    required bool canManage,
    required StaffRepository repo,
  }) {
    // No invite button here; use the Invite tab subcategory.
    final actions = <Widget>[];

    if (clinicId.trim().isEmpty) {
      return TeamSettingsPage(
        title: 'Team members',
        subtitle:
            'Manage clinicians and admin staff used in scheduling today and public booking later.',
        actions: actions,
        children: const [
          TeamEmptyStateCard(
            icon: Icons.domain_disabled_outlined,
            title: 'No clinic selected',
            body: 'Select a clinic to view and manage team members.',
          ),
        ],
      );
    }

    if (!canRead) {
      return TeamSettingsPage(
        title: 'Team members',
        subtitle:
            'Manage clinicians and admin staff used in scheduling today and public booking later.',
        actions: actions,
        children: const [
          TeamEmptyStateCard(
            icon: Icons.lock_outline,
            title: 'Permission needed',
            body:
                'You need members.read to view the team list. Team managers can still invite and update access via the existing callable flows.',
          ),
        ],
      );
    }

    // No timeout: stream is cached per clinicId; timeout was causing spurious reset after 15s
    return StreamBuilder<List<MemberDocSnapshot>>(
      key: ValueKey('members-$clinicId-$_listRetryKey'),
      stream: repo.watchMembersCached(clinicId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return TeamSettingsPage(
            title: 'Team members',
            subtitle:
                'Manage clinicians and admin staff used in scheduling today and public booking later.',
            actions: actions,
            children: const [
              TeamSettingsSectionCard(
                title: 'Loading team',
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                ),
              ),
            ],
          );
        }

        if (snap.hasError) {
          final err = snap.error;
          final isTimeout = err is TimeoutException;
          return TeamSettingsPage(
            title: 'Team members',
            subtitle:
                'Manage clinicians and admin staff used in scheduling today and public booking later.',
            actions: actions,
            children: [
              TeamEmptyStateCard(
                icon: Icons.error_outline,
                title: isTimeout ? 'Team list timed out' : 'Could not load team',
                body: isTimeout
                    ? 'The team list took too long to load. Retry to refresh.'
                    : '$err',
                action: FilledButton.icon(
                  onPressed: () => _retry(clinicId),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ),
            ],
          );
        }

        final docs = snap.data ?? const <MemberDocSnapshot>[];
        final items = docs.map(_TeamMemberItem.fromDoc).toList()
          ..sort((a, b) {
            final byActive = (b.active ? 1 : 0).compareTo(a.active ? 1 : 0);
            if (byActive != 0) return byActive;
            return a.titleText.toLowerCase().compareTo(b.titleText.toLowerCase());
          });

        final filtered = items.where(_matchesFilters).toList();
        final activeCount = items.where((item) => item.active).length;
        final invitedCount = items.where((item) => item.isInvited).length;
        final bookableCount = items.where((item) => item.bookable).length;

        // Left: title, short text, then Browse team (search + filters + list)
        final leftContent = TeamSettingsPage(
          title: 'Team members',
          subtitle:
              'Manage clinicians and admin staff used in scheduling today and public booking later.',
          actions: actions,
          children: [
            TeamSettingsSectionCard(
              title: 'Browse team',
              subtitle:
                  'Filter by status or search by name, email, role, or UID. Invited and suspended members remain visible so access can be reviewed cleanly.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _searchCtl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Search team members',
                      hintText: 'Try a name, email, role, or UID',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchCtl.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchCtl.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _TeamMemberFilter.values
                        .map(
                          (filter) => ChoiceChip(
                            label: Text(filter.label),
                            selected: _filter == filter,
                            onSelected: (_) => setState(() => _filter = filter),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
            if (items.isEmpty)
              TeamEmptyStateCard(
                icon: Icons.group_add_outlined,
                title: 'No team members yet',
                body:
                    'Use the Invite tab to add clinicians, reception staff, or managers.',
                action: null,
              )
            else if (filtered.isEmpty)
              TeamEmptyStateCard(
                icon: Icons.filter_alt_off_outlined,
                title: 'No matches',
                body:
                    'No team members match the current filter. Clear the search or switch the status filter to see the rest of the clinic team.',
                action: OutlinedButton(
                  onPressed: () {
                    _searchCtl.clear();
                    setState(() => _filter = _TeamMemberFilter.all);
                  },
                  child: const Text('Clear filters'),
                ),
              )
            else
              ...filtered.map(
                (item) => _TeamMemberCard(
                  clinicId: clinicId,
                  item: item,
                  canManage: canManage,
                  enableRowTap: widget.enableRowTap,
                  onOpen: () => _openMember(context, clinicId, item.uid),
                  onEditName: canManage
                      ? () => _showEditProfileDialog(
                            context: context,
                            clinicId: clinicId,
                            memberUid: item.uid,
                            initialDisplayName: item.titleText,
                            fallbackLabel: 'Account: ${item.emailOrUid}',
                          )
                      : null,
                  onToggleStatus: canManage
                      ? () => _toggleStatus(
                            clinicId: clinicId,
                            memberUid: item.uid,
                            currentStatus: item.effectiveStatus,
                          )
                      : null,
                ),
              ),
          ],
        );

        // Right: narrow column with team/invite summary cards only
        const double summaryPanelWidth = 280;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: leftContent,
            ),
            SizedBox(
              width: summaryPanelWidth,
              child: Container(
                color: AppColors.settingsPageBg,
                padding: const EdgeInsets.all(AppSpacing.screenPadding),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TeamMetricCard(
                      label: 'Total members',
                      value: items.length.toString(),
                      icon: Icons.group_outlined,
                    ),
                    const SizedBox(height: 12),
                    TeamMetricCard(
                      label: 'Active',
                      value: activeCount.toString(),
                      icon: Icons.check_circle_outline,
                    ),
                    const SizedBox(height: 12),
                    TeamMetricCard(
                      label: 'Calendar ready',
                      value: bookableCount.toString(),
                      icon: Icons.calendar_month_outlined,
                    ),
                    const SizedBox(height: 12),
                    TeamMetricCard(
                      label: 'Invited',
                      value: invitedCount.toString(),
                      icon: Icons.mark_email_unread_outlined,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  bool _matchesFilters(_TeamMemberItem item) {
    final query = _searchCtl.text.trim().toLowerCase();
    final matchesQuery = query.isEmpty ||
        item.searchText.contains(query);
    if (!matchesQuery) return false;

    return switch (_filter) {
      _TeamMemberFilter.all => true,
      _TeamMemberFilter.active => item.active && !item.isInvited,
      _TeamMemberFilter.invited => item.isInvited,
      _TeamMemberFilter.suspended => !item.active && !item.isInvited,
      _TeamMemberFilter.bookable => item.bookable,
    };
  }
}

enum _TeamMemberFilter {
  all('All'),
  active('Active'),
  invited('Invited'),
  suspended('Suspended'),
  bookable('Calendar ready');

  const _TeamMemberFilter(this.label);
  final String label;
}

class _TeamMemberItem {
  _TeamMemberItem({
    required this.uid,
    required this.titleText,
    required this.email,
    required this.emailOrUid,
    required this.roleLabel,
    required this.statusLabel,
    required this.effectiveStatus,
    required this.active,
    required this.isInvited,
    required this.bookable,
    required this.canCreateBookings,
    required this.hasClinicalAccess,
    required this.permissionsSummary,
    required this.searchText,
  });

  final String uid;
  final String titleText;
  final String email;
  final String emailOrUid;
  final String roleLabel;
  final String statusLabel;
  final String effectiveStatus;
  final bool active;
  final bool isInvited;
  final bool bookable;
  final bool canCreateBookings;
  final bool hasClinicalAccess;
  final List<String> permissionsSummary;
  final String searchText;

  factory _TeamMemberItem.fromDoc(MemberDocSnapshot doc) {
    final data = doc.data();
    final uid = doc.id;
    final roleId = (data['role'] ?? data['roleId'] ?? '').toString().trim();
    final roleName = (data['roleName'] ?? '').toString().trim();
    final roleLabel = roleDisplayLabel(
      roleId: roleId,
      roleName: roleName.isEmpty ? null : roleName,
    );
    final active = data['active'] != false;
    final statusRaw = (data['status'] ?? '').toString().trim();
    final effectiveStatus = statusRaw.isNotEmpty
        ? statusRaw
        : (active ? 'active' : 'suspended');
    final statusLabel = statusDisplayLabel(
      status: effectiveStatus,
      active: active,
    );
    final email = memberEmail(data);
    final titleText = memberDisplayName(data, uid);
    final permissionPreview = permissionDisplayFromKeys(
      enabledPermissionKeys(data),
      maxShown: 3,
    );
    final searchText = [
      titleText,
      email,
      uid,
      roleLabel,
      ...permissionPreview.displayLabels,
    ].join(' ').toLowerCase();

    return _TeamMemberItem(
      uid: uid,
      titleText: titleText,
      email: email,
      emailOrUid: email.isNotEmpty ? email : uid,
      roleLabel: roleLabel,
      statusLabel: statusLabel,
      effectiveStatus: effectiveStatus,
      active: active,
      isInvited: effectiveStatus.toLowerCase() == 'invited',
      bookable: memberIsBookable(data),
      canCreateBookings: memberCanCreateBookings(data),
      hasClinicalAccess: memberHasClinicalAccess(data),
      permissionsSummary: permissionPreview.displayLabels,
      searchText: searchText,
    );
  }
}

class _TeamMemberCard extends StatelessWidget {
  const _TeamMemberCard({
    required this.clinicId,
    required this.item,
    required this.canManage,
    required this.enableRowTap,
    required this.onOpen,
    this.onEditName,
    this.onToggleStatus,
  });

  final String clinicId;
  final _TeamMemberItem item;
  final bool canManage;
  final bool enableRowTap;
  final VoidCallback onOpen;
  final VoidCallback? onEditName;
  final VoidCallback? onToggleStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profileRepo = context.read<StaffProfileRepository>();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: profileRepo.watchStaffProfile(clinicId, item.uid),
      builder: (context, profileSnap) {
        final photoUrl = profileSnap.data?.data()?['photoUrl']?.toString().trim();
        final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFE0E0E0)),
          ),
          child: InkWell(
            onTap: enableRowTap ? onOpen : null,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HoverScaleWrapper(
                    child: TeamInitialAvatar(
                      label: item.titleText,
                      active: item.active,
                      radius: 40,
                      imageUrl: hasPhoto ? photoUrl : null,
                      showBorder: false,
                    ),
                  ),
                  const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.titleText,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  decoration: item.active
                                      ? null
                                      : TextDecoration.lineThrough,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.emailOrUid,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (canManage)
                          PopupMenuButton<String>(
                            tooltip: 'Team member actions',
                            onSelected: (value) {
                              switch (value) {
                                case 'open':
                                  onOpen();
                                case 'editName':
                                  onEditName?.call();
                                case 'toggle':
                                  onToggleStatus?.call();
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
                                  item.effectiveStatus == 'active'
                                      ? 'Suspend'
                                      : 'Reactivate',
                                ),
                              ),
                            ],
                          )
                        else if (enableRowTap)
                          const Icon(Icons.chevron_right),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TeamMetadataChip(
                          label: item.roleLabel,
                          icon: Icons.badge_outlined,
                          tone: TeamChipTone.info,
                        ),
                        TeamMetadataChip(
                          label: item.statusLabel,
                          icon: item.isInvited
                              ? Icons.mark_email_unread_outlined
                              : item.active
                                  ? Icons.check_circle_outline
                                  : Icons.pause_circle_outline,
                          tone: item.isInvited
                              ? TeamChipTone.info
                              : item.active
                                  ? TeamChipTone.success
                                  : TeamChipTone.warning,
                        ),
                        TeamMetadataChip(
                          label: item.bookable
                              ? 'Calendar visible'
                              : 'Not bookable',
                          icon: Icons.calendar_month_outlined,
                          tone: item.bookable
                              ? TeamChipTone.success
                              : TeamChipTone.neutral,
                        ),
                        TeamMetadataChip(
                          label: item.hasClinicalAccess
                              ? 'Clinical access'
                              : 'Admin staff',
                          icon: item.hasClinicalAccess
                              ? Icons.description_outlined
                              : Icons.support_agent_outlined,
                        ),
                      ],
                    ),
                    if (item.permissionsSummary.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        item.permissionsSummary.join(' • '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (item.bookable && !item.canCreateBookings) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Can be assigned in the calendar, but cannot create bookings directly.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
        );
      },
    );
  }
}
