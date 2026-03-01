import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

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
  // Canonical = members (matches backend acceptInvite/updateMember + StaffRepository).
  // Legacy = memberships (fallback for older clinics).
  // Session permissions must read from the same canonical as the backend so
  // permission updates (e.g. members.read) are visible immediately.
  // ---------------------------------------------------------------------------

  DocumentReference<Map<String, dynamic>> _canonicalRef({
    required String clinicId,
    required String uid,
  }) {
    return _db
        .collection('clinics')
        .doc(clinicId)
        .collection('members')
        .doc(uid);
  }

  DocumentReference<Map<String, dynamic>> _legacyRef({
    required String clinicId,
    required String uid,
  }) {
    return _db
        .collection('clinics')
        .doc(clinicId)
        .collection('memberships')
        .doc(uid);
  }

  /// Cache so StreamBuilder rebuilds (e.g. tab switch) do not create a new stream
  /// and resubscribe, which would show loading again (ConnectionState.waiting).
  Stream<Membership?>? _cachedMembershipStream;
  String? _cachedMembershipStreamClinicId;
  String? _cachedMembershipStreamUid;

  /// Clears the cached membership stream so the next [watchClinicMembership]
  /// call creates a fresh subscription. Use after a loading timeout so the user
  /// can retry without restarting the app.
  void clearMembershipStreamCache() {
    _cachedMembershipStream = null;
    _cachedMembershipStreamClinicId = null;
    _cachedMembershipStreamUid = null;
  }

  /// Watches the membership doc (canonical first, legacy fallback).
  ///
  /// Cached per (clinicId, uid) so the shell's StreamBuilder does not get a new
  /// stream on tab switch and get stuck on loading.
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

    if (_cachedMembershipStreamClinicId == c &&
        _cachedMembershipStreamUid == u &&
        _cachedMembershipStream != null) {
      return _cachedMembershipStream!;
    }

    final canon = _canonicalRef(clinicId: c, uid: u);
    _cachedMembershipStreamClinicId = c;
    _cachedMembershipStreamUid = u;
    _cachedMembershipStream = canon
        .snapshots()
        .asyncMap((canonSnap) async {
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
        })
        .asBroadcastStream();
    return _cachedMembershipStream!;
  }

  /// One-shot read (canonical first, legacy fallback).
  Future<Membership?> getClinicMembership({
    required String clinicId,
    required String uid,
  }) async {
    final c = clinicId.trim();
    final u = uid.trim();
    if (c.isEmpty || u.isEmpty) {
      if (kDebugMode) {
        debugPrint(
            '[MembershipsRepository.getClinicMembership] Empty clinicId or uid');
      }
      return null;
    }

    if (kDebugMode) {
      debugPrint(
          '[MembershipsRepository.getClinicMembership] Checking membership');
      debugPrint('  clinicId: $c');
      debugPrint('  uid: $u');
    }

    try {
      final canonRef = _canonicalRef(clinicId: c, uid: u);
      final canonSnap = await canonRef.get();

      if (kDebugMode) {
        debugPrint(
            '  Canonical path (clinics/$c/members/$u): ${canonSnap.exists ? "EXISTS" : "NOT FOUND"}');
      }

      if (canonSnap.exists) {
        final data = canonSnap.data();
        if (data == null) {
          if (kDebugMode) {
            debugPrint('  ❌ Canonical doc exists but data is null');
          }
          return null;
        }
        if (kDebugMode) {
          debugPrint('  ✅ Using canonical membership');
          debugPrint('    data keys: ${data.keys.join(", ")}');
          debugPrint('    active: ${data["active"]}');
          debugPrint('    status: ${data["status"] ?? "(null)"}');
        }
        return Membership.fromFirestore(c, data);
      }

      final legacyRef = _legacyRef(clinicId: c, uid: u);
      final legacySnap = await legacyRef.get();

      if (kDebugMode) {
        debugPrint(
            '  Legacy path (clinics/$c/memberships/$u): ${legacySnap.exists ? "EXISTS" : "NOT FOUND"}');
      }

      if (!legacySnap.exists) {
        if (kDebugMode) {
          debugPrint(
              '  ❌ No membership found in either canonical or legacy path');
        }
        return null;
      }

      final data = legacySnap.data();
      if (data == null) {
        if (kDebugMode) {
          debugPrint('  ❌ Legacy doc exists but data is null');
        }
        return null;
      }

      if (kDebugMode) {
        debugPrint('  ✅ Using legacy membership');
        debugPrint('    data keys: ${data.keys.join(", ")}');
        debugPrint('    active: ${data["active"]}');
        debugPrint('    status: ${data["status"] ?? "(null)"}');
      }

      return Membership.fromFirestore(c, data);
    } on FirebaseException catch (e, st) {
      if (kDebugMode) {
        debugPrint(
            '[MembershipsRepository.getClinicMembership] ❌ Firestore error');
        debugPrint('  code: ${e.code}');
        debugPrint('  message: ${e.message}');
        debugPrint('  stack: $st');
      }
      rethrow;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
            '[MembershipsRepository.getClinicMembership] ❌ Unexpected error: $e');
        debugPrint('  stack: $st');
      }
      rethrow;
    }
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
