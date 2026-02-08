import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../models/clinical_tests.dart';
import '../../../models/soap_note.dart';
import 'initial_assessment_note.dart';

/// Clinic-scoped repository for structured SOAP notes.
///
/// Path: clinics/{clinicId}/patients/{patientId}/soapNotes/{noteId}
class SoapNotesRepository {
  final FirebaseFirestore _db;

  SoapNotesRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _notesCollection(
    String clinicId,
    String patientId,
  ) {
    return _db
        .collection('clinics')
        .doc(clinicId)
        .collection('patients')
        .doc(patientId)
        .collection('soapNotes');
  }

  DocumentReference<Map<String, dynamic>> noteDoc(
    String clinicId,
    String patientId,
    String noteId,
  ) {
    return _notesCollection(clinicId, patientId).doc(noteId);
  }

  Stream<SoapNote> watchSoapNote({
    required String clinicId,
    required String patientId,
    required String noteId,
  }) {
    return noteDoc(clinicId, patientId, noteId).snapshots().map((snap) {
      if (!snap.exists) {
        throw StateError('Note not found');
      }
      return SoapNote.fromFirestore(
        snap.id,
        snap.data() ?? const <String, dynamic>{},
      );
    });
  }

  Future<SoapNote> createSoapNote({
    required String clinicId,
    required String patientId,
    required String createdByUid,
    required BodyRegion bodyRegion,
  }) async {
    final col = _notesCollection(clinicId, patientId);
    final doc = col.doc();

    final empty = SoapNote(
      id: doc.id,
      clinicId: clinicId,
      patientId: patientId,
      clinicianId: createdByUid,
      bodyRegion: bodyRegion,
      status: 'draft',
      screening: const ScreeningSection(),
      subjective: const SubjectiveSection(),
      objective: const ObjectiveSection(),
      analysis: const AnalysisSection(),
      plan: const PlanSection(),
      clinicalTests: const [],
    );

    final data = empty.toFirestore();

    try {
      await doc.set(data);
    } catch (e, stack) {
      debugPrint('ERROR creating SoapNote at path: ${doc.path}');
      debugPrint('Error: $e');
      debugPrint('Stack: $stack');
      debugPrint('Data keys: ${data.keys.toList()}');
      rethrow;
    }

    final snap = await doc.get();
    return SoapNote.fromFirestore(
      snap.id,
      snap.data() ?? const <String, dynamic>{},
    );
  }

  Future<void> updateSoapNote({
    required SoapNote note,
    required String clinicId,
    required String patientId,
    required String updatedByUid,
  }) async {
    final doc = noteDoc(clinicId, patientId, note.id);
    final data = note.copyWith(
      clinicianId: updatedByUid,
    ).toFirestore();
    try {
      await doc.update(data);
    } catch (e, stack) {
      debugPrint('ERROR updating SoapNote at path: ${doc.path}');
      debugPrint('Error: $e');
      debugPrint('Stack: $stack');
      debugPrint('Note ID: ${note.id}, Status: ${note.status}');
      rethrow;
    }
  }

  Future<void> finalizeSoapNote({
    required String clinicId,
    required String patientId,
    required String noteId,
    required String updatedByUid,
  }) async {
    final doc = noteDoc(clinicId, patientId, noteId);
    await doc.update({
      'status': 'final',
      'updatedAt': FieldValue.serverTimestamp(),
      'clinicianId': updatedByUid,
    });
  }

  // ---------------------------------------------------------------------------
  // Initial Assessment note (same collection path, different document shape)
  // ---------------------------------------------------------------------------

  Stream<InitialAssessmentNote> watchInitialAssessment({
    required String clinicId,
    required String patientId,
    required String noteId,
  }) {
    return noteDoc(clinicId, patientId, noteId).snapshots().map((snap) {
      if (!snap.exists) {
        throw StateError('Note not found');
      }
      return InitialAssessmentNote.fromFirestore(
        snap.id,
        snap.data() ?? const <String, dynamic>{},
      );
    });
  }

  Future<InitialAssessmentNote> createInitialAssessment({
    required String clinicId,
    required String patientId,
    required String createdByUid,
    required BodyRegion bodyRegion,
  }) async {
    final col = _notesCollection(clinicId, patientId);
    final doc = col.doc();
    final now = FieldValue.serverTimestamp();
    final data = <String, dynamic>{
      'clinicId': clinicId,
      'patientId': patientId,
      'noteType': 'initial',
      'bodyRegion': bodyRegion.name,
      'status': 'draft',
      'createdAt': now,
      'updatedAt': now,
      'createdByUid': createdByUid,
      'subjective': <String, dynamic>{
        'presentingComplaint': '',
        'historyOfPresentingComplaint': '',
        'painIntensityNow': 0,
        'painIntensityBest': 0,
        'painIntensityWorst': 0,
        'painIrritability': '',
        'painNature': '',
        'aggravatingFactors': <Object>[],
        'easingFactors': <Object>[],
        'pattern24h': '',
        'redFlags': <Object>[],
        'yellowFlags': '',
        'pastMedicalHistory': '',
        'meds': '',
        'imaging': '',
        'goals': '',
        'functionalLimitations': '',
      },
      'objective': <String, dynamic>{
        'observation': '',
        'neuroScreenSummary': '',
        'functionalTests': <Object>[],
        'palpation': '',
        'rangeOfMotion': <Object>[],
        'strength': <Object>[],
        'neuroMyotomesSummary': '',
        'neuroDermatomesSummary': '',
        'neuroReflexesSummary': '',
        'regionSpecific': <String, dynamic>{},
      },
      'specialTests': <Object>[],
      'assessment': <String, dynamic>{
        'primaryDiagnosis': '',
        'differentialDiagnoses': <Object>[],
        'contributingFactors': '',
        'clinicalReasoning': '',
        'severity': '',
        'irritability': '',
        'stage': '',
        'outcomeMeasures': <Object>[],
      },
      'plan': <String, dynamic>{
        'planSummary': '',
        'educationAdvice': '',
        'exercises': <Object>[],
        'manualTherapy': '',
        'followUp': '',
        'referrals': '',
        'consentConfirmed': false,
        'homeAdvice': '',
      },
    };
    await doc.set(data);
    final snap = await doc.get();
    return InitialAssessmentNote.fromFirestore(
      snap.id,
      snap.data() ?? const <String, dynamic>{},
    );
  }

  Future<void> updateInitialAssessment({
    required InitialAssessmentNote note,
    required String clinicId,
    required String patientId,
    required String updatedByUid,
  }) async {
    final doc = noteDoc(clinicId, patientId, note.id);
    final data = note.toFirestore();
    data['updatedAt'] = FieldValue.serverTimestamp();
    data['updatedByUid'] = updatedByUid;
    await doc.update(data);
  }

  Future<void> finalizeInitialAssessment({
    required String clinicId,
    required String patientId,
    required String noteId,
    required String updatedByUid,
  }) async {
    final doc = noteDoc(clinicId, patientId, noteId);
    await doc.update({
      'status': 'final',
      'updatedAt': FieldValue.serverTimestamp(),
      'finalizedAt': FieldValue.serverTimestamp(),
      'updatedByUid': updatedByUid,
    });
  }
}

