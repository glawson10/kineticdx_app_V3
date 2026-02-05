// lib/data/repositories/patient_uploads_repository.dart
//
// Clinic-scoped patient uploads: Firestore metadata + Firebase Storage.
// Path: clinics/{clinicId}/private/patientUploads/{patientId}/{uploadId}/{fileName}

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../models/patient_upload.dart';

class PatientUploadsRepository {
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  PatientUploadsRepository({
    FirebaseFirestore? db,
    FirebaseStorage? storage,
  })  : _db = db ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> _uploadsRef(
    String clinicId,
    String patientId,
  ) =>
      _db
          .collection('clinics')
          .doc(clinicId)
          .collection('patients')
          .doc(patientId)
          .collection('uploads');

  /// Stream active uploads for a patient, newest first.
  Stream<List<PatientUpload>> streamActiveUploads({
    required String clinicId,
    required String patientId,
  }) {
    return _uploadsRef(clinicId, patientId)
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => PatientUpload.fromFirestore(d.id, d.data()))
            .toList());
  }

  /// Canonical storage path for one upload.
  static String storagePath({
    required String clinicId,
    required String patientId,
    required String uploadId,
    required String fileName,
  }) {
    return 'clinics/$clinicId/private/patientUploads/$patientId/$uploadId/$fileName';
  }

  /// Upload bytes and create Firestore metadata. Returns uploadId.
  Future<String> upload({
    required String clinicId,
    required String patientId,
    required String fileName,
    required String contentType,
    required Uint8List bytes,
    required String createdByUid,
  }) async {
    final uploadId = _db.collection('_').doc().id;
    final path = storagePath(
      clinicId: clinicId,
      patientId: patientId,
      uploadId: uploadId,
      fileName: fileName,
    );
    final ref = _storage.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    final meta = <String, dynamic>{
      'clinicId': clinicId,
      'patientId': patientId,
      'storagePath': path,
      'fileName': fileName,
      'contentType': contentType,
      'sizeBytes': bytes.length,
      'createdAt': FieldValue.serverTimestamp(),
      'createdByUid': createdByUid,
      'status': 'active',
      'notes': '',
      'tags': <String>[],
    };
    await _uploadsRef(clinicId, patientId).doc(uploadId).set(meta);
    return uploadId;
  }

  /// Download file bytes from Storage (for viewer or share).
  Future<Uint8List> getBytes({required String storagePath}) async {
    final ref = _storage.ref(storagePath);
    final data = await ref.getData();
    if (data == null) throw StateError('No data at $storagePath');
    return data;
  }

  /// Download smaller bytes for thumbnails; returns null on error.
  Future<Uint8List?> getThumbnailBytes({
    required String storagePath,
    int maxBytes = 5 * 1024 * 1024,
  }) async {
    try {
      final ref = _storage.ref(storagePath);
      return await ref.getData(maxBytes);
    } catch (_) {
      return null;
    }
  }

  /// Delete: remove storage object and set Firestore status to "deleted".
  Future<void> delete({
    required String clinicId,
    required String patientId,
    required String uploadId,
    required String storagePath,
  }) async {
    try {
      await _storage.ref(storagePath).delete();
    } catch (_) {
      // Storage may already be gone; continue to update Firestore
    }
    await _uploadsRef(clinicId, patientId)
        .doc(uploadId)
        .update({'status': 'deleted'});
  }

  /// Get a single upload doc (e.g. to read storagePath for viewer).
  Future<PatientUpload?> getUpload({
    required String clinicId,
    required String patientId,
    required String uploadId,
  }) async {
    final snap = await _uploadsRef(clinicId, patientId).doc(uploadId).get();
    if (!snap.exists) return null;
    return PatientUpload.fromFirestore(snap.id, snap.data()!);
  }

  /// Update notes and audit fields on an upload.
  Future<void> updateNotes({
    required String clinicId,
    required String patientId,
    required String uploadId,
    required String notes,
    required String updatedByUid,
  }) async {
    await _uploadsRef(clinicId, patientId).doc(uploadId).update({
      'notes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': updatedByUid,
    });
  }

  /// Update tags and audit fields on an upload.
  Future<void> updateTags({
    required String clinicId,
    required String patientId,
    required String uploadId,
    required List<String> tags,
    required String updatedByUid,
  }) async {
    await _uploadsRef(clinicId, patientId).doc(uploadId).update({
      'tags': _normalizeTags(tags),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': updatedByUid,
    });
  }

  static List<String> _normalizeTags(Iterable<String> raw) {
    final allowed = kPatientUploadTags.toSet();
    final out = <String>[];
    for (final tag in raw) {
      final clean = tag.trim();
      if (clean.isEmpty) continue;
      if (!allowed.contains(clean)) continue;
      if (!out.contains(clean)) out.add(clean);
    }
    return out;
  }
}
