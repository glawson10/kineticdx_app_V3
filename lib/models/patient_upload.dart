// lib/models/patient_upload.dart
//
// Firestore metadata for patient uploads.
// Storage path: clinics/{clinicId}/private/patientUploads/{patientId}/{uploadId}/{fileName}

import 'package:cloud_firestore/cloud_firestore.dart';

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
  });

  static DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static String _str(dynamic v) => v?.toString() ?? '';

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
}
