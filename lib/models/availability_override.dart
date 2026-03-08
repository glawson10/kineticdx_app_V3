// lib/models/availability_override.dart
//
// Temporary availability exception (sickness, holiday, training).
// Path: clinics/{clinicId}/practitioners/{practitionerId}/overrides/{overrideId}
// Writes via settingsUpsertPractitionerOverride / settingsDeletePractitionerOverride.

import 'package:cloud_firestore/cloud_firestore.dart';

/// Override reason for filtering and display.
enum OverrideReason { sickness, holiday, training, other }

/// Date-bounded override: mark a span as available or unavailable.
/// Overrides take precedence over base availability in resolution order.
class PractitionerOverride {
  const PractitionerOverride({
    required this.id,
    required this.fromAt,
    required this.toAt,
    required this.isAvailable,
    this.locationId,
    this.description,
    this.reason,
  });

  final String id;
  final DateTime fromAt;
  final DateTime toAt;
  final bool isAvailable;
  final String? locationId;
  final String? description;
  final String? reason;

  OverrideReason get reasonEnum {
    switch (reason?.toLowerCase()) {
      case 'sickness':
        return OverrideReason.sickness;
      case 'holiday':
        return OverrideReason.holiday;
      case 'training':
        return OverrideReason.training;
      default:
        return OverrideReason.other;
    }
  }

  static DateTime _fromTimestamp(dynamic v) {
    if (v == null) return DateTime.utc(2000, 1, 1);
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v.toUtc();
    if (v is String) {
      final d = DateTime.tryParse(v);
      return d?.toUtc() ?? DateTime.utc(2000, 1, 1);
    }
    return DateTime.utc(2000, 1, 1);
  }

  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = (v is String ? v : v.toString()).trim();
    return s.isEmpty ? null : s;
  }

  factory PractitionerOverride.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return PractitionerOverride(
      id: doc.id,
      fromAt: _fromTimestamp(data['fromAt']),
      toAt: _fromTimestamp(data['toAt']),
      isAvailable: data['isAvailable'] == true,
      locationId: _str(data['locationId']),
      description: _str(data['description']),
      reason: _str(data['reason']),
    );
  }

  /// Payload for settingsUpsertPractitionerOverride (timestamps as ms for callable).
  Map<String, dynamic> toUpsertPatch() => {
        'fromAt': fromAt.millisecondsSinceEpoch,
        'toAt': toAt.millisecondsSinceEpoch,
        'isAvailable': isAvailable,
        'locationId': locationId,
        'description': description ?? '',
        'reason': reason ?? '',
      };
}

/// Legacy alias for backward compatibility.
typedef AvailabilityOverride = PractitionerOverride;
