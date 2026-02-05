// lib/app/clinic_session.dart
import '../models/clinic_permissions.dart';
import '../models/membership.dart';

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

  bool can(String permissionKey) => permissions.has(permissionKey);

  /// Raw map for guards/debug
  Map<String, dynamic> get permissionsRaw => membership.permissions;

  @override
  String toString() => 'ClinicSession(clinicId: $clinicId, active: $isActive)';
}
