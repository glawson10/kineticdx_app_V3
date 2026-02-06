import 'package:cloud_firestore/cloud_firestore.dart';

class SoapPayload {
  final String subjective;
  final String objective;
  final String assessment;
  final String plan;

  const SoapPayload({
    required this.subjective,
    required this.objective,
    required this.assessment,
    required this.plan,
  });

  factory SoapPayload.empty() {
    return const SoapPayload(
      subjective: '',
      objective: '',
      assessment: '',
      plan: '',
    );
  }

  factory SoapPayload.fromMap(Map<String, dynamic>? data) {
    final m = data ?? const <String, dynamic>{};
    return SoapPayload(
      subjective: (m['subjective'] ?? '').toString(),
      objective: (m['objective'] ?? '').toString(),
      assessment: (m['assessment'] ?? '').toString(),
      plan: (m['plan'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'subjective': subjective,
      'objective': objective,
      'assessment': assessment,
      'plan': plan,
    };
  }
}

class ClinicalNote {
  final String id;
  final int schemaVersion;

  final String clinicId;
  final String patientId;
  final String? appointmentId;

  /// "initial" | "followup"
  final String type;

  /// Template id from clinics/{clinicId}/settings/notes
  final String templateId;

  /// "draft" | "final"
  final String status;

  final SoapPayload soap;

  /// Reference only (never auto-populated into SOAP).
  final String? relatedIntakeSessionId;

  final String createdByUid;
  final String? updatedByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ClinicalNote({
    required this.id,
    required this.schemaVersion,
    required this.clinicId,
    required this.patientId,
    required this.appointmentId,
    required this.type,
    required this.templateId,
    required this.status,
    required this.soap,
    required this.relatedIntakeSessionId,
    required this.createdByUid,
    required this.updatedByUid,
    required this.createdAt,
    required this.updatedAt,
  });

  static DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  static String _safeString(dynamic v, {String fallback = ''}) {
    final s = (v ?? '').toString();
    return s.isEmpty ? fallback : s;
  }

  static String _safeType(dynamic v) {
    final s = _safeString(v, fallback: 'initial');
    return (s == 'followup' || s == 'initial') ? s : 'initial';
  }

  static String _safeStatus(dynamic v) {
    final s = _safeString(v, fallback: 'draft');
    return (s == 'final' || s == 'draft') ? s : 'draft';
  }

  factory ClinicalNote.fromFirestore(String id, Map<String, dynamic> data) {
    return ClinicalNote(
      id: id,
      schemaVersion: (data['schemaVersion'] as num?)?.toInt() ?? 1,
      clinicId: _safeString(data['clinicId']),
      patientId: _safeString(data['patientId']),
      appointmentId: (data['appointmentId'] ?? '').toString().trim().isEmpty
          ? null
          : data['appointmentId'].toString(),
      type: _safeType(data['type']),
      templateId: _safeString(data['templateId'], fallback: 'basicSoap'),
      status: _safeStatus(data['status']),
      soap: SoapPayload.fromMap(data['soap'] as Map<String, dynamic>?),
      relatedIntakeSessionId:
          (data['relatedIntakeSessionId'] ?? '').toString().trim().isEmpty
              ? null
              : data['relatedIntakeSessionId'].toString(),
      createdByUid: _safeString(data['createdByUid']),
      updatedByUid: (data['updatedByUid'] ?? '').toString().trim().isEmpty
          ? null
          : data['updatedByUid'].toString(),
      createdAt: _toDate(data['createdAt']),
      updatedAt: _toDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'schemaVersion': schemaVersion,
      'clinicId': clinicId,
      'patientId': patientId,
      'appointmentId': appointmentId,
      'type': type,
      'templateId': templateId,
      'status': status,
      'soap': soap.toMap(),
      'relatedIntakeSessionId': relatedIntakeSessionId,
      'createdByUid': createdByUid,
      'updatedByUid': updatedByUid,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  ClinicalNote copyWith({
    String? id,
    int? schemaVersion,
    String? clinicId,
    String? patientId,
    String? appointmentId,
    String? type,
    String? templateId,
    String? status,
    SoapPayload? soap,
    String? relatedIntakeSessionId,
    String? createdByUid,
    String? updatedByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ClinicalNote(
      id: id ?? this.id,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      clinicId: clinicId ?? this.clinicId,
      patientId: patientId ?? this.patientId,
      appointmentId: appointmentId ?? this.appointmentId,
      type: type ?? this.type,
      templateId: templateId ?? this.templateId,
      status: status ?? this.status,
      soap: soap ?? this.soap,
      relatedIntakeSessionId:
          relatedIntakeSessionId ?? this.relatedIntakeSessionId,
      createdByUid: createdByUid ?? this.createdByUid,
      updatedByUid: updatedByUid ?? this.updatedByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
