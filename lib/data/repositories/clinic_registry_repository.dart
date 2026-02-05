import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../models/clinical_test_registry_item.dart';
import '../../models/outcome_measure.dart';

class ClinicRegistryRepository {
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  ClinicRegistryRepository({FirebaseFirestore? db, FirebaseFunctions? functions})
      : _db = db ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  // ─────────────────────────────
  // Firestore reads
  // ─────────────────────────────

  Stream<List<ClinicalTestRegistryItem>> streamClinicalTests({
    required String clinicId,
    bool activeOnly = false,
  }) {
    Query<Map<String, dynamic>> q = _db
        .collection('clinics')
        .doc(clinicId)
        .collection('clinicalTestRegistry')
        .orderBy('name');

    if (activeOnly) q = q.where('active', isEqualTo: true);

    return q.snapshots().map((snap) {
      return snap.docs
          .map((d) => ClinicalTestRegistryItem.fromFirestore(d.id, d.data()))
          .toList();
    });
  }

  Stream<List<OutcomeMeasure>> streamOutcomeMeasures({
    required String clinicId,
    bool activeOnly = false,
  }) {
    Query<Map<String, dynamic>> q = _db
        .collection('clinics')
        .doc(clinicId)
        .collection('outcomeMeasures')
        .orderBy('name');

    if (activeOnly) q = q.where('active', isEqualTo: true);

    return q.snapshots().map((snap) {
      return snap.docs.map((d) => OutcomeMeasure.fromFirestore(d.id, d.data())).toList();
    });
  }

  // ─────────────────────────────
  // Cloud Functions writes
  // ─────────────────────────────

  Future<String> upsertClinicalTest({
    required String clinicId,
    String? testId,
    required String name,
    String? shortName,
    List<String>? bodyRegions,
    List<String>? tags,
    String? category,
    String? instructions,
    String? positiveCriteria,
    String? contraindications,
    String? interpretation,
    String? resultType,
    List<String>? allowedResults,
    bool? active,
  }) async {
    final res = await _functions.httpsCallable('upsertClinicalTestFn').call({
      'clinicId': clinicId,
      'testId': testId,
      'name': name,
      'shortName': shortName,
      'bodyRegions': bodyRegions ?? [],
      'tags': tags ?? [],
      'category': category,
      'instructions': instructions,
      'positiveCriteria': positiveCriteria,
      'contraindications': contraindications,
      'interpretation': interpretation,
      'resultType': resultType,
      'allowedResults': allowedResults ?? [],
      'active': active,
    });

    return (res.data['testId'] as String);
  }

  Future<String> upsertOutcomeMeasure({
    required String clinicId,
    String? measureId,
    required String name,
    String? fullName,
    List<String>? tags,
    String? scoreFormatHint,
    bool? active,
  }) async {
    final res = await _functions.httpsCallable('upsertOutcomeMeasureFn').call({
      'clinicId': clinicId,
      'measureId': measureId,
      'name': name,
      'fullName': fullName,
      'tags': tags ?? [],
      'scoreFormatHint': scoreFormatHint,
      'active': active,
    });

    return (res.data['measureId'] as String);
  }

  Future<void> setRegistryActive({
    required String clinicId,
    required String collection, // clinicalTestRegistry | outcomeMeasures | assessmentPacks | regionPresets
    required String id,
    required bool active,
  }) async {
    await _functions.httpsCallable('setRegistryActiveFn').call({
      'clinicId': clinicId,
      'collection': collection,
      'id': id,
      'active': active,
    });
  }
}
