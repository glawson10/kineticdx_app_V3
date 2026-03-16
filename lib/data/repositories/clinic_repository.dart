import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

typedef ClinicDocSnapshot = DocumentSnapshot<Map<String, dynamic>>;

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

  Stream<DocumentSnapshot<Map<String, dynamic>>>? _cachedClinicStream;
  String? _cachedClinicStreamId;
  DocumentSnapshot<Map<String, dynamic>>? _lastClinicSnapshot;
  StreamController<DocumentSnapshot<Map<String, dynamic>>>? _clinicController;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _clinicSourceSub;

  /// Read the clinic root doc. Rules should enforce settings.read.
  /// Cached per [clinicId]; replays last snapshot to new listeners so
  /// Settings → General does not stay on loading after leaving Calendar.
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchClinic(String clinicId) {
    if (_cachedClinicStreamId == clinicId && _cachedClinicStream != null) {
      return _cachedClinicStream!;
    }
    _clinicSourceSub?.cancel();
    _clinicController?.close();
    _cachedClinicStreamId = clinicId;
    _lastClinicSnapshot = null;
    _clinicController = StreamController<DocumentSnapshot<Map<String, dynamic>>>.broadcast();
    _clinicSourceSub = _firestore
        .collection('clinics')
        .doc(clinicId)
        .snapshots()
        .listen(
          (s) {
            _lastClinicSnapshot = s;
            _clinicController!.add(s);
          },
          onError: _clinicController!.addError,
          onDone: _clinicController!.close,
          cancelOnError: false,
        );
    _cachedClinicStream = Stream.multi((sink) {
      if (_lastClinicSnapshot != null) sink.add(_lastClinicSnapshot!);
      final sub = _clinicController!.stream.listen(
        sink.add,
        onError: sink.addError,
        onDone: sink.close,
      );
      sink.onCancel = () => sub.cancel();
    });
    return _cachedClinicStream!;
  }

  /// Update clinic profile via Cloud Function (recommended).
  /// Keep the payload as a "patch" object with whitelisted keys.
  Future<void> updateClinicProfile({
    required String clinicId,
    required Map<String, dynamic> patch,
  }) async {
    final callable = _functions.httpsCallable('settingsUpdateClinicProfile');

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

      throw StateError('settingsUpdateClinicProfile returned unexpected payload: $data');
    } on FirebaseFunctionsException catch (e) {
      // Show clean cloud-function errors
      final msg = (e.message ?? e.code).trim();
      throw StateError('settingsUpdateClinicProfile failed: $msg');
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

  /// Watch the canonical public booking settings doc (weeklyHours, etc).
  /// Reads from settings/publicBooking so opening hours and projection share one source of truth.
  /// (Commit 17: projection mirrors this to public/config; listPublicSlots reads the mirror.)
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchPublicBookingSettings(
      String clinicId) {
    final c = clinicId.trim();
    if (c.isEmpty) return const Stream.empty();
    return _firestore
        .collection('clinics')
        .doc(c)
        .collection('settings')
        .doc('publicBooking')
        .snapshots();
  }

  /// Update weekly opening hours via settings.updatePublicBookingConfig.
  /// Writes only to clinics/{clinicId}/settings/publicBooking; mirror triggers update public config.
  ///
  /// Expects `weeklyHours` shape:
  /// {
  ///   "mon": [{"start":"08:00","end":"18:00"}],
  ///   ...
  /// }
  ///
  /// Optionally also sends `weeklyHoursMeta`.
  Future<void> updateClinicWeeklyHours({
    required String clinicId,
    required Map<String, dynamic> weeklyHours,
    Map<String, dynamic>? weeklyHoursMeta,
  }) async {
    final callable = _functions.httpsCallable('settingsUpdatePublicBookingConfig');

    final patch = <String, dynamic>{
      'weeklyHours': weeklyHours,
      if (weeklyHoursMeta != null) 'weeklyHoursMeta': weeklyHoursMeta,
    };
    final payload = <String, dynamic>{
      'clinicId': clinicId,
      'patch': patch,
    };

    try {
      final res = await callable.call(payload);

      final data = res.data;
      if (data is Map && data['ok'] == true) return;

      throw StateError(
        'settingsUpdatePublicBookingConfig returned unexpected payload: $data',
      );
    } on FirebaseFunctionsException catch (e) {
      final msg = (e.message ?? e.code).trim();
      throw StateError('settingsUpdatePublicBookingConfig failed: $msg');
    }
  }

  /// Rebuilds the public booking config mirror from current settings.
  /// Use after saving opening hours so clinician calendar and public booking
  /// see the same weeklyHours (they read from public/config/publicBooking/config).
  /// Requires settings.write.
  Future<void> rebuildPublicBookingConfig(String clinicId) async {
    final callable = _functions.httpsCallable('projectionsRebuildPublicBookingConfig');
    try {
      final res = await callable.call({'clinicId': clinicId});
      final data = res.data;
      if (data is Map && data['ok'] == true) return;
      throw StateError('projectionsRebuildPublicBookingConfig returned unexpected payload: $data');
    } on FirebaseFunctionsException catch (e) {
      final msg = (e.message ?? e.code).trim();
      throw StateError('Rebuild public booking config failed: $msg');
    }
  }
}
