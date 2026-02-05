import 'package:cloud_firestore/cloud_firestore.dart';

class OutcomeMeasure {
  final String id;

  final String name;
  final String? fullName;
  final List<String> tags;
  final String? scoreFormatHint;

  final bool active;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  OutcomeMeasure({
    required this.id,
    required this.name,
    required this.fullName,
    required this.tags,
    required this.scoreFormatHint,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
  });

  factory OutcomeMeasure.fromFirestore(String id, Map<String, dynamic> data) {
    return OutcomeMeasure(
      id: id,
      name: (data['name'] ?? '').toString(),
      fullName: (data['fullName'] as String?)?.trim().isEmpty == true
          ? null
          : data['fullName'] as String?,
      tags: (data['tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      scoreFormatHint: (data['scoreFormatHint'] as String?)?.trim().isEmpty == true
          ? null
          : data['scoreFormatHint'] as String?,
      active: (data['active'] ?? true) == true,
      createdAt: _tsToDate(data['createdAt']),
      updatedAt: _tsToDate(data['updatedAt']),
    );
  }

  static DateTime? _tsToDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }
}
