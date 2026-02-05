// lib/models/membership.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Membership {
  final String clinicId;

  /// Role template key (e.g. "owner", "manager", "clinician", "adminStaff").
  ///
  /// Back-compat:
  /// - older docs may store this as roleId
  /// - newer docs may store this as role
  final String roleId;

  /// Preferred lifecycle field (invited | active | suspended).
  /// Back-compat: may be missing on older docs.
  final String? status;

  /// Back-compat boolean. In V3 rules you treat missing active as active.
  ///
  /// We mirror that here:
  /// - if status == "suspended" -> active = false
  /// - else if "active" field exists -> use it
  /// - else -> active = true
  final bool active;

  /// Authoritative permissions map from membership doc.
  final Map<String, dynamic> permissions;

  final DateTime createdAt;
  final DateTime? updatedAt;

  Membership({
    required this.clinicId,
    required this.roleId,
    required this.active,
    required this.permissions,
    required this.createdAt,
    this.updatedAt,
    this.status,
  });

  static DateTime _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static DateTime? _tsNullable(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return null;
  }

  static Map<String, dynamic> _map(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  static String _string(dynamic v) => (v ?? '').toString();

  /// Normalizes role field across legacy + canonical docs.
  static String _roleFrom(Map<String, dynamic> data) {
    // Prefer "role" if present (newer)
    final role = _string(data['role']).trim();
    if (role.isNotEmpty) return role;

    // Fall back to "roleId" (older)
    final roleId = _string(data['roleId']).trim();
    if (roleId.isNotEmpty) return roleId;

    return '';
  }

  /// Normalizes active field across:
  /// - status-based lifecycle (preferred)
  /// - legacy bool active
  /// - missing active (treat as active)
  static bool _activeFrom(Map<String, dynamic> data) {
    final status = _string(data['status']).trim();
    if (status == 'suspended') return false;
    if (status == 'active') return true;
    if (status == 'invited') {
      // Invited is not "fully active" for access in your rules,
      // but you can decide this later. For now, treat invited as active=false
      // so UI can block privileged screens until accepted.
      return false;
    }

    // Legacy bool
    if (data.containsKey('active')) return data['active'] == true;

    // Back-compat: missing active => active
    return true;
  }

  factory Membership.fromFirestore(String clinicId, Map<String, dynamic> data) {
    final perms = _map(data['permissions']);

    final statusStr = _string(data['status']).trim();
    final status = statusStr.isEmpty ? null : statusStr;

    return Membership(
      clinicId: clinicId,
      roleId: _roleFrom(data),
      status: status,
      active: _activeFrom(data),
      permissions: perms,
      createdAt: _ts(data['createdAt']),
      updatedAt: _tsNullable(data['updatedAt']),
    );
  }
}
