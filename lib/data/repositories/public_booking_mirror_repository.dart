// lib/data/repositories/public_booking_mirror_repository.dart
//
// Commit 17: Read-only. Reads clinics/{clinicId}/public/config/publicBooking/config
// and .../publicBooking/publicBooking (full mirror). No callables.
// Cached streams avoid Firestore web SDK LateInitializationError when StreamBuilder
// is disposed before the snapshot callback runs.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/public_booking_config_v1.dart';

/// Path to the minimal public config doc (Commit 16 projection).
String publicBookingConfigPath(String clinicId) {
  final c = clinicId.trim();
  if (c.isEmpty) return '';
  return 'clinics/$c/public/config/publicBooking/config';
}

/// Path to the full public booking mirror doc (contact, practitioners list, etc.).
String publicBookingFullMirrorPath(String clinicId) {
  final c = clinicId.trim();
  if (c.isEmpty) return '';
  return 'clinics/$c/public/config/publicBooking/publicBooking';
}

class PublicBookingMirrorRepository {
  PublicBookingMirrorRepository(this._firestore);

  final FirebaseFirestore _firestore;

  /// Cached stream per clinicId so StreamBuilder rebuilds don't cancel/resubscribe
  /// and trigger Firestore web SDK "Unexpected state" assertion.
  Stream<PublicBookingConfigV1?>? _cachedConfigStream;
  String? _cachedConfigStreamClinicId;

  /// Cached stream for full mirror doc (intro/price_list contact). Single Firestore
  /// subscription + broadcast so cancel only unsubs from our controller, not Firestore.
  String? _cachedFullMirrorClinicId;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _cachedFullMirrorStream;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _fullMirrorSub;
  StreamController<DocumentSnapshot<Map<String, dynamic>>>? _fullMirrorController;
  DocumentSnapshot<Map<String, dynamic>>? _lastFullMirrorSnap;

  DocumentReference<Map<String, dynamic>> _doc(String clinicId) {
    final path = publicBookingConfigPath(clinicId);
    if (path.isEmpty) throw ArgumentError('clinicId required');
    return _firestore.doc(path);
  }

  DocumentReference<Map<String, dynamic>> _fullMirrorDoc(String clinicId) {
    final path = publicBookingFullMirrorPath(clinicId);
    if (path.isEmpty) throw ArgumentError('clinicId required');
    return _firestore.doc(path);
  }

  /// One-shot read of the full public mirror doc (appointment types, contact, etc.).
  /// Returns null if doc missing.
  Future<Map<String, dynamic>?> getFullMirrorData(String clinicId) async {
    final c = clinicId.trim();
    if (c.isEmpty) return null;
    final snap = await _fullMirrorDoc(c).get();
    if (!snap.exists || snap.data() == null) return null;
    return snap.data();
  }

  /// One-shot read. Returns null if doc missing.
  Future<PublicBookingConfigV1?> getConfig(String clinicId) async {
    final c = clinicId.trim();
    if (c.isEmpty) return null;
    final snap = await _doc(c).get();
    if (!snap.exists || snap.data() == null) return null;
    return PublicBookingConfigV1.fromDoc(snap.data());
  }

  /// Stream. Emits null if doc missing or invalid.
  /// Cached per clinicId to avoid cancel/resubscribe and Firestore "Unexpected state" on web.
  Stream<PublicBookingConfigV1?> streamConfig(String clinicId) {
    final c = clinicId.trim();
    if (c.isEmpty) return Stream.value(null);
    if (_cachedConfigStreamClinicId == c && _cachedConfigStream != null) {
      return _cachedConfigStream!;
    }
    _cachedConfigStreamClinicId = c;
    _cachedConfigStream = _doc(c).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return PublicBookingConfigV1.fromDoc(snap.data());
    }).asBroadcastStream();
    return _cachedConfigStream!;
  }

  /// Stream the full public booking mirror doc (contact info, etc.).
  /// Cached per clinicId; single Firestore subscription so StreamBuilder cancel
  /// does not hit Firestore web SDK LateInitializationError.
  Stream<DocumentSnapshot<Map<String, dynamic>>> streamFullMirrorDoc(String clinicId) {
    final c = clinicId.trim();
    if (c.isEmpty) return Stream.empty();
    if (_cachedFullMirrorClinicId == c && _cachedFullMirrorStream != null) {
      return _cachedFullMirrorStream!;
    }
    _fullMirrorSub?.cancel();
    _fullMirrorController?.close();
    _cachedFullMirrorClinicId = c;
    _lastFullMirrorSnap = null;
    _fullMirrorController = StreamController<DocumentSnapshot<Map<String, dynamic>>>.broadcast();
    final source = _fullMirrorDoc(c).snapshots();
    _fullMirrorSub = source.listen(
      (snap) {
        _lastFullMirrorSnap = snap;
        _fullMirrorController!.add(snap);
      },
      onError: _fullMirrorController!.addError,
      onDone: _fullMirrorController!.close,
      cancelOnError: false,
    );
    _cachedFullMirrorStream = Stream.multi((sink) {
      if (_lastFullMirrorSnap != null) sink.add(_lastFullMirrorSnap!);
      final sub = _fullMirrorController!.stream.listen(
        sink.add,
        onError: sink.addError,
        onDone: sink.close,
      );
      sink.onCancel = () => sub.cancel();
    });
    return _cachedFullMirrorStream!;
  }
}
