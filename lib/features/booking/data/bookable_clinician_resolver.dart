/// Shared clinician-eligibility resolver for internal booking surfaces.
///
/// Joins clinic memberships with practitioner booking metadata to produce
/// one canonical list of bookable clinicians. All internal booking surfaces
/// (calendar header dropdown, rail tools, appointment form) consume this
/// instead of duplicating their own membership + meta join logic.
///
/// Matches the server-side checks in `createAppointmentInternal.ts`:
///   - active membership (not suspended / invited)
///   - if practitioner meta exists: active, activeForBooking, allowedLocationIds, serviceIdsAllowed
///   - if no practitioner meta: schedule permission grants implicit eligibility
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../data/repositories/staff_repository.dart';
import '../../../models/practitioner_booking_meta.dart';

/// Resolved clinician with eligibility status for the current booking context.
class ResolvedClinician {
  final String uid;
  final String displayName;

  /// True when the clinician should appear in internal calendar filters
  /// regardless of the currently selected location or appointment type.
  final bool visibleForInternalCalendar;

  /// True when the clinician is eligible for the specific (locationId, serviceId) combination.
  final bool eligibleForSelection;

  /// Human-readable reason when not eligible (for UX hints).
  final String? exclusionReason;

  /// Underlying booking metadata (null if no practitioner doc exists).
  final PractitionerBookingMeta? meta;

  const ResolvedClinician({
    required this.uid,
    required this.displayName,
    required this.visibleForInternalCalendar,
    required this.eligibleForSelection,
    this.exclusionReason,
    this.meta,
  });
}

/// Result from the resolver: two lists derived from the same source data.
class ResolvedClinicianList {
  /// All clinicians visible on internal calendar surfaces.
  final List<ResolvedClinician> all;

  /// Clinicians eligible for the current (locationId, serviceId) selection.
  final List<ResolvedClinician> eligible;

  /// Whether the eligible list was downgraded to the full visible list
  /// because no clinician matched the selection.
  final bool isFallback;

  const ResolvedClinicianList({
    required this.all,
    required this.eligible,
    required this.isFallback,
  });

  /// The list to show in a booking context. Uses [eligible] when non-empty,
  /// otherwise falls back to [all].
  List<ResolvedClinician> get effectiveBookingList =>
      eligible.isNotEmpty ? eligible : all;
}

// ---------------------------------------------------------------------------
// Pure resolution logic (no Firestore dependency, testable)
// ---------------------------------------------------------------------------

/// Resolve clinician eligibility from raw membership docs and booking metadata.
///
/// This is the single source of truth for internal booking clinician visibility.
/// It mirrors the server-side checks in createAppointmentInternal:
///   1. Membership must be active-like (not suspended, not invited).
///   2. If a practitioners/{uid} doc exists:
///      - active must not be false
///      - activeForBooking must not be false
///      - serviceIdsAllowed must include serviceId (if non-empty)
///      - allowedLocationIds must include locationId (if non-empty)
///   3. If no practitioners/{uid} doc exists:
///      - schedule.read or schedule.write permission grants implicit eligibility.
ResolvedClinicianList resolveBookableClinicians({
  required List<MemberDocSnapshot> members,
  required Map<String, Map<String, dynamic>> metaById,
  String? serviceId,
  String? locationId,
}) {
  final all = <ResolvedClinician>[];
  final eligible = <ResolvedClinician>[];
  final seen = <String>{};

  for (final member in members) {
    if (!seen.add(member.id)) continue;
    final data = member.data();

    if (!_isActiveMembership(data)) continue;

    final metaData = metaById[member.id];
    final hasScheduleAccess = _hasScheduleAccess(data);

    if (metaData != null) {
      final meta = PractitionerBookingMeta.fromMap(member.id, metaData);
      final label = _displayLabel(data, metaData);

      final canShow = hasScheduleAccess || meta.activeForBooking;
      if (!canShow) continue;

      final isEligible = meta.isEligibleFor(
        serviceId: serviceId,
        locationId: locationId,
      );

      String? reason;
      if (!isEligible) {
        if (!meta.active) {
          reason = 'Practitioner is inactive.';
        } else if (!meta.activeForBooking) {
          reason = 'Not active for internal booking.';
        } else if (serviceId != null &&
            serviceId.isNotEmpty &&
            !meta.allowsService(serviceId)) {
          reason = 'Not allowed for this appointment type.';
        } else if (!meta.allowsLocation(locationId)) {
          reason = 'Not allowed at this location.';
        }
      }

      final resolved = ResolvedClinician(
        uid: member.id,
        displayName: label,
        visibleForInternalCalendar: true,
        eligibleForSelection: isEligible,
        exclusionReason: reason,
        meta: meta,
      );

      all.add(resolved);
      if (isEligible) eligible.add(resolved);
    } else {
      if (!hasScheduleAccess) continue;

      final label = _displayLabel(data, null);
      final resolved = ResolvedClinician(
        uid: member.id,
        displayName: label,
        visibleForInternalCalendar: true,
        eligibleForSelection: true,
        meta: null,
      );

      all.add(resolved);
      eligible.add(resolved);
    }
  }

  all.sort(_compareByName);
  eligible.sort(_compareByName);

  return ResolvedClinicianList(
    all: all,
    eligible: eligible,
    isFallback: eligible.isEmpty && all.isNotEmpty,
  );
}

// ---------------------------------------------------------------------------
// Stream-based resolver that widgets can use via StreamBuilder
// ---------------------------------------------------------------------------

/// Watches memberships and practitioner metadata and emits a resolved list
/// whenever either source changes.
Stream<ResolvedClinicianList> watchBookableClinicians({
  required StaffRepository staffRepo,
  required String clinicId,
  String? serviceId,
  String? locationId,
}) {
  final c = clinicId.trim();
  if (c.isEmpty) return const Stream.empty();

  debugPrint('[watchBookableClinicians] clinicId=$c serviceId=$serviceId locationId=$locationId');

  return RxCombineLatest2<
    List<MemberDocSnapshot>,
    List<QueryDocumentSnapshot<Map<String, dynamic>>>,
    ResolvedClinicianList
  >(
    staffRepo.watchMembershipsWithFallback(c),
    staffRepo.watchPractitionerBookingMetas(c),
    (members, metas) {
      final metaById = <String, Map<String, dynamic>>{};
      for (final m in metas) {
        metaById[m.id] = m.data();
      }
      final result = resolveBookableClinicians(
        members: members,
        metaById: metaById,
        serviceId: serviceId,
        locationId: locationId,
      );

      debugPrint(
        '[watchBookableClinicians] members=${members.length} metas=${metas.length} '
        '→ all=${result.all.length} eligible=${result.eligible.length} fallback=${result.isFallback}',
      );
      for (final rc in result.all) {
        debugPrint('  [clinician] ${rc.uid}: "${rc.displayName}" eligible=${rc.eligibleForSelection} hasMeta=${rc.meta != null}');
      }

      return result;
    },
  );
}

// ---------------------------------------------------------------------------
// Private helpers — match server-side createAppointmentInternal checks
// ---------------------------------------------------------------------------

bool _isActiveMembership(Map<String, dynamic> data) {
  final status = (data['status'] ?? '').toString().trim().toLowerCase();
  if (status == 'suspended') return false;
  if (status == 'invited') return false;
  final active = data['active'];
  if (active is bool) return active;
  return true;
}

bool _hasScheduleAccess(Map<String, dynamic> data) {
  final permsRaw = data['permissions'];
  if (permsRaw is! Map) return false;
  final perms = Map<String, dynamic>.from(permsRaw);
  final write = perms['schedule.write'];
  final read = perms['schedule.read'];
  return write == true ||
      read == true ||
      write?.toString() == 'true' ||
      read?.toString() == 'true';
}

String _displayLabel(
  Map<String, dynamic> memberData,
  Map<String, dynamic>? metaData,
) {
  final metaName = (metaData?['displayName'] ?? '').toString().trim();
  if (metaName.isNotEmpty) return metaName;
  final name = (memberData['displayName'] ?? '').toString().trim();
  if (name.isNotEmpty) return name;
  final email = (memberData['invitedEmail'] ?? memberData['email'] ?? '')
      .toString()
      .trim();
  if (email.isNotEmpty) return email;
  return 'Member';
}

int _compareByName(ResolvedClinician a, ResolvedClinician b) =>
    a.displayName.compareTo(b.displayName);
