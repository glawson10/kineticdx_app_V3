/// Booking-authority metadata stored on `clinics/{clinicId}/practitioners/{uid}`.
///
/// This is the single source of truth for whether a clinician can be booked,
/// where they can be booked, and for which services.
class PractitionerBookingMeta {
  final String uid;
  final String displayName;
  final bool active;
  final bool activeForBooking;
  final bool showInPublicBooking;
  final int publicSortOrder;
  final List<String> allowedLocationIds;
  final List<String> serviceIdsAllowed;

  const PractitionerBookingMeta({
    required this.uid,
    this.displayName = '',
    this.active = true,
    this.activeForBooking = true,
    this.showInPublicBooking = false,
    this.publicSortOrder = 0,
    this.allowedLocationIds = const [],
    this.serviceIdsAllowed = const [],
  });

  factory PractitionerBookingMeta.fromMap(String uid, Map<String, dynamic> data) {
    return PractitionerBookingMeta(
      uid: uid,
      displayName: (data['displayName'] ?? '').toString().trim(),
      active: data['active'] != false,
      activeForBooking: data['activeForBooking'] != false,
      showInPublicBooking: data['showInPublicBooking'] == true,
      publicSortOrder: _safeInt(data['sortOrder'] ?? data['publicSortOrder'], 0),
      allowedLocationIds: _safeStringList(data['allowedLocationIds']),
      serviceIdsAllowed: _safeStringList(data['serviceIdsAllowed']),
    );
  }

  /// Whether this practitioner can offer the given service (empty = all allowed).
  bool allowsService(String serviceId) {
    if (serviceIdsAllowed.isEmpty) return true;
    return serviceIdsAllowed.contains(serviceId);
  }

  /// Whether this practitioner can work at the given location (empty = all allowed).
  bool allowsLocation(String? locationId) {
    if (allowedLocationIds.isEmpty) return true;
    if (locationId == null || locationId.isEmpty) return true;
    return allowedLocationIds.contains(locationId);
  }

  /// Whether this practitioner is eligible for a given combination.
  bool isEligibleFor({String? serviceId, String? locationId}) {
    if (!active || !activeForBooking) return false;
    if (serviceId != null && serviceId.isNotEmpty && !allowsService(serviceId)) return false;
    if (!allowsLocation(locationId)) return false;
    return true;
  }

  Map<String, dynamic> toMap() => {
        'displayName': displayName,
        'active': active,
        'activeForBooking': activeForBooking,
        'showInPublicBooking': showInPublicBooking,
        'sortOrder': publicSortOrder,
        'allowedLocationIds': allowedLocationIds,
        'serviceIdsAllowed': serviceIdsAllowed,
      };

  static int _safeInt(dynamic v, int fallback) {
    if (v is int) return v;
    if (v is double) return v.round();
    final n = int.tryParse(v?.toString() ?? '');
    return n ?? fallback;
  }

  static List<String> _safeStringList(dynamic v) {
    if (v is! List) return const [];
    return v
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList()
        .cast<String>();
  }
}
