// lib/models/clinic_invite.dart
//
// Model for clinic invite docs: clinics/{clinicId}/invites/{inviteId}.
// Invites are function-only writes; client never writes.
// Raw token is never stored (hash only in doc).

import 'package:cloud_firestore/cloud_firestore.dart';

class ClinicInvite {
  final String clinicId;
  final String inviteId;

  final String email;
  final String role;
  final Map<String, dynamic> permissions;

  /// active | accepted | revoked | expired (derived or stored)
  final String status;

  final DateTime? expiresAt;
  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? acceptedAt;
  final String? acceptedByUid;

  ClinicInvite({
    required this.clinicId,
    required this.inviteId,
    required this.email,
    required this.role,
    required this.permissions,
    required this.status,
    this.expiresAt,
    this.createdByUid,
    this.createdAt,
    this.acceptedAt,
    this.acceptedByUid,
  });

  static String _str(dynamic v) => (v ?? '').toString().trim();
  static DateTime? _ts(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    return null;
  }
  static Map<String, dynamic> _map(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  factory ClinicInvite.fromFirestore({
    required String clinicId,
    required String inviteId,
    required Map<String, dynamic> data,
  }) {
    final status = _str(data['status']);
    final effectiveStatus = status.isEmpty ? 'active' : status;

    return ClinicInvite(
      clinicId: clinicId,
      inviteId: inviteId,
      email: _str(data['email']),
      role: _str(data['role']).isEmpty ? _str(data['roleId']) : _str(data['role']),
      permissions: _map(data['permissions']),
      status: effectiveStatus,
      expiresAt: _ts(data['expiresAt']),
      createdByUid: _str(data['createdByUid']).isEmpty ? null : _str(data['createdByUid']),
      createdAt: _ts(data['createdAt']),
      acceptedAt: _ts(data['acceptedAt']),
      acceptedByUid: _str(data['acceptedByUid']).isEmpty ? null : _str(data['acceptedByUid']),
    );
  }

  bool get isActive => status == 'active' || status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isExpired {
    final e = expiresAt;
    if (e == null) return false;
    return e.isBefore(DateTime.now());
  }
}
