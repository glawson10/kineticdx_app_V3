import 'dart:async';

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

/// Thrown when update/reschedule would overlap another appointment
/// for the same practitioner.
class PractitionerOverlapException implements Exception {
  final String message;
  PractitionerOverlapException(
      [this.message =
          'This time slot is already booked for the selected practitioner.']);

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
      // 🔒 Practitioner overlap (reschedule)
      if (e.code == 'failed-precondition' &&
          (e.message?.toLowerCase().contains('already booked') ?? false)) {
        throw PractitionerOverlapException(e.message ??
            'This time slot is already booked for the selected practitioner.');
      }
      // 🔒 Series conflict (recurrence create/update)
      if (e.code == 'failed-precondition' &&
          (e.message == 'series_conflict' || (e.details is Map && (e.details as Map).containsKey('conflicts')))) {
        final details = e.details;
        if (details is Map && details['conflicts'] is List && (details['conflicts'] as List).isNotEmpty) {
          final first = (details['conflicts'] as List).first as Map?;
          final msg = first?['message']?.toString() ?? 'A time slot in the series conflicts with an existing booking or closure.';
          throw PractitionerOverlapException(msg);
        }
        throw PractitionerOverlapException(
            'A time slot in the series conflicts with an existing booking or closure.');
      }

      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Watch appointments
  // ---------------------------------------------------------------------------

  /// Cached per (clinicId, start, end, practitionerId) so StreamBuilder keeps
  /// the same subscription when re-entering calendar (avoids Firestore Web
  /// cancel-before-init / LateInitializationError).
  String? _cachedAppointmentsKey;
  Stream<List<Appointment>>? _cachedAppointmentsStream;
  StreamSubscription<List<Appointment>>? _appointmentsSub;
  StreamSubscription<List<Appointment>>? _adminAppointmentsSub;
  StreamController<List<Appointment>>? _appointmentsController;
  List<Appointment>? _lastAppointments;

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

    return watchAppointmentsForDateRange(
      clinicId: clinicId,
      startLocal: startLocal,
      endLocal: endLocal,
      practitionerId: practitionerId,
    );
  }

  /// Watches appointments in a date range [startLocal, endLocal) (local day boundaries).
  /// Used for month view and any range-based calendar.
  /// Cached per key; replays last value to new listeners.
  Stream<List<Appointment>> watchAppointmentsForDateRange({
    required String clinicId,
    required DateTime startLocal,
    required DateTime endLocal,
    String? practitionerId,
  }) {
    final start = DateTime(startLocal.year, startLocal.month, startLocal.day);
    final end = DateTime(endLocal.year, endLocal.month, endLocal.day);

    final pid = (practitionerId ?? '').trim();
    final key = '${clinicId.trim()}|${start.millisecondsSinceEpoch}|${end.millisecondsSinceEpoch}|$pid';
    if (_cachedAppointmentsKey == key && _cachedAppointmentsStream != null) {
      return _cachedAppointmentsStream!;
    }

    _appointmentsSub?.cancel();
    _adminAppointmentsSub?.cancel();
    _appointmentsController?.close();
    _cachedAppointmentsKey = key;
    _lastAppointments = null;
    _appointmentsController = StreamController<List<Appointment>>.broadcast();

    List<Appointment> _merge(List<Appointment> practitioner, List<Appointment> admin) {
      final ids = <String>{};
      final out = <Appointment>[];
      for (final a in practitioner) {
        if (ids.add(a.id)) out.add(a);
      }
      for (final a in admin) {
        if (ids.add(a.id)) out.add(a);
      }
      out.sort((a, b) => a.start.millisecondsSinceEpoch.compareTo(b.start.millisecondsSinceEpoch));
      return out;
    }

    final col = _col(clinicId);
    final baseRange = col
        .where('startAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('startAt', isLessThan: Timestamp.fromDate(end));

    Stream<List<Appointment>> _docsToAppointments(QuerySnapshot<Map<String, dynamic>> snap) {
      return Stream.value(snap.docs.map((d) {
        final data = d.data();
        final patched = Map<String, dynamic>.from(data);
        patched['startAt'] ??= patched['start'];
        patched['endAt'] ??= patched['end'];
        patched['start'] ??= patched['startAt'];
        patched['end'] ??= patched['endAt'];
        return Appointment.fromFirestore(d.id, patched);
      }).toList());
    }

    void _onError(Object e) {
      if (e is FirebaseException &&
          e.code == 'failed-precondition' &&
          (e.message?.toLowerCase().contains('index') ?? false)) {
        debugPrint(
          '⚠️ Firestore requires a composite index for appointments query.\n'
          '   Full error: ${e.message}',
        );
      }
      _appointmentsController?.addError(e);
    }

    if (pid.isNotEmpty) {
      // Practitioner appointments + admin blocks (admin has no practitionerId so excluded from first query)
      List<Appointment> lastPractitioner = [];
      List<Appointment> lastAdmin = [];

      final practitionerQuery = baseRange
          .where('practitionerId', isEqualTo: pid)
          .orderBy('startAt');
      final adminQuery = baseRange
          .where('kind', isEqualTo: 'admin')
          .orderBy('startAt');

      void emitMerged() {
        final merged = _merge(lastPractitioner, lastAdmin);
        _lastAppointments = merged;
        _appointmentsController?.add(merged);
      }

      _appointmentsSub = practitionerQuery.snapshots().handleError(_onError).asyncMap((snap) => _docsToAppointments(snap).first).listen((list) {
        lastPractitioner = list;
        emitMerged();
      }, cancelOnError: false);

      _adminAppointmentsSub = adminQuery.snapshots().handleError(_onError).asyncMap((snap) => _docsToAppointments(snap).first).listen((list) {
        lastAdmin = list;
        emitMerged();
      }, cancelOnError: false);
    } else {
      Query<Map<String, dynamic>> q = baseRange.orderBy('startAt');
      final source = q.snapshots().handleError((Object e) {
        _onError(e);
        throw e;
      }).map((snap) {
        return snap.docs.map((d) {
          final data = d.data();
          final patched = Map<String, dynamic>.from(data);
          patched['startAt'] ??= patched['start'];
          patched['endAt'] ??= patched['end'];
          patched['start'] ??= patched['startAt'];
          patched['end'] ??= patched['endAt'];
          return Appointment.fromFirestore(d.id, patched);
        }).toList();
      });

      _appointmentsSub = source.listen(
        (list) {
          _lastAppointments = list;
          _appointmentsController?.add(list);
        },
        onError: _appointmentsController?.addError,
        onDone: () => _appointmentsController?.close(),
        cancelOnError: false,
      );
    }

    final ctrl = _appointmentsController!;
    _cachedAppointmentsStream = Stream.multi((sink) {
      if (_lastAppointments != null && _cachedAppointmentsKey == key) {
        sink.add(_lastAppointments!);
      }
      sink.addStream(ctrl.stream);
    });

    return _cachedAppointmentsStream!;
  }

  /// Call after creating/updating/cancelling an appointment so the calendar
  /// refetches and shows the new state (avoids stale or broken snapshot listener).
  void invalidateAppointmentsCache() {
    _appointmentsSub?.cancel();
    _adminAppointmentsSub?.cancel();
    _appointmentsController?.close();
    _appointmentsSub = null;
    _adminAppointmentsSub = null;
    _appointmentsController = null;
    _cachedAppointmentsKey = null;
    _cachedAppointmentsStream = null;
    _lastAppointments = null;
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
    String? locationId,
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
      if (locationId != null && locationId.trim().isNotEmpty) 'locationId': locationId.trim(),
      'startMs': start.toUtc().millisecondsSinceEpoch,
      'endMs': end.toUtc().millisecondsSinceEpoch,
    });

    return data['appointmentId'] as String;
  }

  // ---------------------------------------------------------------------------
  // Create appointment series (recurring)
  // ---------------------------------------------------------------------------
  /// Returns [seriesId] and [createdAppointmentIds]. Optionally [conflicts] if
  /// conflictPolicy was WARN_ALLOW.
  Future<Map<String, dynamic>> createAppointmentSeries({
    required String clinicId,
    required String kind,
    String? patientId,
    String? serviceId,
    String? practitionerId,
    required String tz,
    required DateTime start,
    required int durationMinutes,
    required Map<String, dynamic> rule,
    int generateDaysAhead = 180,
    String conflictPolicy = 'BLOCK',
  }) async {
    final data = await _call<Map>('createAppointmentSeriesFn', {
      'clinicId': clinicId,
      'kind': kind,
      if (patientId != null && patientId.isNotEmpty) 'patientId': patientId,
      if (serviceId != null && serviceId.isNotEmpty) 'serviceId': serviceId,
      if (practitionerId != null && practitionerId.isNotEmpty) 'practitionerId': practitionerId,
      'tz': tz,
      'startMs': start.toUtc().millisecondsSinceEpoch,
      'durationMinutes': durationMinutes,
      'rule': rule,
      'generateDaysAhead': generateDaysAhead,
      'conflictPolicy': conflictPolicy,
    });
    return Map<String, dynamic>.from(data);
  }

  // ---------------------------------------------------------------------------
  // Update single occurrence (marks series exception when part of series)
  // ---------------------------------------------------------------------------
  Future<void> updateAppointmentOccurrence({
    required String clinicId,
    required String appointmentId,
    DateTime? start,
    DateTime? end,
    String? kind,
    String? serviceId,
    String? practitionerId,
    bool markException = true,
    int? originalStartMs,
    bool allowClosedOverride = false,
  }) async {
    final payload = <String, dynamic>{
      'clinicId': clinicId,
      'appointmentId': appointmentId,
      'markException': markException,
      'allowClosedOverride': allowClosedOverride,
    };
    if (start != null) payload['startMs'] = start.toUtc().millisecondsSinceEpoch;
    if (end != null) payload['endMs'] = end.toUtc().millisecondsSinceEpoch;
    if (kind != null) payload['kind'] = kind;
    if (serviceId != null) payload['serviceId'] = serviceId;
    if (practitionerId != null) payload['practitionerId'] = practitionerId;
    if (originalStartMs != null) payload['originalStartMs'] = originalStartMs;
    await _call<void>('updateAppointmentOccurrenceFn', payload);
  }

  /// Update entire series (regenerate future occurrences from effectiveFrom).
  /// Not yet implemented on backend; throws.
  Future<Map<String, dynamic>> updateAppointmentSeries({
    required String clinicId,
    required String seriesId,
    String? kind,
    String? patientId,
    String? serviceId,
    String? practitionerId,
    String? startTimeLocal,
    int? durationMinutes,
    Map<String, dynamic>? rule,
    String? tz,
    int? effectiveFromMs,
    bool preserveExceptions = true,
    String conflictPolicy = 'BLOCK',
  }) async {
    final data = await _call<Map>('updateAppointmentSeriesFn', {
      'clinicId': clinicId,
      'seriesId': seriesId,
      if (kind != null) 'kind': kind,
      if (patientId != null) 'patientId': patientId,
      if (serviceId != null) 'serviceId': serviceId,
      if (practitionerId != null) 'practitionerId': practitionerId,
      if (startTimeLocal != null) 'startTimeLocal': startTimeLocal,
      if (durationMinutes != null) 'durationMinutes': durationMinutes,
      if (rule != null) 'rule': rule,
      if (tz != null) 'tz': tz,
      if (effectiveFromMs != null) 'effectiveFromMs': effectiveFromMs,
      'preserveExceptions': preserveExceptions,
      'conflictPolicy': conflictPolicy,
    });
    return Map<String, dynamic>.from(data);
  }

  /// Split series at given occurrence: old series ends before it, new series starts from it.
  /// Not yet implemented on backend; throws.
  Future<Map<String, dynamic>> splitAppointmentSeries({
    required String clinicId,
    required String seriesId,
    required String splitFromAppointmentId,
    String? newStartTimeLocal,
    int? newDurationMinutes,
    Map<String, dynamic>? newRule,
    String conflictPolicy = 'BLOCK',
  }) async {
    final data = await _call<Map>('splitAppointmentSeriesFn', {
      'clinicId': clinicId,
      'seriesId': seriesId,
      'splitFromAppointmentId': splitFromAppointmentId,
      if (newStartTimeLocal != null) 'newStartTimeLocal': newStartTimeLocal,
      if (newDurationMinutes != null) 'newDurationMinutes': newDurationMinutes,
      if (newRule != null) 'newRule': newRule,
      'conflictPolicy': conflictPolicy,
    });
    return Map<String, dynamic>.from(data);
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
    String? locationId, // BOOKING_DATA_CONTRACT; pass null to clear
    bool? allowClosedOverride, // optional if TS supports it here too
  }) async {
    final payload = <String, dynamic>{
      'clinicId': clinicId,
      'appointmentId': appointmentId,
    };

    // Keep consistent: send UTC ms.
    if (start != null) {
      payload['startMs'] = start.toUtc().millisecondsSinceEpoch;
    }
    if (end != null) payload['endMs'] = end.toUtc().millisecondsSinceEpoch;

    if (kind != null) payload['kind'] = kind;
    if (serviceId != null) payload['serviceId'] = serviceId;

    if (practitionerId != null) {
      final pid = practitionerId.trim();
      if (pid.isNotEmpty) payload['practitionerId'] = pid;
    }

    // When locationId is provided (including null), send it so backend can update or clear
    if (locationId != null) {
      payload['locationId'] = locationId.trim().isEmpty ? null : locationId.trim();
    } else {
      payload['locationId'] = null;
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
  // Cancel appointment (status-based; slot freed via trigger)
  // ---------------------------------------------------------------------------
  Future<void> cancelAppointment({
    required String clinicId,
    required String appointmentId,
    String? reason,
  }) async {
    await _call<void>('cancelAppointmentFn', {
      'clinicId': clinicId,
      'appointmentId': appointmentId,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
  }

  // ---------------------------------------------------------------------------
  // Delete appointment (hard delete; prefer cancelAppointment for lifecycle)
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
