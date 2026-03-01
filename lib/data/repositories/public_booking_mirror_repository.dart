// lib/data/repositories/public_booking_mirror_repository.dart
//
// Commit 17: Read-only. Reads clinics/{clinicId}/public/config/publicBooking/config.
// Used by availability engine and public booking flow. No callables.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/public_booking_config_v1.dart';

/// Path to the minimal public config doc (Commit 16 projection).
String publicBookingConfigPath(String clinicId) {
  final c = clinicId.trim();
  if (c.isEmpty) return '';
  return 'clinics/$c/public/config/publicBooking/config';
}

class PublicBookingMirrorRepository {
  PublicBookingMirrorRepository(this._firestore);

  final FirebaseFirestore _firestore;

  /// Cached stream per clinicId so StreamBuilder rebuilds don't cancel/resubscribe
  /// and trigger Firestore web SDK "Unexpected state" assertion.
  Stream<PublicBookingConfigV1?>? _cachedConfigStream;
  String? _cachedConfigStreamClinicId;

  DocumentReference<Map<String, dynamic>> _doc(String clinicId) {
    final path = publicBookingConfigPath(clinicId);
    if (path.isEmpty) throw ArgumentError('clinicId required');
    return _firestore.doc(path);
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
}
