// lib/models/membership_index.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class MembershipIndex {
  final String clinicId;

  /// Role template key (e.g. owner/manager/clinician/adminStaff/viewer).
  /// Back-compat: supports roleId (old) and role (new).
  final String roleId;

  /// Optional lifecycle field (invited | active | suspended).
  final String? status;

  /// Back-compat bool used by older docs.
  /// Back-compat: if missing, treat as active.
  /// If status == suspended -> active=false
  /// If status == invited -> active=false (so clinic picker doesn’t route into clinic shell)
  final bool active;

  final DateTime createdAt;
  final String? clinicNameCache;

  MembershipIndex({
    required this.clinicId,
    required this.roleId,
    required this.active,
    required this.createdAt,
    this.clinicNameCache,
    this.status,
  });

  static DateTime _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static String _string(dynamic v) => (v ?? '').toString();

  static String _roleFrom(Map<String, dynamic> data) {
    final role = _string(data['role']).trim();
    if (role.isNotEmpty) return role;

    final roleId = _string(data['roleId']).trim();
    if (roleId.isNotEmpty) return roleId;

    return '';
  }

  static bool _activeFrom(Map<String, dynamic> data) {
    final status = _string(data['status']).trim();
    if (status == 'suspended') return false;
    if (status == 'active') return true;
    if (status == 'invited') return false;

    if (data.containsKey('active')) return data['active'] == true;

    // Back-compat: missing active => active
    return true;
  }

  factory MembershipIndex.fromFirestore(String clinicId, Map<String, dynamic> data) {
    final statusStr = _string(data['status']).trim();
    final status = statusStr.isEmpty ? null : statusStr;

    return MembershipIndex(
      clinicId: clinicId,
      roleId: _roleFrom(data),
      active: _activeFrom(data),
      clinicNameCache: _string(data['clinicNameCache']).trim().isEmpty
          ? null
          : _string(data['clinicNameCache']).trim(),
      createdAt: _ts(data['createdAt']),
      status: status,
    );
  }
}
