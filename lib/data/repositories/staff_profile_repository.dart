// lib/data/repositories/staff_profile_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Staff profile (HR-ish) data:
/// clinics/{clinicId}/staffProfiles/{uid}
///
/// Availability subcollection:
/// clinics/{clinicId}/staffProfiles/{uid}/availability/default
///
/// Reads: Firestore streams (rules-controlled)
/// Writes: Cloud Functions callables (recommended for validation + audit)
class StaffProfileRepository {
  StaffProfileRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _fn = functions ?? FirebaseFunctions.instanceFor(region: 'europe-west3');

  final FirebaseFirestore _db;
  final FirebaseFunctions _fn;

  static const String _staffProfilesCol = 'staffProfiles';

  DocumentReference<Map<String, dynamic>> _profileRef(
    String clinicId,
    String uid,
  ) {
    final c = clinicId.trim();
    final u = uid.trim();
    return _db.collection('clinics').doc(c).collection(_staffProfilesCol).doc(u);
  }

  /// Stream the staff profile doc (may be null if not created yet).
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchStaffProfile(
    String clinicId,
    String uid,
  ) {
    final c = clinicId.trim();
    final u = uid.trim();
    if (c.isEmpty || u.isEmpty) return const Stream.empty();

    final ref = _profileRef(c, u);
    debugPrint('[StaffProfileRepository] watchStaffProfile path=${ref.path}');
    return ref.snapshots();
  }

  /// Upsert profile via callable for safety + validation + audit.
  ///
  /// Callable should:
  /// - enforce members.manage
  /// - validate patch fields
  /// - set updatedAt/updatedByUid
  /// - optionally create doc if missing
  Future<void> upsertStaffProfile({
    required String clinicId,
    required String uid,
    required Map<String, dynamic> patch,
  }) async {
    final callable = _fn.httpsCallable('upsertStaffProfileFn');

    final res = await callable.call(<String, dynamic>{
      'clinicId': clinicId.trim(),
      'uid': uid.trim(),
      'patch': patch,
    });

    final data = res.data;
    if (data is Map && data['ok'] == true) return;

    throw StateError('upsertStaffProfileFn returned unexpected payload: $data');
  }

  /// --- Availability (opening hours) ---
  ///
  /// We store weekly availability as "HH:mm" blocks (non-query metadata),
  /// and interpret it in the clinic/staff timezone in the availability engine.
  DocumentReference<Map<String, dynamic>> _availabilityDefaultRef(
    String clinicId,
    String uid,
  ) {
    return _profileRef(clinicId, uid).collection('availability').doc('default');
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchAvailabilityDefault(
    String clinicId,
    String uid,
  ) {
    final c = clinicId.trim();
    final u = uid.trim();
    if (c.isEmpty || u.isEmpty) return const Stream.empty();

    final ref = _availabilityDefaultRef(c, u);
    debugPrint(
      '[StaffProfileRepository] watchAvailabilityDefault path=${ref.path}',
    );
    return ref.snapshots();
  }

  /// Write availability via callable (recommended).
  ///
  /// Payload shape suggestion:
  /// {
  ///   timezone: "Europe/Prague",
  ///   weekly: {
  ///     mon: [{start:"08:00", end:"12:00"}, ...],
  ///     ...
  ///   }
  /// }
  Future<void> setAvailabilityDefault({
    required String clinicId,
    required String uid,
    required String timezone,
    required Map<String, dynamic> weekly, // day -> List<{start,end}>
  }) async {
    final callable = _fn.httpsCallable('setStaffAvailabilityDefaultFn');

    final res = await callable.call(<String, dynamic>{
      'clinicId': clinicId.trim(),
      'uid': uid.trim(),
      'timezone': timezone.trim(),
      'weekly': weekly,
    });

    final data = res.data;
    if (data is Map && data['ok'] == true) return;

    throw StateError(
      'setStaffAvailabilityDefaultFn returned unexpected payload: $data',
    );
  }
}
