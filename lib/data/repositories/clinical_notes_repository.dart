import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../models/clinical_note.dart';

class ClinicalNotesRepository {
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  ClinicalNotesRepository({FirebaseFirestore? db, FirebaseFunctions? functions})
      : _db = db ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  /// Stream all notes for a patient (requires clinical.read in rules).
  Stream<List<ClinicalNote>> notesForPatient({
    required String clinicId,
    required String patientId,
  }) {
    return _db
        .collection('clinics')
        .doc(clinicId)
        .collection('patients')
        .doc(patientId)
        .collection('notes')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ClinicalNote.fromFirestore(d.id, d.data()))
            .toList());
  }

  /// Stream notes filtered by episode (client-side filter or query by episodeId).
  Stream<List<ClinicalNote>> notesForEpisode({
    required String clinicId,
    required String patientId,
    required String episodeId,
  }) {
    return _db
        .collection('clinics')
        .doc(clinicId)
        .collection('patients')
        .doc(patientId)
        .collection('notes')
        .where('episodeId', isEqualTo: episodeId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ClinicalNote.fromFirestore(d.id, d.data()))
            .toList());
  }

  /// Read a single note doc.
  Future<ClinicalNote?> getNote({
    required String clinicId,
    required String patientId,
    required String noteId,
  }) async {
    final snap = await _db
        .collection('clinics')
        .doc(clinicId)
        .collection('patients')
        .doc(patientId)
        .collection('notes')
        .doc(noteId)
        .get();

    if (!snap.exists) return null;
    return ClinicalNote.fromFirestore(snap.id, snap.data()!);
  }

  // ─────────────────────────────
  // Cloud Functions (v2 callable)
  // ─────────────────────────────

  Future<String> createNoteDraft({
    required String clinicId,
    required String patientId,
    required String episodeId,
    String? appointmentId,
    required String noteType,
  }) async {
    final res = await _functions.httpsCallable('createNoteDraftFn').call({
      'clinicId': clinicId,
      'patientId': patientId,
      'episodeId': episodeId,
      'appointmentId': appointmentId,
      'noteType': noteType,
    });

    return (res.data['noteId'] as String);
  }

  /// Update full SOAP payload for a draft note.
  /// Draft-only. Author-only unless manager override.
  Future<void> updateDraftSoap({
    required String clinicId,
    required String patientId,
    required String noteId,
    required Map<String, dynamic> soap,
  }) async {
    await _functions.httpsCallable('updateNoteDraftFn').call({
      'clinicId': clinicId,
      'patientId': patientId,
      'noteId': noteId,
      'soap': soap,
    });
  }

  /// Sign the note (author only).
  Future<void> signNote({
    required String clinicId,
    required String patientId,
    required String noteId,
  }) async {
    await _functions.httpsCallable('signNoteFn').call({
      'clinicId': clinicId,
      'patientId': patientId,
      'noteId': noteId,
    });
  }

  /// Amend a signed note.
  /// Clinician can amend own; manager can amend any.
  Future<void> amendSignedNote({
    required String clinicId,
    required String patientId,
    required String noteId,
    required Map<String, dynamic> soap,
    required String reason,
    String? summary,
    List<String>? fieldPaths,
  }) async {
    await _functions.httpsCallable('amendSignedNoteFn').call({
      'clinicId': clinicId,
      'patientId': patientId,
      'noteId': noteId,
      'soap': soap,
      'reason': reason,
      'summary': summary,
      'fieldPaths': fieldPaths ?? [],
    });
  }
}
