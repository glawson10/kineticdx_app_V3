// lib/data/repositories/practitioner_availability_repository.dart
//
// Base recurring availability: clinics/{clinicId}/practitioners/{practitionerId}/availability
// Reads: Firestore. Writes: settingsUpsertPractitionerAvailability callable.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../models/practitioner_availability.dart';

class PractitionerAvailabilityRepository {
  PractitionerAvailabilityRepository({
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
        .collection('availability');
  }

  Stream<List<PractitionerAvailability>> watchAvailabilities({
    required String clinicId,
    required String practitionerId,
  }) {
    final c = clinicId.trim();
    final p = practitionerId.trim();
    if (c.isEmpty || p.isEmpty) return Stream.value(const []);

    return _collection(c, p).snapshots().map((snap) {
      final list = snap.docs
          .map((d) => PractitionerAvailability.fromDoc(d))
          .toList();
      list.sort((a, b) {
        final au = a.updatedAt;
        final bu = b.updatedAt;
        if (au != null && bu != null) return bu.compareTo(au);
        if (au != null) return -1;
        if (bu != null) return 1;
        return a.id.compareTo(b.id);
      });
      return list;
    });
  }

  Future<String> upsertAvailability({
    required String clinicId,
    required String practitionerId,
    String? availabilityId,
    required Map<String, dynamic> patch,
  }) async {
    final callable = _functions.httpsCallable('settingsUpsertPractitionerAvailability');
    final result = await callable.call(<String, dynamic>{
      'clinicId': clinicId,
      'practitionerId': practitionerId,
      if (availabilityId != null && availabilityId.isNotEmpty) 'availabilityId': availabilityId,
      'patch': patch,
    });
    final data = result.data as Map<String, dynamic>?;
    final id = data?['availabilityId']?.toString().trim();
    if (id == null || id.isEmpty) throw StateError('Callable did not return availabilityId');
    return id;
  }

  /// Delete an availability rule via callable.
  Future<void> deleteAvailability({
    required String clinicId,
    required String practitionerId,
    required String availabilityId,
  }) async {
    final callable = _functions.httpsCallable('settingsDeletePractitionerAvailability');
    await callable.call(<String, dynamic>{
      'clinicId': clinicId,
      'practitionerId': practitionerId,
      'availabilityId': availabilityId,
    });
  }
}
