// lib/models/practitioner_availability.dart
//
// Base recurring availability for a practitioner.
// Source: clinics/{clinicId}/practitioners/{practitionerId}/availability/{availabilityId}
// Writes via callable settingsUpsertPractitionerAvailability only.

import 'package:cloud_firestore/cloud_firestore.dart';

/// One time block on a single day (Mon=1 … Sun=7).
class AvailabilityBlock {
  const AvailabilityBlock({
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    this.bookableOnline = true,
  });

  final int dayOfWeek;
  final String startTime;
  final String endTime;
  final bool bookableOnline;

  Map<String, dynamic> toJson() => {
        'dayOfWeek': dayOfWeek,
        'startTime': startTime,
        'endTime': endTime,
        'bookableOnline': bookableOnline,
      };

  static AvailabilityBlock fromJson(Map<String, dynamic> map) {
    return AvailabilityBlock(
      dayOfWeek: _int(map['dayOfWeek'], 1, 7) ?? 1,
      startTime: _string(map['startTime'], '09:00'),
      endTime: _string(map['endTime'], '17:00'),
      bookableOnline: map['bookableOnline'] != false,
    );
  }

  static int? _int(dynamic v, int min, int max) {
    if (v == null) return null;
    final n = v is int ? v : int.tryParse(v.toString());
    if (n == null || n < min || n > max) return null;
    return n;
  }

  static String _string(dynamic v, String fallback) {
    if (v == null) return fallback;
    final s = (v is String ? v : v.toString()).trim();
    return s.isEmpty ? fallback : s;
  }
}

/// Recurrence: frequency (weekly/biweekly/monthly) + interval 1–12.
class RecurrenceRule {
  const RecurrenceRule({
    this.frequency = 'weekly',
    this.interval = 1,
  });

  final String frequency;
  final int interval;

  Map<String, dynamic> toJson() => {'frequency': frequency, 'interval': interval};

  static RecurrenceRule fromJson(Map<String, dynamic>? map) {
    if (map == null) return const RecurrenceRule();
    return RecurrenceRule(
      frequency: _frequency(map['frequency']),
      interval: _interval(map['interval']),
    );
  }

  static String _frequency(dynamic v) {
    final s = (v is String ? v : v?.toString() ?? '').trim().toLowerCase();
    if (s == 'biweekly' || s == 'monthly') return s;
    return 'weekly';
  }

  static int _interval(dynamic v) {
    if (v == null) return 1;
    final n = v is int ? v : int.tryParse(v.toString());
    if (n == null || n < 1 || n > 12) return 1;
    return n;
  }
}

/// One recurring availability rule for a practitioner.
class PractitionerAvailability {
  const PractitionerAvailability({
    required this.id,
    required this.locationId,
    required this.startDate,
    this.endDate,
    this.recurrenceRule = const RecurrenceRule(),
    this.blocks = const [],
    this.description,
    this.active = true,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String locationId;
  final String startDate;
  final String? endDate;
  final RecurrenceRule recurrenceRule;
  final List<AvailabilityBlock> blocks;
  final String? description;
  final bool active;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static PractitionerAvailability fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final id = doc.id;
    final blocksRaw = data['blocks'];
    final blocks = blocksRaw is List
        ? blocksRaw
            .map((e) => e is Map ? AvailabilityBlock.fromJson(Map<String, dynamic>.from(e)) : null)
            .whereType<AvailabilityBlock>()
            .toList()
        : <AvailabilityBlock>[];
    return PractitionerAvailability(
      id: id,
      locationId: _str(data['locationId']) ?? id,
      startDate: _str(data['startDate']) ?? '',
      endDate: _strNull(data['endDate']),
      recurrenceRule: data['recurrenceRule'] is Map
          ? RecurrenceRule.fromJson(Map<String, dynamic>.from(data['recurrenceRule'] as Map))
          : const RecurrenceRule(),
      blocks: blocks,
      description: _strNull(data['description']),
      active: data['active'] != false,
      createdAt: _parseTimestamp(data['createdAt']),
      updatedAt: _parseTimestamp(data['updatedAt']),
    );
  }

  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = (v is String ? v : v.toString()).trim();
    return s.isEmpty ? null : s;
  }

  static String? _strNull(dynamic v) {
    if (v == null) return null;
    final s = (v is String ? v : v.toString()).trim();
    return s.isEmpty ? null : s;
  }

  static DateTime? _parseTimestamp(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return null;
  }

  /// Blocks grouped by dayOfWeek (1–7). Useful for day-by-day UI.
  Map<int, List<AvailabilityBlock>> get blocksByDay {
    final map = <int, List<AvailabilityBlock>>{};
    for (final b in blocks) {
      final day = b.dayOfWeek.clamp(1, 7);
      map.putIfAbsent(day, () => []).add(b);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.startTime.compareTo(b.startTime));
    }
    return map;
  }

  /// Patch map for settingsUpsertPractitionerAvailability callable.
  Map<String, dynamic> toUpsertPatch() {
    return {
      'locationId': locationId,
      'startDate': startDate,
      'endDate': endDate ?? '',
      'recurrenceRule': recurrenceRule.toJson(),
      'blocks': blocks.map((b) => b.toJson()).toList(),
      'description': description ?? '',
      'active': active,
    };
  }

  bool get hasAnyBookableOnline => blocks.any((b) => b.bookableOnline);
}
