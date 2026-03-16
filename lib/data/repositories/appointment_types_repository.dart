import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../models/appointment_type.dart';

class AppointmentTypesRepository {
  AppointmentTypesRepository(this._firestore);
  final FirebaseFirestore _firestore;

  /// Watches all appointment types (active and inactive) for settings list.
  Stream<List<AppointmentType>> watchAllTypes(String clinicId) {
    final c = clinicId.trim();
    if (c.isEmpty) return Stream.value([]);
    return _firestore
        .collection('clinics')
        .doc(c)
        .collection('appointmentTypes')
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => AppointmentType.fromFirestore(d.id, d.data()))
            .toList());
  }

  /// Watches active appointment types only (for calendar picker / public).
  Stream<List<AppointmentType>> watchActiveTypes(String clinicId) {
    final c = clinicId.trim();
    if (c.isEmpty) return Stream.value([]);
    return _firestore
        .collection('clinics')
        .doc(c)
        .collection('appointmentTypes')
        .where('active', isEqualTo: true)
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => AppointmentType.fromFirestore(d.id, d.data()))
            .toList());
  }

  @Deprecated('Use watchActiveTypes for List<AppointmentType> or watchAllTypes for settings')
  Stream<QuerySnapshot<Map<String, dynamic>>> watchTypes(String clinicId) {
    final c = clinicId.trim();
    if (c.isEmpty) return const Stream.empty();
    return _firestore
        .collection('clinics')
        .doc(c)
        .collection('appointmentTypes')
        .where('active', isEqualTo: true)
        .orderBy('name')
        .snapshots();
  }

  Stream<List<AppointmentType>> watchAppointmentTypesViaCallable(String clinicId) {
    return watchActiveTypes(clinicId);
  }

  /// Creates or updates an appointment type. For create, omit [appointmentTypeId].
  /// [patch] must contain at least one of: name, durationMinutes, colorHex, active,
  /// showInOnlineBooking, description, defaultPrice, allowedLocationIds.
  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'europe-west3');

  Future<void> upsert(String clinicId, {String? appointmentTypeId, required Map<String, dynamic> patch}) async {
    final fn = _functions.httpsCallable('settingsUpsertAppointmentType');
    final payload = <String, dynamic>{'clinicId': clinicId, 'patch': patch};
    if (appointmentTypeId != null && appointmentTypeId.trim().isNotEmpty) {
      payload['appointmentTypeId'] = appointmentTypeId.trim();
    }
    await fn.call(payload);
  }

  Future<void> setActive(String clinicId, String appointmentTypeId, bool active) async {
    final fn = _functions.httpsCallable('settingsSetAppointmentTypeActive');
    await fn.call({'clinicId': clinicId, 'appointmentTypeId': appointmentTypeId, 'active': active});
  }

  Future<void> upsertAppointmentType({
    required String clinicId,
    String? appointmentTypeId,
    required Map<String, dynamic> patch,
  }) async {
    return upsert(clinicId, appointmentTypeId: appointmentTypeId, patch: patch);
  }

  Future<void> setAppointmentTypeActive({
    required String clinicId,
    required String appointmentTypeId,
    required bool active,
  }) async {
    return setActive(clinicId, appointmentTypeId, active);
  }
}
