// lib/models/appointment_type.dart
//
// Appointment type model. Matches backend: clinics/{clinicId}/appointmentTypes.
// Used in settings list/form, clinic calendar picker, public booking, and price list.

class AppointmentType {
  final String id;
  final String name;
  final int durationMinutes;
  final String? colorHex;
  final bool active;
  final bool showInOnlineBooking;
  final String? description;
  final double? defaultPrice;
  final List<String> allowedLocationIds;
  final bool telehealth;
  final List<String> allowedPractitionerIds;

  const AppointmentType({
    required this.id,
    required this.name,
    required this.durationMinutes,
    this.colorHex,
    required this.active,
    required this.showInOnlineBooking,
    this.description,
    this.defaultPrice,
    this.allowedLocationIds = const [],
    this.telehealth = false,
    this.allowedPractitionerIds = const [],
  });

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  factory AppointmentType.fromFirestore(String id, Map<String, dynamic> data) {
    final allowedRaw = data['allowedLocationIds'];
    final List<String> allowed = _stringList(allowedRaw);

    final allowedPractRaw = data['allowedPractitionerIds'];
    final List<String> allowedPract = _stringList(allowedPractRaw);

    double? defaultPrice;
    final dp = data['defaultPrice'];
    if (dp != null) {
      if (dp is num) {
        defaultPrice = dp.toDouble();
      } else {
        final p = double.tryParse(dp.toString());
        if (p != null && p >= 0) defaultPrice = p;
      }
    }

    return AppointmentType(
      id: id,
      name: (data['name'] as String?) ?? '',
      durationMinutes: (data['durationMinutes'] as num?)?.toInt() ?? 30,
      colorHex: (data['colorHex'] as String?)?.trim().isNotEmpty == true
          ? (data['colorHex'] as String).trim()
          : null,
      active: data['active'] as bool? ?? true,
      showInOnlineBooking: data['showInOnlineBooking'] as bool? ?? false,
      description: (data['description'] as String?)?.trim().isNotEmpty == true
          ? (data['description'] as String).trim()
          : null,
      defaultPrice: defaultPrice,
      allowedLocationIds: allowed,
      telehealth: data['telehealth'] as bool? ?? false,
      allowedPractitionerIds: allowedPract,
    );
  }
}
