import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class ClinicRepository {
  ClinicRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'europe-west3');

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  // ---------------------------------------------------------------------------
  // Clinic profile (1A)
  // ---------------------------------------------------------------------------

  /// Read the clinic root doc. Rules should enforce settings.read.
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchClinic(String clinicId) {
    return _firestore.collection('clinics').doc(clinicId).snapshots();
  }

  /// Update clinic profile via Cloud Function (recommended).
  /// Keep the payload as a "patch" object with whitelisted keys.
  Future<void> updateClinicProfile({
    required String clinicId,
    required Map<String, dynamic> patch,
  }) async {
    final callable = _functions.httpsCallable('updateClinicProfileFn');

    // Ensure JSON-safe map (no controllers, timestamps, etc accidentally)
    final safePatch = <String, dynamic>{};
    patch.forEach((k, v) {
      safePatch[k] = v;
    });

    try {
      final res = await callable.call(<String, dynamic>{
        'clinicId': clinicId,
        'patch': safePatch,
      });

      final data = res.data;
      if (data is Map && data['ok'] == true) return;

      throw StateError('updateClinicProfileFn returned unexpected payload: $data');
    } on FirebaseFunctionsException catch (e) {
      // Show clean cloud-function errors
      final msg = (e.message ?? e.code).trim();
      throw StateError('updateClinicProfileFn failed: $msg');
    }
  }

  // ---------------------------------------------------------------------------
  // Closures (1B)
  // ---------------------------------------------------------------------------

  /// Stream active closures ordered by start time.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchActiveClosures(String clinicId) {
    return _firestore
        .collection('clinics')
        .doc(clinicId)
        .collection('closures')
        .where('active', isEqualTo: true)
        .orderBy('fromAt')
        .snapshots();
  }

  /// Create a closure (via Cloud Function).
  /// We send ISO strings so the callable can parse on web + mobile consistently.
  Future<String> createClosure({
    required String clinicId,
    required DateTime fromAt,
    required DateTime toAt,
    String? reason,
  }) async {
    final callable = _functions.httpsCallable('createClosureFn');

    final res = await callable.call(<String, dynamic>{
      'clinicId': clinicId,
      'fromAt': fromAt.toUtc().toIso8601String(),
      'toAt': toAt.toUtc().toIso8601String(),
      'reason': (reason ?? '').trim().isEmpty ? null : reason!.trim(),
    });

    final data = res.data;
    if (data is Map && data['ok'] == true && data['closureId'] is String) {
      return data['closureId'] as String;
    }

    throw StateError('createClosureFn returned unexpected payload: $data');
  }

  /// Soft-delete a closure (via Cloud Function).
  Future<void> deleteClosure({
    required String clinicId,
    required String closureId,
  }) async {
    final callable = _functions.httpsCallable('deleteClosureFn');

    final res = await callable.call(<String, dynamic>{
      'clinicId': clinicId,
      'closureId': closureId,
    });

    final data = res.data;
    if (data is Map && data['ok'] == true) return;

    throw StateError('deleteClosureFn returned unexpected payload: $data');
  }

  // ---------------------------------------------------------------------------
  // Opening hours / weekly hours (1C)
  // ---------------------------------------------------------------------------

  /// Watch the public booking settings doc (contains weeklyHours, weeklyHoursMeta, etc).
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchPublicBookingSettings(
      String clinicId) {
    return _firestore
        .doc('clinics/$clinicId/public/config/publicBooking/publicBooking')
        .snapshots();
  }

  /// Update weekly opening hours via callable.
  ///
  /// Expects `weeklyHours` shape:
  /// {
  ///   "mon": [{"start":"08:00","end":"18:00"}],
  ///   ...
  /// }
  ///
  /// Optionally also writes `weeklyHoursMeta`.
  Future<void> updateClinicWeeklyHours({
    required String clinicId,
    required Map<String, dynamic> weeklyHours,
    Map<String, dynamic>? weeklyHoursMeta,
  }) async {
    final callable = _functions.httpsCallable('updateClinicWeeklyHoursFn');

    final payload = <String, dynamic>{
      'clinicId': clinicId,
      'weeklyHours': weeklyHours,
      if (weeklyHoursMeta != null) 'weeklyHoursMeta': weeklyHoursMeta,
    };

    try {
      final res = await callable.call(payload);

      final data = res.data;
      if (data is Map && data['ok'] == true) return;

      throw StateError(
        'updateClinicWeeklyHoursFn returned unexpected payload: $data',
      );
    } on FirebaseFunctionsException catch (e) {
      final msg = (e.message ?? e.code).trim();
      throw StateError('updateClinicWeeklyHoursFn failed: $msg');
    }
  }
}
