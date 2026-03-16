import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/callable_error_mapping.dart';
import '../../app/clinic_context.dart';
import '../../data/repositories/appointment_types_repository.dart';
import '../../data/repositories/locations_repository.dart';
import '../../data/repositories/staff_profile_repository.dart';
import '../../data/repositories/staff_repository.dart';
import '../../features/auth/permission_guard.dart';
import '../../models/practitioner_booking_meta.dart';
import '../../ui/design_tokens.dart';
import '../team_member_display_helpers.dart';
import '../team_settings_widgets.dart';
import 'practitioner_availability_screen.dart';

/// Categories for the left rail on the team member profile (matches settings pattern).
enum _MemberProfileCategory {
  profile,
  bookingVisibility,
  availability,
}

class StaffMemberScreen extends StatefulWidget {
  const StaffMemberScreen({
    super.key,
    required this.memberUid,
    this.clinicId,
    this.embeddedInSettings = false,
    this.embedInPanel = false,
    this.initialTab,
  });

  final String memberUid;
  final String? clinicId;
  final bool embeddedInSettings;
  /// When true, build only the body content (no Scaffold/AppBar) for embedding in a detail panel.
  final bool embedInPanel;
  final String? initialTab;

  @override
  State<StaffMemberScreen> createState() => _StaffMemberScreenState();
}

class _StaffMemberScreenState extends State<StaffMemberScreen> {
  final _displayNameCtl = TextEditingController();
  final _titleCtl = TextEditingController();
  final _phoneCtl = TextEditingController();
  final _emailCtl = TextEditingController();
  final _bioCtl = TextEditingController();
  final _publicSortOrderCtl = TextEditingController(text: '0');

  String? _experienceLevel;
  bool _savingProfile = false;
  String? _saveErr;
  bool _profileHydrated = false;

  // Booking metadata state
  bool _activeForBooking = true;
  bool _showInPublicBooking = false;
  int _publicSortOrder = 0;
  List<String> _allowedLocationIds = [];
  List<String> _serviceIdsAllowed = [];
  bool _savingBookingMeta = false;
  String? _bookingMetaSaveErr;
  /// Signature of last meta applied from stream; prevents stream from overwriting user's unsaved toggles.
  String? _lastAppliedBookingMetaSignature;

  bool _uploadingPhoto = false;

  _MemberProfileCategory _selectedCategory = _MemberProfileCategory.profile;
  _MemberProfileCategory? _railHover;
  bool _permissionsExpanded = false;

  static const double _categoryRailWidth = 260;

  @override
  void dispose() {
    _displayNameCtl.dispose();
    _titleCtl.dispose();
    _phoneCtl.dispose();
    _emailCtl.dispose();
    _bioCtl.dispose();
    _publicSortOrderCtl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  InputDecoration _profileInputDecoration(
    BuildContext context, {
    required String label,
    String? hint,
    bool alignLabelWithHint = false,
  }) {
    final theme = Theme.of(context);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      alignLabelWithHint: alignLabelWithHint,
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.element),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.element),
        borderSide: BorderSide(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.element),
        borderSide: BorderSide(
          color: theme.colorScheme.primary,
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.element),
        borderSide: BorderSide(color: theme.colorScheme.error),
      ),
    );
  }

  void _hydrateProfileControllersIfNeeded({
    required String displayName,
    required String title,
    required String phone,
    required String email,
    String? experienceLevel,
    String? bio,
  }) {
    if (_profileHydrated) return;

    _displayNameCtl.text = displayName;
    _titleCtl.text = title;
    _phoneCtl.text = phone;
    _emailCtl.text = email;
    _experienceLevel = experienceLevel ?? _experienceLevel ?? 'senior';
    _bioCtl.text = bio ?? '';
    _profileHydrated = true;
  }

  /// Apply booking meta from Firestore stream so UI matches server.
  /// Only applies when the **stream data** has changed from the last applied snapshot,
  /// so the stream does not overwrite the user's unsaved toggles/checkboxes.
  void _applyBookingMetaFromStream(PractitionerBookingMeta meta, bool hasDoc) {
    if (!hasDoc) return;
    final signature = _bookingMetaSignature(meta);
    if (signature == _lastAppliedBookingMetaSignature) return;
    _lastAppliedBookingMetaSignature = signature;
    final newIds = List<String>.from(meta.allowedLocationIds);
    final newServices = List<String>.from(meta.serviceIdsAllowed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _activeForBooking = meta.activeForBooking;
        _showInPublicBooking = meta.showInPublicBooking;
        _publicSortOrder = meta.publicSortOrder;
        _publicSortOrderCtl.text = '${meta.publicSortOrder}';
        _allowedLocationIds = newIds;
        _serviceIdsAllowed = newServices;
      });
    });
  }

  static String _bookingMetaSignature(PractitionerBookingMeta meta) {
    final locs = List<String>.from(meta.allowedLocationIds)..sort();
    final svcs = List<String>.from(meta.serviceIdsAllowed)..sort();
    return '${meta.activeForBooking}|${meta.showInPublicBooking}|${meta.publicSortOrder}|${locs.join(",")}|${svcs.join(",")}';
  }

  Future<void> _saveBookingMeta({
    required String clinicId,
    required StaffRepository staffRepo,
  }) async {
    setState(() {
      _savingBookingMeta = true;
      _bookingMetaSaveErr = null;
    });

    try {
      final sortOrder = int.tryParse(_publicSortOrderCtl.text.trim()) ?? _publicSortOrder;
      await staffRepo.upsertPractitionerBookingMeta(
        clinicId: clinicId,
        uid: widget.memberUid,
        patch: <String, dynamic>{
          'activeForBooking': _activeForBooking,
          'showInPublicBooking': _showInPublicBooking,
          'publicSortOrder': sortOrder,
          'allowedLocationIds': List<String>.from(_allowedLocationIds),
          'serviceIdsAllowed': List<String>.from(_serviceIdsAllowed),
          'displayName': _displayNameCtl.text.trim(),
        },
      );
      if (mounted) _toast('Booking settings saved');
    } catch (e) {
      setState(() {
        _bookingMetaSaveErr = messageForCallableError(
          e,
          fallback: 'Failed to save booking settings.',
        );
      });
    } finally {
      if (mounted) setState(() => _savingBookingMeta = false);
    }
  }

  Future<void> _saveProfile({
    required String clinicId,
    required StaffProfileRepository profileRepo,
    required StaffRepository staffRepo,
  }) async {
    setState(() {
      _savingProfile = true;
      _saveErr = null;
    });

    try {
      final patch = <String, dynamic>{
        'schemaVersion': 1,
        'displayName': _displayNameCtl.text.trim(),
        if (_titleCtl.text.trim().isNotEmpty) 'title': _titleCtl.text.trim(),
        'contact': <String, dynamic>{
          'phone': _phoneCtl.text.trim(),
          'email': _emailCtl.text.trim(),
        },
      };

      final level = (_experienceLevel ?? '').trim();
      if (level.isNotEmpty) patch['experienceLevel'] = level;

      patch['bio'] = _bioCtl.text.trim();

      await profileRepo.upsertStaffProfile(
        clinicId: clinicId,
        uid: widget.memberUid,
        patch: patch,
      );

      final displayName = _displayNameCtl.text.trim();
      if (displayName.isNotEmpty) {
        await staffRepo.updateMemberDisplayName(
          clinicId: clinicId,
          memberUid: widget.memberUid,
          displayName: displayName,
        );
      }

      _toast('Profile saved');
    } catch (e) {
      setState(() {
        _saveErr = messageForCallableError(
          e,
          fallback: 'Failed to save profile.',
        );
      });
    } finally {
      if (mounted) {
        setState(() => _savingProfile = false);
      }
    }
  }

  Future<void> _uploadProfilePhoto({
    required String clinicId,
    required StaffProfileRepository profileRepo,
  }) async {
    if (_uploadingPhoto) return;
    setState(() => _uploadingPhoto = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final Uint8List? bytes = file.bytes;
      if (bytes == null) {
        _toast('Could not read file. Try again.');
        return;
      }
      final ext = file.extension ?? 'jpg';
      await profileRepo.uploadProfilePhoto(
        clinicId: clinicId,
        uid: widget.memberUid,
        bytes: bytes,
        fileExtension: ext,
      );
      _toast('Profile photo updated');
    } on FirebaseFunctionsException catch (e) {
      _toast(messageForCallableError(e, fallback: 'Upload failed. Please try again.'));
    } catch (e) {
      _toast('Upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Widget _buildCategoryRail(ThemeData theme) {
    return SizedBox(
      width: _categoryRailWidth,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest.withOpacity(0.7),
          border: Border(right: BorderSide(color: theme.dividerColor)),
        ),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 6),
          children: [
            _buildCategoryTile(theme, _MemberProfileCategory.profile, 'Profile', Icons.person_outline),
            _buildCategoryTile(theme, _MemberProfileCategory.bookingVisibility, 'Booking visibility', Icons.visibility_outlined),
            _buildCategoryTile(theme, _MemberProfileCategory.availability, 'Availability', Icons.schedule_outlined),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryTile(ThemeData theme, _MemberProfileCategory cat, String label, IconData icon) {
    final selected = _selectedCategory == cat;
    final hovered = _railHover == cat && !selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _railHover = cat),
      onExit: (_) => setState(() => _railHover = null),
      child: InkWell(
        onTap: () => setState(() => _selectedCategory = cat),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primaryContainer.withOpacity(0.5)
                : hovered
                    ? theme.colorScheme.onSurface.withOpacity(0.04)
                    : null,
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
            border: selected
                ? Border(
                    left: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 3,
                    ),
                  )
                : null,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 22,
                color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: selected ? FontWeight.w600 : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryTabBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          _CategoryChip(
            label: 'Profile',
            selected: _selectedCategory == _MemberProfileCategory.profile,
            onTap: () => setState(() => _selectedCategory = _MemberProfileCategory.profile),
          ),
          const SizedBox(width: 8),
          _CategoryChip(
            label: 'Booking visibility',
            selected: _selectedCategory == _MemberProfileCategory.bookingVisibility,
            onTap: () => setState(() => _selectedCategory = _MemberProfileCategory.bookingVisibility),
          ),
          const SizedBox(width: 8),
          _CategoryChip(
            label: 'Availability',
            selected: _selectedCategory == _MemberProfileCategory.availability,
            onTap: () => setState(() => _selectedCategory = _MemberProfileCategory.availability),
          ),
        ],
      ),
    );
  }

  /// Section block inside the right pane (no card; typography + spacing).
  Widget _buildSectionBlock(
    BuildContext context, {
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ] else
            const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required ClinicContext clinicCtx,
    required String clinicId,
    required bool canRead,
    required bool canManage,
    required StaffRepository staffRepo,
    required StaffProfileRepository profileRepo,
  }) {
    return !canRead
        ? const Center(
            child: Text('You do not have permission to view team members.'),
          )
        : clinicId.isEmpty
            ? const Center(child: Text('No clinic selected.'))
            : StreamBuilder<Map<String, dynamic>?>(
                  stream: staffRepo.watchMembershipDataWithFallback(
                    clinicId,
                    widget.memberUid,
                  ),
                  builder: (context, memberSnap) {
                    if (memberSnap.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Failed to load team member: ${memberSnap.error}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }
                    if (!memberSnap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final memberData = memberSnap.data;
                    if (memberData == null) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'This team member is missing a membership record.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }

                    final roleId =
                        (memberData['roleId'] ?? memberData['role'] ?? '')
                            .toString()
                            .trim();
                    final roleName =
                        (memberData['roleName'] ?? '').toString().trim();
                    final roleLabel = roleDisplayLabel(
                      roleId: roleId,
                      roleName: roleName.isEmpty ? null : roleName,
                    );
                    final active = memberData['active'] != false;
                    final statusRaw =
                        (memberData['status'] ?? '').toString().trim();
                    final statusLabel = statusDisplayLabel(
                      status: statusRaw.isEmpty
                          ? (active ? 'active' : 'suspended')
                          : statusRaw,
                      active: active,
                    );
                    final email = memberEmail(memberData);
                    final displayName =
                        memberDisplayName(memberData, widget.memberUid);
                    final enabledPermissions =
                        enabledPermissionKeys(memberData);
                    final permissionPreview = permissionDisplayFromKeys(
                      enabledPermissions,
                      maxShown: 8,
                    );
                    final isSelf = clinicCtx.hasUid &&
                        clinicCtx.uid.trim() == widget.memberUid.trim();
                    final canEditThisProfile = canManage || isSelf;
                    final bookable = memberIsBookable(memberData);
                    final canWriteBookings =
                        memberCanCreateBookings(memberData);
                    final clinicalAccess =
                        memberHasClinicalAccess(memberData);
                    final isInvited =
                        (statusRaw.isNotEmpty ? statusRaw : '').toLowerCase() ==
                            'invited';

                    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream:
                          profileRepo.watchStaffProfile(clinicId, widget.memberUid),
                      builder: (context, profileSnap) {
                        return StreamBuilder<Map<String, dynamic>?>(
                          stream: staffRepo.watchPractitionerBookingMeta(clinicId, widget.memberUid),
                          builder: (context, bookingMetaSnap) {
                        final bookingMetaData = bookingMetaSnap.data;
                        final hasPractitionerDoc = bookingMetaData != null;
                        final meta = hasPractitionerDoc
                            ? PractitionerBookingMeta.fromMap(widget.memberUid, bookingMetaData)
                            : PractitionerBookingMeta(uid: widget.memberUid);
                        _applyBookingMetaFromStream(meta, hasPractitionerDoc);

                        final profileData = profileSnap.data?.data();
                        final experienceLevel =
                            (profileData?['experienceLevel'] ?? '')
                                .toString()
                                .trim();

                        _hydrateProfileControllersIfNeeded(
                          displayName: (profileData?['displayName'] ??
                                  memberData['displayName'] ??
                                  '')
                              .toString(),
                          title: (profileData?['title'] ?? '').toString(),
                          phone: (profileData?['contact'] is Map)
                              ? ((profileData?['contact']?['phone'] ?? '')
                                  .toString())
                              : '',
                          email: (profileData?['contact'] is Map)
                              ? ((profileData?['contact']?['email'] ??
                                          email)
                                      .toString())
                              : email,
                          experienceLevel:
                              experienceLevel.isEmpty ? null : experienceLevel,
                          bio: (profileData?['bio'] ?? '').toString().trim().isEmpty
                              ? null
                              : (profileData?['bio'] ?? '').toString().trim(),
                        );

                        final theme = Theme.of(context);
                        final photoUrl = (profileData?['photoUrl'] ?? '')
                            .toString()
                            .trim();
                        final persistentOverview = Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    AppSpacing.screenPadding,
                                    AppSpacing.lg,
                                    AppSpacing.screenPadding,
                                    AppSpacing.md,
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      HoverScaleWrapper(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(0.06),
                                                blurRadius: 8,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                            border: Border.all(
                                              color: theme.colorScheme.primary.withOpacity(0.2),
                                              width: 2,
                                            ),
                                          ),
                                          child: TeamInitialAvatar(
                                            label: displayName,
                                            active: active,
                                            radius: 44,
                                            imageUrl:
                                                photoUrl.isEmpty ? null : photoUrl,
                                            showBorder: true,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 24),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              displayName,
                                              style: theme.textTheme.headlineSmall?.copyWith(
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: -0.3,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: [
                                                TeamMetadataChip(
                                                  label: roleLabel,
                                                  icon: Icons.badge_outlined,
                                                  tone: TeamChipTone.info,
                                                ),
                                                TeamMetadataChip(
                                                  label: statusLabel,
                                                  icon: isInvited
                                                      ? Icons.mark_email_unread_outlined
                                                      : active
                                                      ? Icons.check_circle_outline
                                                      : Icons.pause_circle_outline,
                                                  tone: isInvited
                                                      ? TeamChipTone.info
                                                      : active
                                                      ? TeamChipTone.success
                                                      : TeamChipTone.warning,
                                                ),
                                                TeamMetadataChip(
                                                  label: bookable
                                                      ? 'Calendar visible'
                                                      : 'Not bookable',
                                                  icon: Icons.calendar_month_outlined,
                                                  tone: bookable
                                                      ? TeamChipTone.success
                                                      : TeamChipTone.neutral,
                                                ),
                                                TeamMetadataChip(
                                                  label: clinicalAccess
                                                      ? 'Clinical access'
                                                      : 'Admin staff',
                                                  icon: clinicalAccess
                                                      ? Icons.description_outlined
                                                      : Icons.support_agent_outlined,
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              email.isNotEmpty
                                                  ? email
                                                  : 'UID: ${widget.memberUid}',
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                color: theme.colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Divider(height: 1, color: theme.dividerColor),
                              ],
                            );
                        final profileCategoryContent = Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                            _buildSectionBlock(
                              context,
                              title: 'Profile details',
                              subtitle: canEditThisProfile
                                  ? 'Update the display details used across team views and future booking surfaces.'
                                  : 'You can view this member profile, but only clinic managers can change another person’s details.',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (isSelf && !canManage)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: AppSpacing.md,
                                      ),
                                      child: Text(
                                        'You can update your own profile details here. Roles, permissions, and team status are still managed by clinic admins.',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                  if (canEditThisProfile) ...[
                                    Text(
                                      'Profile photo',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    OutlinedButton.icon(
                                      onPressed: _uploadingPhoto
                                          ? null
                                          : () => _uploadProfilePhoto(
                                                clinicId: clinicId,
                                                profileRepo: profileRepo,
                                              ),
                                      icon: _uploadingPhoto
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.upload_outlined),
                                      label: Text(
                                        _uploadingPhoto
                                            ? 'Uploading...'
                                            : 'Upload photo',
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.md),
                                  ],
                                  TextField(
                                    controller: _displayNameCtl,
                                    enabled: canEditThisProfile && !_savingProfile,
                                    decoration: _profileInputDecoration(
                                      context,
                                      label: 'Display name',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _titleCtl,
                                    enabled: canEditThisProfile && !_savingProfile,
                                    decoration: _profileInputDecoration(
                                      context,
                                      label: 'Title or job title',
                                      hint: 'e.g. Senior physiotherapist',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _phoneCtl,
                                    enabled: canEditThisProfile && !_savingProfile,
                                    decoration: _profileInputDecoration(
                                      context,
                                      label: 'Phone',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _emailCtl,
                                    enabled: canEditThisProfile && !_savingProfile,
                                    keyboardType: TextInputType.emailAddress,
                                    decoration: _profileInputDecoration(
                                      context,
                                      label: 'Contact email',
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: _bioCtl,
                                    enabled: canEditThisProfile && !_savingProfile,
                                    maxLines: 3,
                                    decoration: _profileInputDecoration(
                                      context,
                                      label: 'Short bio',
                                      hint:
                                          'e.g. A few sentences about your background or specialisms.',
                                      alignLabelWithHint: true,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Experience level',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 8),
                                  SegmentedButton<String>(
                                    segments: const [
                                      ButtonSegment<String>(
                                        value: 'junior',
                                        label: Text('Junior'),
                                      ),
                                      ButtonSegment<String>(
                                        value: 'senior',
                                        label: Text('Senior'),
                                      ),
                                    ],
                                    selected: {
                                      (_experienceLevel ?? 'senior').trim(),
                                    },
                                    onSelectionChanged:
                                        (canEditThisProfile && !_savingProfile)
                                            ? (selection) => setState(
                                                  () => _experienceLevel =
                                                      selection.first,
                                                )
                                            : null,
                                  ),
                                  if (_saveErr != null) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      _saveErr!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error,
                                          ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            _buildSectionBlock(
                              context,
                              title: 'Access and permissions',
                              subtitle:
                                  'Roles are the shorthand, but Firestore rules and callable checks ultimately follow the permission flags stored on the membership document.',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      TeamMetadataChip(
                                        label: canWriteBookings
                                            ? 'Can create bookings'
                                            : 'Read-only calendar',
                                        icon: canWriteBookings
                                            ? Icons.edit_calendar_outlined
                                            : Icons.calendar_view_day_outlined,
                                      ),
                                      TeamMetadataChip(
                                        label: clinicalAccess
                                            ? 'Can access clinical notes'
                                            : 'No clinical note access',
                                        icon: Icons.lock_open_outlined,
                                      ),
                                      if (isSelf)
                                        const TeamMetadataChip(
                                          label: 'This is your profile',
                                          icon: Icons.person_outline,
                                          tone: TeamChipTone.info,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (permissionPreview.displayLabels.isEmpty)
                                    Text(
                                      'No explicit permissions stored on this membership yet.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    )
                                  else
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        if (_permissionsExpanded) ...[
                                          ...permissionDisplayFromKeys(
                                            enabledPermissions,
                                            maxShown: enabledPermissions.length + 1,
                                          ).displayLabels.map((label) => TeamMetadataChip(label: label)),
                                          InkResponse(
                                            onTap: () => setState(() => _permissionsExpanded = false),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                              child: Text(
                                                'Show less',
                                                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                                  color: Theme.of(context).colorScheme.primary,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ] else ...[
                                          for (final label
                                              in permissionPreview.displayLabels)
                                            TeamMetadataChip(label: label),
                                          if (permissionPreview.overflowCount > 0)
                                            InkResponse(
                                              onTap: () => setState(() => _permissionsExpanded = true),
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                                child: TeamMetadataChip(
                                                  label:
                                                      '+${permissionPreview.overflowCount} more',
                                                ),
                                              ),
                                            ),
                                        ],
                                      ],
                                    ),
                                ],
                              ),
                            ),
                            ],
                            );
                        final bookingCategoryContent = _buildSectionBlock(
                              context,
                              title: 'Booking & visibility',
                              subtitle: canManage
                                  ? 'Control whether this clinician appears in the booking calendar and public booking, and restrict which services or locations they can be booked for. They must have Schedule read or Schedule write permission to appear in the internal booking clinician list.'
                                  : 'Only clinic managers can change booking settings.',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SwitchListTile(
                                    title: const Text('Active for internal booking'),
                                    subtitle: const Text('Show in calendar clinician dropdown'),
                                    value: _activeForBooking,
                                    onChanged: canManage && !_savingBookingMeta
                                        ? (v) => setState(() => _activeForBooking = v)
                                        : null,
                                  ),
                                  SwitchListTile(
                                    title: const Text('Visible in public booking'),
                                    subtitle: const Text('Show on the patient-facing online booking page'),
                                    value: _showInPublicBooking,
                                    onChanged: canManage && !_savingBookingMeta
                                        ? (v) => setState(() => _showInPublicBooking = v)
                                        : null,
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    enabled: canManage && !_savingBookingMeta,
                                    decoration: const InputDecoration(
                                      labelText: 'Public sort order',
                                      hintText: '0 = first',
                                    ),
                                    keyboardType: TextInputType.number,
                                    controller: _publicSortOrderCtl,
                                    onChanged: (v) {
                                      final n = int.tryParse(v);
                                      if (n != null) setState(() => _publicSortOrder = n);
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  _BookingMetaMultiSelect(
                                    label: 'Allowed locations',
                                    hint: 'Empty = all locations',
                                    enabled: canManage && !_savingBookingMeta,
                                    selectedIds: _allowedLocationIds,
                                    optionsStream: context.read<LocationsRepository>().watchLocations(clinicId).map(
                                      (list) => list.where((l) => l.active).map((l) => _SelectOption(l.id, l.name)).toList(),
                                    ),
                                    onChanged: (ids) => setState(() => _allowedLocationIds = ids),
                                  ),
                                  const SizedBox(height: 16),
                                  _BookingMetaMultiSelect(
                                    label: 'Allowed appointment types',
                                    hint: 'Empty = all types',
                                    enabled: canManage && !_savingBookingMeta,
                                    selectedIds: _serviceIdsAllowed,
                                    optionsStream: context.read<AppointmentTypesRepository>().watchActiveTypes(clinicId).map(
                                      (list) => list.map((t) => _SelectOption(t.id, t.name)).toList(),
                                    ),
                                    onChanged: (ids) => setState(() => _serviceIdsAllowed = ids),
                                  ),
                                  if (_bookingMetaSaveErr != null) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      _bookingMetaSaveErr!,
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context).colorScheme.error,
                                      ),
                                    ),
                                  ],
                                  if (canManage) ...[
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        FilledButton.tonalIcon(
                                          onPressed: _savingBookingMeta
                                              ? null
                                              : () => _saveBookingMeta(clinicId: clinicId, staffRepo: staffRepo),
                                          icon: _savingBookingMeta
                                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                              : const Icon(Icons.save_outlined),
                                          label: Text(_savingBookingMeta ? 'Saving...' : 'Save booking settings'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            );
                        final contentByCategory = switch (_selectedCategory) {
                          _MemberProfileCategory.profile => profileCategoryContent,
                          _MemberProfileCategory.bookingVisibility => bookingCategoryContent,
                          _MemberProfileCategory.availability => const SizedBox.shrink(),
                        };
                        final rail = _buildCategoryRail(theme);
                        final scrollContent = _selectedCategory == _MemberProfileCategory.availability
                            ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: PractitionerAvailabilityContent(
                                        clinicId: clinicId,
                                        practitionerId: widget.memberUid,
                                        practitionerName: displayName,
                                      ),
                                    ),
                                  ],
                                )
                            : SingleChildScrollView(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.screenPadding,
                                    vertical: AppSpacing.md,
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      contentByCategory,
                                      if (canEditThisProfile && _selectedCategory == _MemberProfileCategory.profile)
                                        const SizedBox(height: 96),
                                    ],
                                  ),
                                );
                        final workspaceContent = Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(AppRadius.workspace),
                            border: Border.all(
                              color: theme.dividerColor,
                              width: 1,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              if (constraints.maxWidth < 800) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    _buildCategoryTabBar(theme),
                                    persistentOverview,
                                    Expanded(child: scrollContent),
                                  ],
                                );
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  rail,
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        persistentOverview,
                                        Expanded(child: scrollContent),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        );
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(AppSpacing.screenPadding),
                                child: workspaceContent,
                              ),
                            ),
                            if (canEditThisProfile && _selectedCategory == _MemberProfileCategory.profile)
                              SafeArea(
                                top: false,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.screenPadding,
                                    vertical: 20,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surface,
                                    boxShadow: AppShadows.saveBarTop,
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: AppSizes.maxContentWidth,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          FilledButton.icon(
                                            onPressed: _savingProfile
                                                ? null
                                                : () => _saveProfile(
                                                      clinicId: clinicId,
                                                      profileRepo: profileRepo,
                                                      staffRepo: staffRepo,
                                                    ),
                                            icon: _savingProfile
                                                ? const SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                                  )
                                                : const Icon(Icons.save_outlined),
                                            label: Text(
                                              _savingProfile
                                                  ? 'Saving...'
                                                  : 'Save profile',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                          },
                        );
                      },
                    );
                  },
                );
  }

  @override
  Widget build(BuildContext context) {
    final clinicCtx = context.watch<ClinicContext>();
    final clinicId = (widget.clinicId?.trim().isNotEmpty == true
            ? widget.clinicId!.trim()
            : clinicCtx.clinicId)
        .trim();
    final guard = PermissionGuard(clinicCtx.permissions);
    final canManage = guard.has('members.manage');
    final canRead = guard.has('members.read') || canManage;
    final staffRepo = context.read<StaffRepository>();
    final profileRepo = context.read<StaffProfileRepository>();

    final body = _buildBody(
      context,
      clinicCtx: clinicCtx,
      clinicId: clinicId,
      canRead: canRead,
      canManage: canManage,
      staffRepo: staffRepo,
      profileRepo: profileRepo,
    );

    if (widget.embedInPanel) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const SizedBox.shrink(),
      ),
      backgroundColor: AppColors.settingsPageBg,
      body: body,
    );
  }
}

// ────────────────────────────────────────────────────────────
// Category tab chip (narrow layout)
// ────────────────────────────────────────────────────────────

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: theme.colorScheme.primaryContainer,
      checkmarkColor: theme.colorScheme.primary,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs + 2,
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// Helpers for the booking metadata multi-select controls
// ────────────────────────────────────────────────────────────

class _SelectOption {
  final String id;
  final String label;
  const _SelectOption(this.id, this.label);
}

class _BookingMetaMultiSelect extends StatelessWidget {
  final String label;
  final String hint;
  final bool enabled;
  final List<String> selectedIds;
  final Stream<List<_SelectOption>> optionsStream;
  final ValueChanged<List<String>> onChanged;

  const _BookingMetaMultiSelect({
    required this.label,
    required this.hint,
    required this.enabled,
    required this.selectedIds,
    required this.optionsStream,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<List<_SelectOption>>(
      stream: optionsStream,
      builder: (context, snap) {
        final options = snap.data ?? [];
        if (options.isEmpty) {
          return Text(
            '$label: none configured yet',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(hint, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final opt in options)
                  FilterChip(
                    label: Text(opt.label),
                    selected: selectedIds.contains(opt.id),
                    onSelected: enabled
                        ? (selected) {
                            final newIds = List<String>.from(selectedIds);
                            if (selected) {
                              if (!newIds.contains(opt.id)) newIds.add(opt.id);
                            } else {
                              newIds.remove(opt.id);
                            }
                            onChanged(newIds);
                          }
                        : null,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
