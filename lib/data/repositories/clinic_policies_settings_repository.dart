// lib/data/repositories/clinic_policies_settings_repository.dart
//
// clinics/{clinicId}/settings/policies. Client read/write (settings.write for writes).

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/clinic_policies_settings.dart';

class ClinicPoliciesSettingsRepository {
  ClinicPoliciesSettingsRepository(this._firestore);
  final FirebaseFirestore _firestore;

  static const String _docId = 'policies';

  Stream<ClinicPoliciesSettings> streamSettings(String clinicId) {
    final c = clinicId.trim();
    if (c.isEmpty) return Stream.value(const ClinicPoliciesSettings());
    return _firestore
        .collection('clinics')
        .doc(c)
        .collection('settings')
        .doc(_docId)
        .snapshots()
        .map((snap) => ClinicPoliciesSettings.fromDoc(snap.data()));
  }

  Future<void> updateSettings(
    String clinicId,
    ClinicPoliciesSettings settings,
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
