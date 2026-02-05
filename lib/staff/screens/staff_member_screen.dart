// lib/staff/screens/staff_member_screen.dart
//
// ✅ FIX: Staff opening hours were "saving" but immediately reverting because
// we were hydrating mutable form state inside a StreamBuilder rebuild.
// Stream emits -> build runs -> hydrate runs -> overwrites local edits.
//
// Solution:
// - Add `_availabilityDirty` flag (set true on ANY edit)
// - Prevent hydration once dirty
// - Reset dirty only after successful save
// - Remove TextEditingController creation inside build for timezone field
//   (use initialValue + onChanged instead to avoid rebuild/controller churn)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/shared/widgets/weekly_hours_editor.dart';

import '../../app/clinic_context.dart';
import '../../data/repositories/staff_repository.dart';
import '../../data/repositories/staff_profile_repository.dart';
import '../../features/auth/permission_guard.dart';

class StaffMemberScreen extends StatefulWidget {
  const StaffMemberScreen({
    super.key,
    required this.memberUid,
  });

  final String memberUid;

  @override
  State<StaffMemberScreen> createState() => _StaffMemberScreenState();
}

class _StaffMemberScreenState extends State<StaffMemberScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  // ─────────────────────────────
  // Profile controllers (Phase A)
  // ─────────────────────────────
  final _displayNameCtl = TextEditingController();
  final _phoneCtl = TextEditingController();
  final _emailCtl = TextEditingController();

  bool _savingProfile = false;
  String? _saveErr;

  // ─────────────────────────────
  // Availability (staff opening hours)
  // ─────────────────────────────
  String _availabilityTimezone = 'Europe/Prague';

  // day -> [{start,end}]
  Map<String, List<Map<String, String>>> _weekly = const {
    'mon': [],
    'tue': [],
    'wed': [],
    'thu': [],
    'fri': [],
    'sat': [],
    'sun': [],
  };

  bool _savingAvailability = false;
  String? _availabilityErr;

  // ✅ NEW: Once user edits, block stream-hydration from overwriting local state.
  bool _availabilityDirty = false;

  // ✅ Lazy tab loading: only subscribe/build a tab once it’s visited.
  final Set<int> _builtTabs = <int>{0}; // Profile tab preloaded

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);

    _tabs.addListener(() {
      if (_tabs.indexIsChanging) return;
      final idx = _tabs.index;
      if (_builtTabs.add(idx)) {
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _displayNameCtl.dispose();
    _phoneCtl.dispose();
    _emailCtl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  bool _profileHydrated = false;
  void _hydrateProfileControllersIfNeeded({
    required String displayName,
    required String phone,
    required String email,
  }) {
    if (_profileHydrated) return;
    if (displayName.isEmpty && phone.isEmpty && email.isEmpty) return;

    _displayNameCtl.text = displayName;
    _phoneCtl.text = phone;
    _emailCtl.text = email;

    _profileHydrated = true;
  }

  bool _availabilityHydrated = false;
  void _hydrateAvailabilityIfNeeded({
    required String timezone,
    required dynamic weekly,
  }) {
    // ✅ CRITICAL: never hydrate once user has started editing
    if (_availabilityHydrated || _availabilityDirty) return;

    if (timezone.trim().isNotEmpty) {
      _availabilityTimezone = timezone.trim();
    }

    final Map<String, List<Map<String, String>>> parsed = {
      'mon': [],
      'tue': [],
      'wed': [],
      'thu': [],
      'fri': [],
      'sat': [],
      'sun': [],
    };

    if (weekly is Map) {
      for (final day in parsed.keys) {
        final v = weekly[day];
        if (v is List) {
          parsed[day] = v
              .whereType<Map>()
              .map((m) => {
                    'start': (m['start'] ?? '').toString(),
                    'end': (m['end'] ?? '').toString(),
                  })
              .where((it) =>
                  it['start']!.trim().isNotEmpty && it['end']!.trim().isNotEmpty)
              .toList();
        }
      }
      _weekly = parsed;
    } else if (weekly == null) {
      // Optional starter template for first-time setup only
      _weekly = {
        'mon': [
          {'start': '08:00', 'end': '12:00'},
          {'start': '13:00', 'end': '17:00'},
        ],
        'tue': [
          {'start': '08:00', 'end': '16:00'},
        ],
        'wed': [],
        'thu': [],
        'fri': [],
        'sat': [],
        'sun': [],
      };
    }

    _availabilityHydrated = true;
  }

  Map<String, dynamic> _weeklyToFirestorePayload(
    Map<String, List<Map<String, String>>> weekly,
  ) {
    return {
      for (final entry in weekly.entries)
        entry.key: entry.value
            .map((it) => {
                  'start': (it['start'] ?? '').toString(),
                  'end': (it['end'] ?? '').toString(),
                })
            .toList(),
    };
  }

  void _markAvailabilityDirty() {
    if (_availabilityDirty) return;
    setState(() => _availabilityDirty = true);
  }

  void _clearAvailabilityDirty() {
    if (!_availabilityDirty) return;
    setState(() => _availabilityDirty = false);
  }

  @override
  Widget build(BuildContext context) {
    final clinicCtx = context.watch<ClinicContext>();
    final clinicId = clinicCtx.clinicId;

    final guard = PermissionGuard(clinicCtx.permissions);
    final canManage = guard.has('members.manage');
    final canRead = guard.has('members.read') || canManage;

    final staffRepo = context.read<StaffRepository>();
    final profileRepo = context.read<StaffProfileRepository>();

    if (clinicId.trim().isEmpty) {
      return const Scaffold(
        body: Center(child: Text('No clinic selected.')),
      );
    }

    if (!canRead) {
      return const Scaffold(
        body: Center(child: Text('You do not have permission to view staff.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff member'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Profile'),
            Tab(text: 'Professional'),
            Tab(text: 'Opening hours'),
          ],
        ),
      ),

      // ✅ Membership resolved via StaffRepository (canonical-first fallback)
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: staffRepo.watchMembershipDataWithFallback(
          clinicId,
          widget.memberUid,
        ),
        builder: (context, memberSnap) {
          if (memberSnap.hasError) {
            return Center(child: Text('Error: ${memberSnap.error}'));
          }
          if (!memberSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final memberData = memberSnap.data;
          if (memberData == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'This staff member is missing a membership record.\n\n'
                  'Expected one of:\n'
                  '- clinics/{clinicId}/memberships/{uid}\n'
                  '- clinics/{clinicId}/members/{uid}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final roleId =
              (memberData['roleId'] ?? memberData['role'] ?? '').toString();
          final status = (memberData['status'] ?? '').toString();
          final active = memberData['active'];
          final invitedEmail =
              (memberData['invitedEmail'] ?? memberData['email'] ?? '')
                  .toString();
          final memberDisplayName = (memberData['displayName'] ?? '').toString();

          final isSelf =
              clinicCtx.hasUid && clinicCtx.uid.trim() == widget.memberUid.trim();

          // Phase A: only managers can edit others.
          final canEditThisProfile = canManage;

          final allowSuspend = canManage && !isSelf;

          return Column(
            children: [
              _MemberHeader(
                uid: widget.memberUid,
                roleId: roleId,
                status: status,
                active: active,
                invitedEmail: invitedEmail,
                displayName: memberDisplayName,
                canManage: canManage,
                allowSuspend: allowSuspend,
                onSuspend: () async {
                  await staffRepo.setMembershipStatus(
                    clinicId: clinicId,
                    memberUid: widget.memberUid,
                    status: 'suspended',
                  );
                  _toast('Member suspended');
                },
                onActivate: () async {
                  await staffRepo.setMembershipStatus(
                    clinicId: clinicId,
                    memberUid: widget.memberUid,
                    status: 'active',
                  );
                  _toast('Member activated');
                },
              ),
              const Divider(height: 1),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    // ─────────────────────────────
                    // Profile tab (lazy loaded)
                    // ─────────────────────────────
                    _builtTabs.contains(0)
                        ? _ProfileTabBody(
                            clinicId: clinicId,
                            memberUid: widget.memberUid,
                            profileRepo: profileRepo,
                            staffRepo: staffRepo,
                            displayNameCtl: _displayNameCtl,
                            phoneCtl: _phoneCtl,
                            emailCtl: _emailCtl,
                            enabled: canEditThisProfile,
                            saving: _savingProfile,
                            error: _saveErr,
                            onSetSaving: (v) =>
                                setState(() => _savingProfile = v),
                            onSetError: (v) => setState(() => _saveErr = v),
                            hydrateIfNeeded: _hydrateProfileControllersIfNeeded,
                            onSaved: () => _toast('Profile saved'),
                          )
                        : const SizedBox.shrink(),

                    // ─────────────────────────────
                    // Professional tab (lazy loaded)
                    // ─────────────────────────────
                    _builtTabs.contains(1)
                        ? const _PlaceholderTab(
                            title: 'Professional',
                            body:
                                'Add insurance, registration numbers, and expiries here in Phase B.',
                          )
                        : const SizedBox.shrink(),

                    // ─────────────────────────────
                    // Opening hours tab (lazy loaded)
                    // ─────────────────────────────
                    _builtTabs.contains(2)
                        ? _OpeningHoursTabBody(
                            clinicId: clinicId,
                            memberUid: widget.memberUid,
                            profileRepo: profileRepo,
                            enabled: canEditThisProfile,
                            saving: _savingAvailability,
                            error: _availabilityErr,
                            onSetSaving: (v) =>
                                setState(() => _savingAvailability = v),
                            onSetError: (v) =>
                                setState(() => _availabilityErr = v),
                            hydrateIfNeeded: (tz, weekly) {
                              _hydrateAvailabilityIfNeeded(
                                timezone: tz,
                                weekly: weekly,
                              );
                            },
                            getTimezone: () => _availabilityTimezone,
                            setTimezone: (tz) {
                              setState(() => _availabilityTimezone = tz);
                              _markAvailabilityDirty();
                            },
                            getWeekly: () => _weekly,
                            setWeekly: (w) {
                              setState(() => _weekly = w);
                              _markAvailabilityDirty();
                            },
                            toPayload: _weeklyToFirestorePayload,
                            onSaved: () => _toast('Opening hours saved'),
                            onSavedSuccessfully: _clearAvailabilityDirty,
                          )
                        : const SizedBox.shrink(),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// ─────────────────────────────
/// Tab bodies (so StreamBuilders don’t get recreated as often)
/// ─────────────────────────────

class _ProfileTabBody extends StatelessWidget {
  const _ProfileTabBody({
    required this.clinicId,
    required this.memberUid,
    required this.profileRepo,
    required this.staffRepo,
    required this.displayNameCtl,
    required this.phoneCtl,
    required this.emailCtl,
    required this.enabled,
    required this.saving,
    required this.error,
    required this.onSetSaving,
    required this.onSetError,
    required this.hydrateIfNeeded,
    required this.onSaved,
  });

  final String clinicId;
  final String memberUid;
  final StaffProfileRepository profileRepo;
  final StaffRepository staffRepo;

  final TextEditingController displayNameCtl;
  final TextEditingController phoneCtl;
  final TextEditingController emailCtl;

  final bool enabled;
  final bool saving;
  final String? error;

  final void Function(bool v) onSetSaving;
  final void Function(String? v) onSetError;

  final void Function({
    required String displayName,
    required String phone,
    required String email,
  }) hydrateIfNeeded;

  final VoidCallback onSaved;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: profileRepo.watchStaffProfile(clinicId, memberUid),
      builder: (context, snap) {
        final data = snap.data?.data();

        hydrateIfNeeded(
          displayName: (data?['displayName'] ?? '').toString(),
          phone: (data?['contact'] is Map)
              ? ((data?['contact']?['phone'] ?? '').toString())
              : '',
          email: (data?['contact'] is Map)
              ? ((data?['contact']?['email'] ?? '').toString())
              : '',
        );

        return _ProfileTab(
          displayNameCtl: displayNameCtl,
          phoneCtl: phoneCtl,
          emailCtl: emailCtl,
          enabled: enabled,
          saving: saving,
          error: error,
          onSave: () async {
            if (!enabled) return;

            onSetSaving(true);
            onSetError(null);

            try {
              await profileRepo.upsertStaffProfile(
                clinicId: clinicId,
                uid: memberUid,
                patch: <String, dynamic>{
                  'schemaVersion': 1,
                  'displayName': displayNameCtl.text.trim(),
                  'contact': <String, dynamic>{
                    'phone': phoneCtl.text.trim(),
                    'email': emailCtl.text.trim(),
                  },
                },
              );

              final name = displayNameCtl.text.trim();
              if (name.isNotEmpty) {
                await staffRepo.updateMemberDisplayName(
                  clinicId: clinicId,
                  memberUid: memberUid,
                  displayName: name,
                );
              }

              onSaved();
            } catch (e) {
              onSetError(e.toString());
            } finally {
              onSetSaving(false);
            }
          },
        );
      },
    );
  }
}

class _OpeningHoursTabBody extends StatelessWidget {
  const _OpeningHoursTabBody({
    required this.clinicId,
    required this.memberUid,
    required this.profileRepo,
    required this.enabled,
    required this.saving,
    required this.error,
    required this.onSetSaving,
    required this.onSetError,
    required this.hydrateIfNeeded,
    required this.getTimezone,
    required this.setTimezone,
    required this.getWeekly,
    required this.setWeekly,
    required this.toPayload,
    required this.onSaved,
    required this.onSavedSuccessfully,
  });

  final String clinicId;
  final String memberUid;
  final StaffProfileRepository profileRepo;

  final bool enabled;
  final bool saving;
  final String? error;

  final void Function(bool v) onSetSaving;
  final void Function(String? v) onSetError;

  final void Function(String timezone, dynamic weekly) hydrateIfNeeded;

  final String Function() getTimezone;
  final void Function(String tz) setTimezone;

  final Map<String, List<Map<String, String>>> Function() getWeekly;
  final void Function(Map<String, List<Map<String, String>>> w) setWeekly;

  final Map<String, dynamic> Function(
    Map<String, List<Map<String, String>>> weekly,
  ) toPayload;

  final VoidCallback onSaved;
  final VoidCallback onSavedSuccessfully;

  @override
  Widget build(BuildContext context) {
    // Helpful debug trace (path must be EXACT)
    final path =
        'clinics/$clinicId/staffProfiles/$memberUid/availability/default';

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: profileRepo.watchAvailabilityDefault(clinicId, memberUid),
      builder: (context, snap) {
        // ✅ SHOW STREAM ERRORS (this is what you were missing)
        if (snap.hasError) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Failed to load staff availability.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text('Path: $path'),
              const SizedBox(height: 12),
              Text(
                snap.error.toString(),
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 12),
              const Text(
                'If this says permission-denied, your Firestore rules do NOT allow reading staffProfiles availability.',
              ),
            ],
          );
        }

        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snap.data?.data();

        // Hydrate only when pristine (your parent code blocks after edit)
        hydrateIfNeeded(
          (data?['timezone'] ?? '').toString(),
          data?['weekly'],
        );

        final tz = getTimezone();
        final weekly = getWeekly();

        return _OpeningHoursTab(
          timezone: tz,
          weekly: weekly,
          enabled: enabled,
          saving: saving,
          error: error,
          onTimezoneChanged: (v) => setTimezone(v.trim()),
          onWeeklyChanged: (w) => setWeekly(w),
          onSave: () async {
            if (!enabled) return;

            onSetSaving(true);
            onSetError(null);

            try {
              // EXTRA: show what we're sending (helps catch "wed missing" bugs)
              final payload = toPayload(weekly);

              await profileRepo.setAvailabilityDefault(
                clinicId: clinicId,
                uid: memberUid,
                timezone: tz.trim().isEmpty ? 'Europe/Prague' : tz.trim(),
                weekly: payload,
              );

              onSavedSuccessfully();
              onSaved();
            } catch (e) {
              onSetError(e.toString());
            } finally {
              onSetSaving(false);
            }
          },
        );
      },
    );
  }
}


/// ─────────────────────────────
/// UI components
/// ─────────────────────────────

class _MemberHeader extends StatelessWidget {
  const _MemberHeader({
    required this.uid,
    required this.roleId,
    required this.status,
    required this.active,
    required this.invitedEmail,
    required this.displayName,
    required this.canManage,
    required this.allowSuspend,
    required this.onSuspend,
    required this.onActivate,
  });

  final String uid;
  final String roleId;
  final String status;
  final dynamic active;
  final String invitedEmail;
  final String displayName;

  final bool canManage;
  final bool allowSuspend;

  final Future<void> Function() onSuspend;
  final Future<void> Function() onActivate;

  @override
  Widget build(BuildContext context) {
    final title = displayName.isNotEmpty
        ? displayName
        : (invitedEmail.isNotEmpty ? invitedEmail : uid);

    final trailing = !canManage
        ? null
        : PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'activate') await onActivate();
              if (v == 'suspend') await onSuspend();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'activate', child: Text('Activate')),
              PopupMenuItem(
                value: 'suspend',
                enabled: allowSuspend,
                child: Text(allowSuspend ? 'Suspend' : 'Suspend (disabled)'),
              ),
            ],
          );

    return ListTile(
      title: Text(title),
      subtitle: Text('role=$roleId • status=$status • active=$active'),
      trailing: trailing,
    );
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({
    required this.displayNameCtl,
    required this.phoneCtl,
    required this.emailCtl,
    required this.enabled,
    required this.saving,
    required this.error,
    required this.onSave,
  });

  final TextEditingController displayNameCtl;
  final TextEditingController phoneCtl;
  final TextEditingController emailCtl;
  final bool enabled;
  final bool saving;
  final String? error;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    final effectiveEnabled = enabled && !saving;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: displayNameCtl,
          enabled: effectiveEnabled,
          decoration: const InputDecoration(labelText: 'Display name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: phoneCtl,
          enabled: effectiveEnabled,
          decoration: const InputDecoration(labelText: 'Phone'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: emailCtl,
          enabled: effectiveEnabled,
          decoration: const InputDecoration(labelText: 'Email'),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 16),
        if (!enabled) ...[
          Text(
            'Read-only: you do not have permission to edit staff profiles.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
        ],
        if (error != null) ...[
          Text(error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 12),
        ],
        ElevatedButton.icon(
          onPressed: (!enabled || saving) ? null : onSave,
          icon: saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          label: Text(saving ? 'Saving…' : 'Save profile'),
        ),
      ],
    );
  }
}

class _OpeningHoursTab extends StatelessWidget {
  const _OpeningHoursTab({
    required this.timezone,
    required this.weekly,
    required this.enabled,
    required this.saving,
    required this.error,
    required this.onWeeklyChanged,
    required this.onTimezoneChanged,
    required this.onSave,
  });

  final String timezone;
  final Map<String, List<Map<String, String>>> weekly;

  final bool enabled;
  final bool saving;
  final String? error;

  final void Function(String tz) onTimezoneChanged;
  final void Function(Map<String, List<Map<String, String>>> weekly)
      onWeeklyChanged;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    final effectiveEnabled = enabled && !saving;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextFormField(
          enabled: effectiveEnabled,
          initialValue: timezone,
          decoration: const InputDecoration(
            labelText: 'Timezone (IANA)',
            helperText: 'e.g. Europe/Prague',
          ),
          onChanged: onTimezoneChanged,
        ),
        const SizedBox(height: 12),
        WeeklyHoursEditor(
          initialWeekly: weekly,
          readOnly: !effectiveEnabled,
          onChanged: onWeeklyChanged,
        ),
        const SizedBox(height: 16),
        if (!enabled) ...[
          Text(
            'Read-only: you do not have permission to edit opening hours.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
        ],
        if (error != null) ...[
          Text(error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 12),
        ],
        ElevatedButton.icon(
          onPressed: (!enabled || saving) ? null : onSave,
          icon: saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          label: Text(saving ? 'Saving…' : 'Save opening hours'),
        ),
      ],
    );
  }
}

class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(body, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
