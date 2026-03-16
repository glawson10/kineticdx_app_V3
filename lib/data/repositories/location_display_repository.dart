// lib/data/repositories/location_display_repository.dart
// clinics/{clinicId}/settings/locationDisplay — read via Firestore, write via settingsUpdateLocationDisplayOrder.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../models/location_display_settings.dart';

class LocationDisplayRepository {
  LocationDisplayRepository(this._firestore);
  final FirebaseFirestore _firestore;

  static const String _docId = 'locationDisplay';

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'europe-west3');

  Stream<LocationDisplaySettings> streamSettings(String clinicId) {
    final c = clinicId.trim();
    if (c.isEmpty) return Stream.value(const LocationDisplaySettings());
    return _firestore
        .collection('clinics')
        .doc(c)
        .collection('settings')
        .doc(_docId)
        .snapshots()
        .map((snap) => LocationDisplaySettings.fromDoc(snap.data()));
  }

  /// Persists location display order via callable (callable-only write path).
  Future<void> updateSettings(
    String clinicId,
    LocationDisplaySettings settings,
  ) async {
    final c = clinicId.trim();
    if (c.isEmpty) return;
    final fn = _functions.httpsCallable('settingsUpdateLocationDisplayOrder');
    await fn.call({'clinicId': c, 'locationIds': settings.locationIds});
  }
}
