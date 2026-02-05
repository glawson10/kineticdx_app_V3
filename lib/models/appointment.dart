import 'package:cloud_firestore/cloud_firestore.dart';

class Appointment {
  final String id;
  final String clinicId;

  /// "admin" | "new" | "followup"
  final String kind;

  final String patientId;
  final String serviceId;
  final String practitionerId;

  /// Denormalized display fields (written by createAppointmentFn)
  final String patientName;
  final String serviceName;
  final String practitionerName;

  /// ✅ These MUST be local wall-clock times for the calendar UI.
  final DateTime start;
  final DateTime end;

  /// "booked" | "attended" | "cancelled" | "missed"
  final String status;

  // ─────────────────────────────
  // Closure override metadata
  // ─────────────────────────────
  final bool closureOverride;
  final String? closureOverrideByUid;
  final DateTime? closureOverrideAt;

  Appointment({
    required this.id,
    required this.clinicId,
    required this.kind,
    required this.patientId,
    required this.serviceId,
    required this.practitionerId,
    required this.patientName,
    required this.serviceName,
    required this.practitionerName,
    required this.start,
    required this.end,
    required this.status,
    required this.closureOverride,
    this.closureOverrideByUid,
    this.closureOverrideAt,
  });

  static DateTime _fallbackEpoch() => DateTime.fromMillisecondsSinceEpoch(0);

  static DateTime _toLocalDate(dynamic v) {
    if (v == null) return _fallbackEpoch();

    if (v is Timestamp) {
      // ✅ Convert Firestore timestamp -> DateTime -> LOCAL
      return v.toDate().toLocal();
    }

    if (v is DateTime) {
      // ✅ Normalize any DateTime to local for UI consistency
      return v.toLocal();
    }

    if (v is String) {
      final parsed = DateTime.tryParse(v);
      if (parsed == null) return _fallbackEpoch();
      return parsed.toLocal();
    }

    return _fallbackEpoch();
  }

  static DateTime _readStart(Map<String, dynamic> data) {
    if (data['startAt'] != null) return _toLocalDate(data['startAt']);
    return _toLocalDate(data['start']);
  }

  static DateTime _readEnd(Map<String, dynamic> data) {
    if (data['endAt'] != null) return _toLocalDate(data['endAt']);
    return _toLocalDate(data['end']);
  }

  factory Appointment.fromFirestore(String id, Map<String, dynamic> data) {
    final kindRaw = (data['kind'] ?? 'followup').toString().trim();
    final kind = kindRaw.isEmpty ? 'followup' : kindRaw;

    return Appointment(
      id: id,
      clinicId: (data['clinicId'] ?? '').toString(),
      kind: kind,

      patientId: (data['patientId'] ?? '').toString(),
      serviceId: (data['serviceId'] ?? '').toString(),
      practitionerId: (data['practitionerId'] ?? '').toString(),

      patientName: (data['patientName'] ?? '').toString(),
      serviceName: (data['serviceName'] ?? '').toString(),
      practitionerName: (data['practitionerName'] ?? '').toString(),

      // ✅ LOCAL times
      start: _readStart(data),
      end: _readEnd(data),

      status: (data['status'] ?? 'booked').toString(),

      closureOverride: data['closureOverride'] == true,
      closureOverrideByUid: data['closureOverrideByUid']?.toString(),
      closureOverrideAt: data['closureOverrideAt'] != null
          ? _toLocalDate(data['closureOverrideAt'])
          : null,
    );
  }

  bool get isAdmin => kind.toLowerCase() == 'admin' || patientId.trim().isEmpty;

  bool get isClosureOverride => closureOverride == true;

  String get kindLabel {
    switch (kind.toLowerCase()) {
      case 'new':
        return 'New';
      case 'followup':
        return 'Follow-up';
      case 'admin':
        return 'Admin';
      default:
        return isAdmin ? 'Admin' : 'Booking';
    }
  }

  String get statusLabel {
    switch (status.toLowerCase()) {
      case 'attended':
        return 'Attended';
      case 'cancelled':
        return 'Cancelled';
      case 'missed':
        return 'Missed';
      case 'booked':
      default:
        return 'Booked';
    }
  }

  String get displayTitle {
    if (isAdmin) return 'Admin';
    final name = patientName.trim();
    return name.isEmpty ? 'Patient' : name;
  }
}
