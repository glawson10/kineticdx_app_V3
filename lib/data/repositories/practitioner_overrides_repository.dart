// lib/data/repositories/practitioner_overrides_repository.dart
//
// Overrides: clinics/{clinicId}/practitioners/{practitionerId}/overrides
// Reads: Firestore. Writes: settingsUpsertPractitionerOverride, settingsDeletePractitionerOverride.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../models/availability_override.dart';

class PractitionerOverridesRepository {
  PractitionerOverridesRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instanceFor(region: 'europe-west3');

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> _collection(
    String clinicId,
    String practitionerId,
  ) {
    return _firestore
        .collection('clinics')
        .doc(clinicId.trim())
        .collection('practitioners')
        .doc(practitionerId.trim())
        .collection('overrides');
  }

  /// Stream all overrides for a practitioner. Sorted by fromAt desc.
  Stream<List<PractitionerOverride>> watchOverrides({
    required String clinicId,
    required String practitionerId,
  }) {
    final c = clinicId.trim();
    final p = practitionerId.trim();
    if (c.isEmpty || p.isEmpty) return Stream.value(const []);

    return _collection(c, p).snapshots().map((snap) {
      final list = snap.docs.map((d) => PractitionerOverride.fromDoc(d)).toList();
      list.sort((a, b) => b.fromAt.compareTo(a.fromAt));
      return list;
    });
  }

  /// Create or update via callable. Returns overrideId (new on create).
  Future<String> upsertOverride({
    required String clinicId,
    required String practitionerId,
    String? overrideId,
    required Map<String, dynamic> patch,
  }) async {
    final callable = _functions.httpsCallable('settingsUpsertPractitionerOverride');
    final result = await callable.call(<String, dynamic>{
      'clinicId': clinicId,
      'practitionerId': practitionerId,
      if (overrideId != null && overrideId.isNotEmpty) 'overrideId': overrideId,
      'patch': patch,
    });
    final data = result.data as Map<String, dynamic>?;
    final id = data?['overrideId']?.toString().trim();
    if (id == null || id.isEmpty) throw StateError('Callable did not return overrideId');
    return id;
  }

  Future<void> deleteOverride({
    required String clinicId,
    required String practitionerId,
    required String overrideId,
  }) async {
    final callable = _functions.httpsCallable('settingsDeletePractitionerOverride');
    await callable.call(<String, dynamic>{
      'clinicId': clinicId,
      'practitionerId': practitionerId,
      'overrideId': overrideId,
    });
  }
}
