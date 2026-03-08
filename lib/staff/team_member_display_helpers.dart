// lib/staff/team_member_display_helpers.dart
//
// Deterministic, friendly display for team list: permission keys, role, status.
// Used by StaffSettingsScreen (Team → Members list).

import '/config/permission_keys.dart';

/// Human-readable labels for common permission keys (sorted display uses these).
const Map<String, String> _permissionLabels = {
  'settings.read': 'Settings read',
  'settings.write': 'Settings write',
  'members.read': 'Members read',
  'members.manage': 'Members manage',
  'schedule.read': 'Schedule read',
  'schedule.write': 'Schedule write',
  'patients.read': 'Patients read',
  'patients.write': 'Patients write',
  'clinical.read': 'Clinical read',
  'clinical.write': 'Clinical write',
  'notes.read': 'Notes read',
  'notes.write.own': 'Notes write (own)',
  'notes.write.any': 'Notes write (any)',
  'services.manage': 'Services manage',
  'resources.manage': 'Resources manage',
  'registries.manage': 'Registries manage',
  'audit.read': 'Audit read',
  'billing.manage': 'Billing manage',
};

/// Returns sorted (alphabetically) permission keys, then takes [maxShown] (default 5),
/// with human labels where defined. [overflowCount] is how many are not shown.
/// Use for deterministic, friendly chip display + "+N" when overflowCount > 0.
({
  List<String> displayLabels,
  int overflowCount,
}) permissionDisplayFromKeys(
  List<String> permissionKeys, {
  int maxShown = 5,
}) {
  final sorted = List<String>.from(permissionKeys)..sort();
  final overflow = sorted.length > maxShown ? sorted.length - maxShown : 0;
  final taken = sorted.take(maxShown).toList();
  final displayLabels = taken
      .map((k) => _permissionLabels[k] ?? k)
      .toList();
  return (displayLabels: displayLabels, overflowCount: overflow);
}

/// Resolves role for display: [roleName] from doc if non-empty, else known roleId → label, else raw [roleId].
String roleDisplayLabel({
  required String roleId,
  String? roleName,
}) {
  final name = (roleName ?? '').toString().trim();
  if (name.isNotEmpty) return name;
  return RoleTemplateIds.displayName(roleId.trim());
}

/// Single status label for chip/text. No conflicting "Inactive" when invited.
/// - status == invited → "Invited" only
/// - active == false and not invited → "Suspended"
/// - else → "Active"
/// If [status] is missing/empty, infer from [active] only.
String statusDisplayLabel({
  required String status,
  required bool active,
}) {
  final s = status.trim().toLowerCase();
  if (s == 'invited') return 'Invited';
  if (!active && s != 'invited') return 'Suspended';
  if (s.isNotEmpty) return s == 'active' ? 'Active' : s == 'suspended' ? 'Suspended' : status;
  return active ? 'Active' : 'Suspended';
}

String memberDisplayName(Map<String, dynamic> data, String uid) {
  final displayName =
      (data['displayName'] ?? data['fullName'] ?? data['name'] ?? '')
          .toString()
          .trim();
  if (displayName.isNotEmpty) return displayName;
  final email = memberEmail(data);
  if (email.isNotEmpty) return email;
  return uid;
}

String memberEmail(Map<String, dynamic> data) {
  return (data['invitedEmail'] ?? data['email'] ?? '').toString().trim();
}

List<String> enabledPermissionKeys(Map<String, dynamic> data) {
  final permsRaw = data['permissions'];
  if (permsRaw is! Map) return const [];
  final perms = Map<String, dynamic>.from(permsRaw);
  return perms.entries
      .where((entry) => entry.value == true)
      .map((entry) => entry.key)
      .toList()
    ..sort();
}

bool memberHasPermission(Map<String, dynamic> data, String key) {
  return enabledPermissionKeys(data).contains(key);
}

bool memberIsBookable(Map<String, dynamic> data) {
  return memberHasPermission(data, PermissionKeys.scheduleRead) ||
      memberHasPermission(data, PermissionKeys.scheduleWrite);
}

bool memberCanCreateBookings(Map<String, dynamic> data) {
  return memberHasPermission(data, PermissionKeys.scheduleWrite);
}

bool memberHasClinicalAccess(Map<String, dynamic> data) {
  return memberHasPermission(data, PermissionKeys.clinicalRead) ||
      memberHasPermission(data, PermissionKeys.notesRead);
}
