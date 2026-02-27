// lib/app/clinic_session.dart
import '../models/clinic_permissions.dart';
import '../models/membership.dart';

/// Thrown when [ClinicSession.requirePerm] fails (no boolean permission flag).
class PermissionDeniedException implements Exception {
  PermissionDeniedException(this.permissionKey);
  final String permissionKey;
  @override
  String toString() => 'PermissionDeniedException($permissionKey)';
}

class ClinicSession {
  final String clinicId;
  final Membership membership;
  final ClinicPermissions permissions;

  ClinicSession({
    required this.clinicId,
    required this.membership,
    required this.permissions,
  });

  bool get isActive => membership.active == true;

  /// True if the permission flag is present and true (boolean flags only, no role inference).
  bool can(String permissionKey) => permissions.has(permissionKey);

  /// Throws [PermissionDeniedException] if [can(permissionKey)] is false.
  void requirePerm(String permissionKey) {
    if (!can(permissionKey)) throw PermissionDeniedException(permissionKey);
  }

  /// Raw map for guards/debug
  Map<String, dynamic> get permissionsRaw => membership.permissions;

  @override
  String toString() => 'ClinicSession(clinicId: $clinicId, active: $isActive)';
}
