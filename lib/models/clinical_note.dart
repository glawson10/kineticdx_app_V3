import 'package:cloud_firestore/cloud_firestore.dart';

enum ClinicalNoteStatus { draft, signed, locked }
enum EncounterType { initial, followup }
enum NoteTemplate { standard, custom }

class ClinicalNote {
  final String id;

  final int schemaVersion;

  final String clinicId;
  final String patientId;
  final String episodeId;

  final String authorUid;

  final ClinicalNoteStatus status;
  final EncounterType encounterType;
  final NoteTemplate template;

  final String? appointmentId;
  final String? assessmentId;
  final String? previousNoteId;

  final int version;

  /// Canonical current SOAP snapshot.
  final Map<String, dynamic> current;

  final int amendmentCount;
  final DateTime? lastAmendedAt;
  final String? lastAmendedByUid;

  final DateTime? signedAt;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  ClinicalNote({
    required this.id,
    required this.schemaVersion,
    required this.clinicId,
    required this.patientId,
    required this.episodeId,
    required this.authorUid,
    required this.status,
    required this.encounterType,
    required this.template,
    required this.version,
    required this.current,
    required this.amendmentCount,
    required this.lastAmendedAt,
    required this.lastAmendedByUid,
    required this.signedAt,
    required this.createdAt,
    required this.updatedAt,
    this.appointmentId,
    this.assessmentId,
    this.previousNoteId,
  });

  static DateTime? _ts(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  static ClinicalNoteStatus _status(String? s) {
    switch (s) {
      case 'signed':
        return ClinicalNoteStatus.signed;
      case 'locked':
        return ClinicalNoteStatus.locked;
      case 'draft':
      default:
        return ClinicalNoteStatus.draft;
    }
  }

  static EncounterType _encounter(String? s) {
    switch (s) {
      case 'followup':
        return EncounterType.followup;
      case 'initial':
      default:
        return EncounterType.initial;
    }
  }

  static NoteTemplate _template(String? s) {
    switch (s) {
      case 'custom':
        return NoteTemplate.custom;
      case 'standard':
      default:
        return NoteTemplate.standard;
    }
  }

  factory ClinicalNote.fromFirestore(String id, Map<String, dynamic> data) {
    return ClinicalNote(
      id: id,
      schemaVersion: (data['schemaVersion'] as num?)?.toInt() ?? 1,
      clinicId: (data['clinicId'] ?? '').toString(),
      patientId: (data['patientId'] ?? '').toString(),
      episodeId: (data['episodeId'] ?? '').toString(),
      authorUid: (data['authorUid'] ?? data['clinicianId'] ?? '').toString(),
      status: _status(data['status']?.toString()),
      encounterType: _encounter(data['encounterType']?.toString()),
      template: _template(data['template']?.toString()),
      appointmentId: data['appointmentId']?.toString(),
      assessmentId: data['assessmentId']?.toString(),
      previousNoteId: data['previousNoteId']?.toString(),
      version: (data['version'] as num?)?.toInt() ?? 1,
      current: Map<String, dynamic>.from((data['current'] ?? {}) as Map),
      amendmentCount: (data['amendmentCount'] as num?)?.toInt() ?? 0,
      lastAmendedAt: _ts(data['lastAmendedAt']),
      lastAmendedByUid: data['lastAmendedByUid']?.toString(),
      signedAt: _ts(data['signedAt']),
      createdAt: _ts(data['createdAt']),
      updatedAt: _ts(data['updatedAt']),
    );
  }
}
