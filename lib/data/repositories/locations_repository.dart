import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../models/clinic_location.dart';

class LocationsRepository {
  final _firestore = FirebaseFirestore.instance;

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'europe-west3');

  Stream<List<ClinicLocation>> watchLocations(String clinicId) {
    final c = clinicId.trim();
    if (c.isEmpty) return Stream.value([]);
    return _firestore
        .collection('clinics')
        .doc(c)
        .collection('locations')
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ClinicLocation.fromDoc(d.id, d.data()))
            .toList());
  }

  Future<void> upsert(String clinicId, {String? locationId, required Map<String, dynamic> patch}) async {
    final fn = _functions.httpsCallable('settingsUpsertLocation');
    final payload = <String, dynamic>{'clinicId': clinicId, 'patch': patch};
    if (locationId != null && locationId.trim().isNotEmpty) payload['locationId'] = locationId.trim();
    await fn.call(payload);
  }

  Stream<List<ClinicLocation>> watchLocationsViaCallable(String clinicId) {
    return watchLocations(clinicId);
  }

  Future<void> setActive(String clinicId, String locationId, bool active) async {
    final fn = _functions.httpsCallable('settingsSetLocationActive');
    await fn.call({'clinicId': clinicId, 'locationId': locationId, 'active': active});
  }

  /// Updates location opening hours. Must be within clinic opening hours.
  Future<void> updateLocationWeeklyHours(
    String clinicId,
    String locationId,
    Map<String, List<Map<String, String>>> weeklyHours,
  ) async {
    final fn = _functions.httpsCallable('settingsUpdateLocationWeeklyHours');
    await fn.call({
      'clinicId': clinicId,
      'locationId': locationId,
      'weeklyHours': weeklyHours,
    });
  }
}
