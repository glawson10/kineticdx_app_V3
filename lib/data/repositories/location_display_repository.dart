// lib/data/repositories/location_display_repository.dart
// clinics/{clinicId}/settings/locationDisplay

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/location_display_settings.dart';

class LocationDisplayRepository {
  LocationDisplayRepository(this._firestore);
  final FirebaseFirestore _firestore;

  static const String _docId = 'locationDisplay';

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

  Future<void> updateSettings(
    String clinicId,
    LocationDisplaySettings settings,
  ) async {
    final c = clinicId.trim();
    if (c.isEmpty) return;
    final ref = _firestore
        .collection('clinics')
        .doc(c)
        .collection('settings')
        .doc(_docId);
    final data = Map<String, dynamic>.from(settings.toMap());
    data['updatedAt'] = FieldValue.serverTimestamp();
    await ref.set(data, SetOptions(merge: true));
  }
}
