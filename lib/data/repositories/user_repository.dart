import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserRepository {
  final FirebaseFirestore _db;

  UserRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> userRef(String uid) =>
      _db.collection('users').doc(uid);

  /// Creates /users/{uid} if missing; otherwise updates lastSeenAt and safe fields.
  ///
  /// Notes:
  /// - createdAt is set only on first creation (server timestamp)
  /// - lastSeenAt updates each time called
  /// - displayName is only updated if non-empty to avoid wiping existing values
  Future<void> ensureUserDoc(User user) async {
    final ref = userRef(user.uid);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final now = FieldValue.serverTimestamp();

      final email = (user.email ?? '').trim().toLowerCase();
      final displayName = (user.displayName ?? '').trim();

      if (!snap.exists) {
        final data = <String, dynamic>{
          'displayName': displayName, // can be empty
          'email': email,
          // DO NOT write null placeholders unless you actually need them.
          // 'phone': null,
          // 'defaultClinicId': null,
          'onboarding': <String, dynamic>{
            'completedIntro': false,
            'hasCreatedClinic': false,
          },
          'createdAt': now,
          'lastSeenAt': now,
        };

        tx.set(ref, data);
        return;
      }

      // Update only safe mutable fields. Never overwrite createdAt.
      final update = <String, dynamic>{
        'email': email,
        'lastSeenAt': now,
      };

      if (displayName.isNotEmpty) {
        update['displayName'] = displayName;
      }

      tx.update(ref, update);
    });
  }

  /// Reads the user document once.
  Future<Map<String, dynamic>?> getUserData(String uid) async {
    final snap = await userRef(uid).get();
    return snap.data();
  }

  /// Updates defaultClinicId safely (clinician shell "last clinic used").
  /// This is NOT the same as the public booking clinic routing.
  Future<void> setDefaultClinicId({
    required String uid,
    required String clinicId,
  }) async {
    final trimmed = clinicId.trim();
    if (trimmed.isEmpty) return;

    await userRef(uid).update({
      'defaultClinicId': trimmed,
      'lastSeenAt': FieldValue.serverTimestamp(),
    });
  }

  /// Marks onboarding flags without overwriting the whole onboarding map.
  Future<void> setOnboardingFlags({
    required String uid,
    bool? completedIntro,
    bool? hasCreatedClinic,
  }) async {
    final update = <String, dynamic>{
      'lastSeenAt': FieldValue.serverTimestamp(),
    };

    if (completedIntro != null) {
      update['onboarding.completedIntro'] = completedIntro;
    }
    if (hasCreatedClinic != null) {
      update['onboarding.hasCreatedClinic'] = hasCreatedClinic;
    }

    await userRef(uid).update(update);
  }
}
