// lib/models/service.dart
// Appointment type model. Contract: BOOKING_DATA_CONTRACT.md §8.

class Service {
  final String id;
  final String name;
  final String description;
  final int defaultMinutes;
  final bool active;

  /// BOOKING_DATA_CONTRACT: colorHex. Drives calendar block colour. Optional until backend/settings add it.
  final String? colorHex;

  /// BOOKING_DATA_CONTRACT: telehealth. Optional until backend/settings add it.
  final bool telehealth;

  /// BOOKING_DATA_CONTRACT: allowedPractitionerIds. Empty = all allowed. Optional until backend/settings add it.
  final List<String> allowedPractitionerIds;

  Service({
    required this.id,
    required this.name,
    required this.description,
    required this.defaultMinutes,
    required this.active,
    this.colorHex,
    this.telehealth = false,
    this.allowedPractitionerIds = const [],
  });

  factory Service.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    final allowedRaw = data['allowedPractitionerIds'];
    final List<String> allowed = allowedRaw is List
        ? allowedRaw
            .whereType<String>()
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList()
        : const [];

    return Service(
      id: id,
      name: (data['name'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      defaultMinutes: (data['defaultMinutes'] as num?)?.toInt() ?? 0,
      active: (data['active'] ?? false) == true,
      colorHex: (data['colorHex'] as String?)?.trim().isNotEmpty == true
          ? (data['colorHex'] as String).trim()
          : null,
      telehealth: (data['telehealth'] == true),
      allowedPractitionerIds: allowed,
    );
  }
}
