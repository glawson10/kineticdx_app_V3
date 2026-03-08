// lib/models/waitlist_entry.dart
// Waitlist entry for slot matching.

import 'package:cloud_firestore/cloud_firestore.dart';

class WaitlistEntry {
  const WaitlistEntry({
    required this.id,
    required this.clinicId,
    this.patientId,
    this.patientDisplayName,
    this.priority = 0,
    this.notes,
    this.preferredPractitionerIds = const [],
    this.preferredAppointmentTypeIds = const [],
    this.earliestDate,
    this.latestDate,
    this.createdAt,
  });

  final String id;
  final String clinicId;
  final String? patientId;
  final String? patientDisplayName;
  final int priority;
  final String? notes;
  final List<String> preferredPractitionerIds;
  final List<String> preferredAppointmentTypeIds;
  final DateTime? earliestDate;
  final DateTime? latestDate;
  final DateTime? createdAt;

  String get displayLabel => (patientDisplayName?.trim().isNotEmpty == true)
      ? patientDisplayName!
      : (patientId != null && patientId!.length > 8
          ? '${patientId!.substring(0, 8)}…'
          : 'Unknown');

  /// Map for Firestore write (omit id; caller adds createdAt).
  Map<String, dynamic> toMap() {
    return {
      'clinicId': clinicId,
      if (patientId != null) 'patientId': patientId,
      if (patientDisplayName != null && patientDisplayName!.isNotEmpty)
        'patientDisplayName': patientDisplayName,
      'priority': priority,
      if (notes != null && notes!.isNotEmpty) 'notes': notes,
      if (preferredPractitionerIds.isNotEmpty)
        'preferredPractitionerIds': preferredPractitionerIds,
      if (preferredAppointmentTypeIds.isNotEmpty)
        'preferredAppointmentTypeIds': preferredAppointmentTypeIds,
      if (earliestDate != null) 'earliestDate': Timestamp.fromDate(earliestDate!),
      if (latestDate != null) 'latestDate': Timestamp.fromDate(latestDate!),
    };
  }
}
