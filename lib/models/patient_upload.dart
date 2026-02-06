// lib/models/patient_upload.dart
//
// Firestore metadata for patient uploads.
// Storage path: clinics/{clinicId}/private/patientUploads/{patientId}/{uploadId}/{fileName}

import 'package:cloud_firestore/cloud_firestore.dart';

const List<String> kPatientUploadTags = [
  'Imaging',
  'Referral',
  'Consent',
  'Report',
  'Patient-provided',
  'Other',
];

class PatientUpload {
  final String id;
  final String clinicId;
  final String patientId;
  final String storagePath;
  final String fileName;
  final String contentType;
  final int sizeBytes;
  final DateTime? createdAt;
  final String? createdByUid;
  final String status; // "active" | "deleted"
  final String notes;
  final List<String> tags;
  final DateTime? updatedAt;
  final String? updatedByUid;

  const PatientUpload({
    required this.id,
    required this.clinicId,
    required this.patientId,
    required this.storagePath,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    this.createdAt,
    this.createdByUid,
    required this.status,
    this.notes = '',
    this.tags = const [],
    this.updatedAt,
    this.updatedByUid,
  });

  static DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static String _str(dynamic v) => v?.toString() ?? '';

  static List<String> _stringList(dynamic v) {
    if (v is Iterable) {
      return v
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return <String>[];
  }

  static List<String> _normalizeTags(dynamic v) {
    final allowed = kPatientUploadTags.toSet();
    final raw = _stringList(v);
    final out = <String>[];
    for (final tag in raw) {
      if (allowed.contains(tag) && !out.contains(tag)) {
        out.add(tag);
      }
    }
    return out;
  }

  factory PatientUpload.fromFirestore(String id, Map<String, dynamic> data) {
    return PatientUpload(
      id: id,
      clinicId: _str(data['clinicId']),
      patientId: _str(data['patientId']),
      storagePath: _str(data['storagePath']),
      fileName: _str(data['fileName']),
      contentType: _str(data['contentType']),
      sizeBytes: (data['sizeBytes'] is int)
          ? data['sizeBytes'] as int
          : ((data['sizeBytes'] is num)
              ? (data['sizeBytes'] as num).toInt()
              : 0),
      createdAt: _toDate(data['createdAt']),
      createdByUid: _str(data['createdByUid']).isEmpty
          ? null
          : _str(data['createdByUid']),
      status: _str(data['status']).isEmpty ? 'active' : _str(data['status']),
      notes: _str(data['notes']),
      tags: _normalizeTags(data['tags']),
      updatedAt: _toDate(data['updatedAt']),
      updatedByUid: _str(data['updatedByUid']).isEmpty
          ? null
          : _str(data['updatedByUid']),
    );
  }

  bool get isPdf =>
      contentType.toLowerCase().contains('pdf') ||
      fileName.toLowerCase().endsWith('.pdf');

  bool get isImage {
    final ct = contentType.toLowerCase();
    final fn = fileName.toLowerCase();
    return ct.startsWith('image/') ||
        fn.endsWith('.jpg') ||
        fn.endsWith('.jpeg') ||
        fn.endsWith('.png') ||
        fn.endsWith('.gif') ||
        fn.endsWith('.webp');
  }

  bool get hasNotes => notes.trim().isNotEmpty;
}
