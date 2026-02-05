import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../models/appointment.dart';

/// Thrown when a booking overlaps a clinic closure.
class ClinicClosureConflictException implements Exception {
  final String message;
  ClinicClosureConflictException(
      [this.message = 'Clinic is closed during this time.']);

  @override
  String toString() => message;
}

class AppointmentsRepository {
  final FirebaseFunctions _functions;
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  /// Cloud Functions are deployed to europe-west3.
  /// On Flutter Web, region MUST be explicitly specified.
  AppointmentsRepository({
    FirebaseFunctions? functions,
    FirebaseFirestore? db,
    FirebaseAuth? auth,
  })  : _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'europe-west3'),
        _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> _col(String clinicId) {
    return _db.collection('clinics').doc(clinicId).collection('appointments');
  }

  // ---------------------------------------------------------------------------
  // Auth helpers
  // ---------------------------------------------------------------------------
  User _requireUser() {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in.');
    return user;
  }

  Future<T> _call<T>(String name, Map<String, dynamic> payload) async {
    _requireUser();

    try {
      final res = await _functions.httpsCallable(name).call(payload);
      return res.data as T;
    } on FirebaseFunctionsException catch (e, st) {
      debugPrint('❌ Callable $name failed');
      debugPrint('   code: ${e.code}');
      debugPrint('   message: ${e.message}');
      debugPrint('   details: ${e.details}');
      debugPrint('   stack: $st');

      // 🔒 Clinic closure enforcement
      if (e.code == 'failed-precondition' &&
          (e.message?.toLowerCase().contains('closure') ?? false)) {
        throw ClinicClosureConflictException();
      }

      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Watch appointments
  // ---------------------------------------------------------------------------
  /// Watches appointments for a given week (Mon..Sun).
  ///
  /// If [practitionerId] is provided, results are filtered to that practitioner.
  ///
  /// ✅ Firestore index note:
  /// When practitionerId filter is applied, Firestore typically requires a
  /// composite index on:
  ///   practitionerId (ASC), startAt (ASC)
  /// for the combination of:
  ///   where practitionerId == X
  ///   where startAt >= A and startAt < B
  ///   orderBy startAt
  Stream<List<Appointment>> watchAppointmentsForWeek({
    required String clinicId,
    required DateTime weekStart,
    String? practitionerId,
  }) {
    // Use local week boundaries (Prague/local), Firestore stores absolute instants.
    final startLocal = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final endLocal = startLocal.add(const Duration(days: 7));

    Query<Map<String, dynamic>> q = _col(clinicId)
        .where('startAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startLocal))
        .where('startAt', isLessThan: Timestamp.fromDate(endLocal));

    final pid = (practitionerId ?? '').trim();
    if (pid.isNotEmpty) {
      q = q.where('practitionerId', isEqualTo: pid);
    }

    // Range field must be the first orderBy.
    q = q.orderBy('startAt');

    return q.snapshots().handleError((Object e) {
      // Make the “missing composite index” problem super obvious in terminal.
      if (e is FirebaseException &&
          e.code == 'failed-precondition' &&
          (e.message?.toLowerCase().contains('index') ?? false)) {
        debugPrint(
          '⚠️ Firestore requires a composite index for appointments query.\n'
          '   Collection: clinics/{clinicId}/appointments\n'
          '   Likely fields: practitionerId ASC, startAt ASC\n'
          '   Full error: ${e.message}',
        );
      }
      throw e;
    }).map((snap) {
      return snap.docs.map((d) {
        final data = d.data();

        // ✅ Back-compat HARDENED:
        // Some parts of the app/model may read start/end,
        // others read startAt/endAt. Ensure both are always present.
        final patched = Map<String, dynamic>.from(data);

        // Prefer canonical startAt/endAt if present
        patched['startAt'] ??= patched['start'];
        patched['endAt'] ??= patched['end'];

        // Also provide legacy keys if only canonical exist
        patched['start'] ??= patched['startAt'];
        patched['end'] ??= patched['endAt'];

        return Appointment.fromFirestore(d.id, patched);
      }).toList();
    });
  }

  // ---------------------------------------------------------------------------
  // Create appointment
  // ---------------------------------------------------------------------------
  Future<String> createAppointment({
    required String clinicId,
    required String kind,
    String? patientId,
    String? serviceId,
    String? practitionerId,
    required DateTime start,
    required DateTime end,
  }) async {
    // ✅ Standardize: ALWAYS send UTC ms to Cloud Functions.
    final data = await _call<Map>('createAppointmentFn', {
      'clinicId': clinicId,
      'kind': kind,
      if (patientId != null) 'patientId': patientId,
      if (serviceId != null) 'serviceId': serviceId,
      if (practitionerId != null) 'practitionerId': practitionerId,
      'startMs': start.toUtc().millisecondsSinceEpoch,
      'endMs': end.toUtc().millisecondsSinceEpoch,
    });

    return data['appointmentId'] as String;
  }

  // ---------------------------------------------------------------------------
  // Update appointment (time only) + allowClosedOverride
  // ---------------------------------------------------------------------------
  Future<void> updateAppointment({
    required String clinicId,
    required String appointmentId,
    required DateTime start,
    required DateTime end,
    bool allowClosedOverride = false,
  }) async {
    await _call<void>('updateAppointmentFn', {
      'clinicId': clinicId,
      'appointmentId': appointmentId,
      'startMs': start.toUtc().millisecondsSinceEpoch,
      'endMs': end.toUtc().millisecondsSinceEpoch,
      'allowClosedOverride': allowClosedOverride,
    });
  }

  // ---------------------------------------------------------------------------
  // Update appointment details (time/kind/service)
  // ---------------------------------------------------------------------------
  Future<void> updateAppointmentDetails({
    required String clinicId,
    required String appointmentId,
    DateTime? start,
    DateTime? end,
    String? kind,
    String? serviceId,
    String? practitionerId, // optional if you later allow reassignment
    bool? allowClosedOverride, // optional if TS supports it here too
  }) async {
    final payload = <String, dynamic>{
      'clinicId': clinicId,
      'appointmentId': appointmentId,
    };

    // Keep consistent: send UTC ms.
    if (start != null) payload['startMs'] = start.toUtc().millisecondsSinceEpoch;
    if (end != null) payload['endMs'] = end.toUtc().millisecondsSinceEpoch;

    if (kind != null) payload['kind'] = kind;
    if (serviceId != null) payload['serviceId'] = serviceId;

    if (practitionerId != null) {
      final pid = practitionerId.trim();
      if (pid.isNotEmpty) payload['practitionerId'] = pid;
    }

    if (allowClosedOverride != null) {
      payload['allowClosedOverride'] = allowClosedOverride;
    }

    await _call<void>('updateAppointmentFn', payload);
  }

  // ---------------------------------------------------------------------------
  // Update appointment status
  // ---------------------------------------------------------------------------
  Future<void> updateAppointmentStatus({
    required String clinicId,
    required String appointmentId,
    required String status,
  }) async {
    await _call<void>('updateAppointmentStatusFn', {
      'clinicId': clinicId,
      'appointmentId': appointmentId,
      'status': status,
    });
  }

  // ---------------------------------------------------------------------------
  // Delete appointment
  // ---------------------------------------------------------------------------
  Future<void> deleteAppointment({
    required String clinicId,
    required String appointmentId,
  }) async {
    await _call<void>('deleteAppointmentFn', {
      'clinicId': clinicId,
      'appointmentId': appointmentId,
    });
  }
}
