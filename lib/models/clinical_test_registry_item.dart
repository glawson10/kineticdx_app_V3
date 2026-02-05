import 'package:cloud_firestore/cloud_firestore.dart';

class ClinicalTestRegistryItem {
  final String id;

  final String name;
  final String? shortName;
  final List<String> bodyRegions;
  final List<String> tags;
  final String category;

  final String? instructions;
  final String? positiveCriteria;
  final String? contraindications;
  final String? interpretation;

  final String resultType; // e.g. "ternary"
  final List<String> allowedResults;

  final bool active;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  ClinicalTestRegistryItem({
    required this.id,
    required this.name,
    required this.shortName,
    required this.bodyRegions,
    required this.tags,
    required this.category,
    required this.instructions,
    required this.positiveCriteria,
    required this.contraindications,
    required this.interpretation,
    required this.resultType,
    required this.allowedResults,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ClinicalTestRegistryItem.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return ClinicalTestRegistryItem(
      id: id,
      name: (data['name'] ?? '').toString(),
      shortName: (data['shortName'] as String?)?.trim().isEmpty == true
          ? null
          : data['shortName'] as String?,
      bodyRegions: (data['bodyRegions'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      tags: (data['tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      category: (data['category'] ?? 'special_test').toString(),
      instructions: data['instructions'] as String?,
      positiveCriteria: data['positiveCriteria'] as String?,
      contraindications: data['contraindications'] as String?,
      interpretation: data['interpretation'] as String?,
      resultType: (data['resultType'] ?? 'ternary').toString(),
      allowedResults: (data['allowedResults'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
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
