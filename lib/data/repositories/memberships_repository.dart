import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/membership.dart';
import '../../models/membership_index.dart';

class MembershipsRepository {
  final FirebaseFirestore _db;

  MembershipsRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  // ---------------------------------------------------------------------------
  // Clinic picker (index mirror)
  // users/{uid}/memberships/{clinicId}
  // ---------------------------------------------------------------------------

  Stream<List<MembershipIndex>> membershipsForUser(String uid) {
    final u = uid.trim();
    if (u.isEmpty) return Stream.value(const <MembershipIndex>[]);

    return _db
        .collection('users')
        .doc(u)
        .collection('memberships')
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => MembershipIndex.fromFirestore(doc.id, doc.data()))
            .toList());
  }

  // ---------------------------------------------------------------------------
  // Authoritative membership doc (permissions live here)
  //
  // Canonical (V3): clinics/{clinicId}/memberships/{uid}
  // Legacy (V1):   clinics/{clinicId}/members/{uid}
  //
  // We read canonical first, then fall back to legacy for old clinics.
  // ---------------------------------------------------------------------------

  DocumentReference<Map<String, dynamic>> _canonicalRef({
    required String clinicId,
    required String uid,
  }) {
    return _db
        .collection('clinics')
        .doc(clinicId)
        .collection('memberships')
        .doc(uid);
  }

  DocumentReference<Map<String, dynamic>> _legacyRef({
    required String clinicId,
    required String uid,
  }) {
    return _db
        .collection('clinics')
        .doc(clinicId)
        .collection('members')
        .doc(uid);
  }

  /// Watches the membership doc (canonical first, legacy fallback).
  ///
  /// NOTE: This emits:
  /// - canonical membership if it exists
  /// - legacy membership if canonical doesn't exist
  /// - null if neither exists
  Stream<Membership?> watchClinicMembership({
    required String clinicId,
    required String uid,
  }) {
    final c = clinicId.trim();
    final u = uid.trim();
    if (c.isEmpty || u.isEmpty) return Stream.value(null);

    final canon = _canonicalRef(clinicId: c, uid: u);

    return canon.snapshots().asyncMap((canonSnap) async {
      if (canonSnap.exists) {
        final data = canonSnap.data();
        if (data == null) return null;
        return Membership.fromFirestore(c, data);
      }

      // fallback to legacy
      final legacySnap = await _legacyRef(clinicId: c, uid: u).get();
      if (!legacySnap.exists) return null;
      final data = legacySnap.data();
      if (data == null) return null;
      return Membership.fromFirestore(c, data);
    });
  }

  /// One-shot read (canonical first, legacy fallback).
  Future<Membership?> getClinicMembership({
    required String clinicId,
    required String uid,
  }) async {
    final c = clinicId.trim();
    final u = uid.trim();
    if (c.isEmpty || u.isEmpty) return null;

    final canonSnap = await _canonicalRef(clinicId: c, uid: u).get();
    if (canonSnap.exists) {
      final data = canonSnap.data();
      if (data == null) return null;
      return Membership.fromFirestore(c, data);
    }

    final legacySnap = await _legacyRef(clinicId: c, uid: u).get();
    if (!legacySnap.exists) return null;
    final data = legacySnap.data();
    if (data == null) return null;
    return Membership.fromFirestore(c, data);
  }

  // ---------------------------------------------------------------------------
  // Raw member doc (if you need access to dynamic maps directly)
  // Canonical first, legacy fallback.
  // ---------------------------------------------------------------------------

  Stream<Map<String, dynamic>?> watchClinicMemberDoc({
    required String clinicId,
    required String uid,
  }) {
    final c = clinicId.trim();
    final u = uid.trim();
    if (c.isEmpty || u.isEmpty) return Stream.value(null);

    final canon = _canonicalRef(clinicId: c, uid: u);

    return canon.snapshots().asyncMap((canonSnap) async {
      if (canonSnap.exists) return canonSnap.data();

      final legacySnap = await _legacyRef(clinicId: c, uid: u).get();
      return legacySnap.data();
    });
  }

  Future<Map<String, dynamic>?> getClinicMemberDoc({
    required String clinicId,
    required String uid,
  }) async {
    final c = clinicId.trim();
    final u = uid.trim();
    if (c.isEmpty || u.isEmpty) return null;

    final canonSnap = await _canonicalRef(clinicId: c, uid: u).get();
    if (canonSnap.exists) return canonSnap.data();

    final legacySnap = await _legacyRef(clinicId: c, uid: u).get();
    return legacySnap.data();
  }

  // ---------------------------------------------------------------------------
  // Debug helpers (optional)
  // ---------------------------------------------------------------------------

  /// Returns true if:
  /// - membership exists
  /// - not explicitly inactive (active == false)
  /// - permissionKey is true in the permissions map
  ///
  /// Back-compat: if `active` is null/missing, we treat as active.
  Future<bool> hasPermission({
    required String clinicId,
    required String uid,
    required String permissionKey,
  }) async {
    final m = await getClinicMembership(clinicId: clinicId, uid: uid);
    if (m == null) return false;

    // Backwards compatible: null means "not present" => active
    if (m.active == false) return false;

    final perms = m.permissions;
    return perms[permissionKey] == true;
  }
}
