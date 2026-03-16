import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../models/public_booking_settings.dart';

class PublicBookingSettingsRepository {
  PublicBookingSettingsRepository(this._firestore);
  final FirebaseFirestore _firestore;

  Stream<PublicBookingSettings> streamSettings(String clinicId) {
    final c = clinicId.trim();
    if (c.isEmpty) return Stream.value(const PublicBookingSettings());
    return _firestore
        .collection('clinics')
        .doc(c)
        .collection('settings')
        .doc('publicBooking')
        .snapshots()
        .map((snap) => PublicBookingSettings.fromDoc(snap.data()));
  }

  Future<void> updateSettings(String clinicId, Map<String, dynamic> patch) async {
    final fn = FirebaseFunctions.instanceFor(region: 'europe-west3')
        .httpsCallable('settingsUpdatePublicBookingConfig');
    await fn.call({'clinicId': clinicId, 'patch': patch});
  }
}
