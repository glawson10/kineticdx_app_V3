import 'package:cloud_firestore/cloud_firestore.dart';

class ClinicMember {
  final String clinicId;
  final String uid;

  final String roleId;
  final bool active;
  final Map<String, dynamic> permissions;

  final DateTime createdAt;
  final DateTime updatedAt;

  ClinicMember({
    required this.clinicId,
    required this.uid,
    required this.roleId,
    required this.active,
    required this.permissions,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ClinicMember.fromFirestore(
    String clinicId,
    String uid,
    Map<String, dynamic> data,
  ) {
    DateTime ts(dynamic v) {
      if (v is Timestamp) return v.toDate();
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    return ClinicMember(
      clinicId: clinicId,
      uid: uid,
      roleId: (data['roleId'] ?? '').toString(),
      active: data['active'] == true,
      permissions: Map<String, dynamic>.from((data['permissions'] ?? {}) as Map),
      createdAt: ts(data['createdAt']),
      updatedAt: ts(data['updatedAt']),
    );
  }
}
