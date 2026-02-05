// lib/data/repositories/staff_repository.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class StaffRepository {
  StaffRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _fn =
            functions ?? FirebaseFunctions.instanceFor(region: 'europe-west3');

  final FirebaseFirestore _db;
  final FirebaseFunctions _fn;

  // ✅ Canonical = members (matches rules + MembershipsRepository)
  // 🟡 Legacy fallback = memberships (temporary migration support)
  static const String _membersSubcollection = 'members'; // ✅ canonical
  static const String _membershipsSubcollection =
      'memberships'; // legacy/fallback

  CollectionReference<Map<String, dynamic>> _membersCol(String clinicId) {
    return _db
        .collection('clinics')
        .doc(clinicId.trim())
        .collection(_membersSubcollection);
  }

  CollectionReference<Map<String, dynamic>> _membershipsCol(String clinicId) {
    return _db
        .collection('clinics')
        .doc(clinicId.trim())
        .collection(_membershipsSubcollection);
  }

  // ─────────────────────────────
  // Single membership doc (canonical-first fallback)
  // ─────────────────────────────

  /// Stream membership doc data using:
  ///   1) clinics/{clinicId}/members/{uid}        (canonical)
  ///   2) clinics/{clinicId}/memberships/{uid}    (legacy fallback)
  ///
  /// Returns null if neither exists.
  Stream<Map<String, dynamic>?> watchMembershipDataWithFallback(
    String clinicId,
    String memberUid,
  ) {
    final c = clinicId.trim();
    final u = memberUid.trim();
    if (c.isEmpty || u.isEmpty) return const Stream.empty();

    final canonRef = _membersCol(c).doc(u);
    final legacyRef = _membershipsCol(c).doc(u);

    debugPrint(
      '[StaffRepository] watchMembershipDataWithFallback canon=${canonRef.path} legacy=${legacyRef.path}',
    );

    return canonRef.snapshots().switchMap((canonSnap) {
      if (canonSnap.exists) return Stream.value(canonSnap.data());

      return legacyRef.snapshots().map((legacySnap) {
        if (!legacySnap.exists) return null;
        return legacySnap.data();
      });
    });
  }

  // ─────────────────────────────
  // Membership list (canonical-first merge)
  // ─────────────────────────────

  /// Reads BOTH collections and merges them:
  /// - canonical (/members) wins if a uid exists in both places
  /// - legacy-only members are included (migration safety)
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      watchMembershipsWithFallback(
    String clinicId,
  ) {
    final c = clinicId.trim();
    if (c.isEmpty) return const Stream.empty();

    final canonRef = _membersCol(c); // ✅ /members
    final legacyRef = _membershipsCol(c); // 🟡 /memberships

    debugPrint(
      '[StaffRepository] watchMembershipsWithFallback canon=${canonRef.path} legacy=${legacyRef.path}',
    );

    return RxCombineLatest2<
        QuerySnapshot<Map<String, dynamic>>,
        QuerySnapshot<Map<String, dynamic>>,
        List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      canonRef.snapshots(),
      legacyRef.snapshots(),
      (canonSnap, legacySnap) {
        final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

        // legacy first
        for (final d in legacySnap.docs) {
          byId[d.id] = d;
        }
        // canonical overwrites
        for (final d in canonSnap.docs) {
          byId[d.id] = d;
        }

        final docs = byId.values.toList();

        // Sort by createdAt desc if present
        docs.sort((a, b) {
          final ta = a.data()['createdAt'];
          final tb = b.data()['createdAt'];

          DateTime da = DateTime.fromMillisecondsSinceEpoch(0);
          DateTime dbb = DateTime.fromMillisecondsSinceEpoch(0);

          if (ta is Timestamp) da = ta.toDate();
          if (tb is Timestamp) dbb = tb.toDate();

          return dbb.compareTo(da);
        });

        debugPrint(
          '[StaffRepository] watchMembershipsWithFallback -> canon=${canonSnap.docs.length} legacy=${legacySnap.docs.length} merged=${docs.length}',
        );

        return docs;
      },
    );
  }

  // ─────────────────────────────
  // Optional list streams
  // ─────────────────────────────

  /// ✅ Canonical-only list (members)
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchMembers(
    String clinicId,
  ) {
    final c = clinicId.trim();
    if (c.isEmpty) return const Stream.empty();

    final ref = _membersCol(c);
    debugPrint('[StaffRepository] watchMembers (canonical) path=${ref.path}');
    return ref.snapshots().map((snap) => snap.docs);
  }

  /// 🟡 Legacy-only list (memberships)
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      watchMembershipsLegacy(
    String clinicId,
  ) {
    final c = clinicId.trim();
    if (c.isEmpty) return const Stream.empty();

    final ref = _membershipsCol(c);
    debugPrint('[StaffRepository] watchMembershipsLegacy path=${ref.path}');
    return ref.snapshots().map((snap) => snap.docs);
  }

  // ─────────────────────────────
  // Callables
  // ─────────────────────────────

  Future<Map<String, dynamic>> inviteMember({
    required String clinicId,
    required String email,
    required String roleId,
  }) async {
    final callable = _fn.httpsCallable('inviteMemberFn');

    final res = await callable.call(<String, dynamic>{
      'clinicId': clinicId.trim(),
      'email': email.trim().toLowerCase(),
      'roleId': roleId.trim(),
    });

    final data = res.data;
    if (data is Map) return Map<String, dynamic>.from(data);

    throw StateError('inviteMemberFn returned unexpected payload: $data');
  }

  Future<void> setMembershipStatus({
    required String clinicId,
    required String memberUid,
    required String status,
  }) async {
    final callable = _fn.httpsCallable('setMembershipStatusFn');

    final res = await callable.call(<String, dynamic>{
      'clinicId': clinicId.trim(),
      'memberUid': memberUid.trim(),
      'status': status.trim(),
    });

    final data = res.data;
    if (data is Map && data['ok'] == true) return;

    throw StateError(
        'setMembershipStatusFn returned unexpected payload: $data');
  }

  Future<void> updateMemberDisplayName({
    required String clinicId,
    required String memberUid,
    required String displayName,
  }) async {
    final callable = _fn.httpsCallable('updateMemberProfileFn');

    final res = await callable.call(<String, dynamic>{
      'clinicId': clinicId.trim(),
      'memberUid': memberUid.trim(),
      'displayName': displayName.trim(),
    });

    final data = res.data;
    if (data is Map && data['ok'] == true) return;

    throw StateError(
        'updateMemberProfileFn returned unexpected payload: $data');
  }
}

/// Minimal combineLatest for two Firestore streams without adding rxdart.
class RxCombineLatest2<A, B, R> extends Stream<R> {
  RxCombineLatest2(this._a, this._b, this._combine);

  final Stream<A> _a;
  final Stream<B> _b;
  final R Function(A a, B b) _combine;

  @override
  StreamSubscription<R> listen(
    void Function(R event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    late StreamSubscription<A> subA;
    late StreamSubscription<B> subB;

    A? lastA;
    B? lastB;
    var hasA = false;
    var hasB = false;

    final controller = StreamController<R>();

    void emitIfReady() {
      if (hasA && hasB) controller.add(_combine(lastA as A, lastB as B));
    }

    subA = _a.listen((a) {
      lastA = a;
      hasA = true;
      emitIfReady();
    }, onError: controller.addError);

    subB = _b.listen((b) {
      lastB = b;
      hasB = true;
      emitIfReady();
    }, onError: controller.addError);

    controller.onCancel = () async {
      await subA.cancel();
      await subB.cancel();
    };

    return controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

extension _SwitchMapExt<T> on Stream<T> {
  Stream<R> switchMap<R>(Stream<R> Function(T value) mapper) {
    late StreamController<R> controller;
    StreamSubscription<T>? outerSub;
    StreamSubscription<R>? innerSub;

    controller = StreamController<R>(onListen: () {
      outerSub = listen(
          (event) async {
            await innerSub?.cancel();
            innerSub = mapper(event).listen(
              controller.add,
              onError: controller.addError,
            );
          },
          onError: controller.addError,
          onDone: () async {
            await innerSub?.cancel();
            await controller.close();
          });
    }, onCancel: () async {
      await outerSub?.cancel();
      await innerSub?.cancel();
    });

    return controller.stream;
  }
}
