// lib/models/location_display_settings.dart
// clinics/{clinicId}/settings/locationDisplay: order + defaultLocationId.

class LocationDisplaySettings {
  const LocationDisplaySettings({
    this.locationIds = const [],
    this.defaultLocationId,
  });

  final List<String> locationIds;
  final String? defaultLocationId;

  factory LocationDisplaySettings.fromDoc(Map<String, dynamic>? data) {
    if (data == null) return const LocationDisplaySettings();
    final ids = data['locationIds'];
    final list = ids is List
        ? (ids)
            .map((e) => e?.toString().trim())
            .where((s) => s != null && s.isNotEmpty)
            .cast<String>()
            .toList()
        : <String>[];
    final def = data['defaultLocationId']?.toString().trim();
    return LocationDisplaySettings(
      locationIds: list,
      defaultLocationId: def != null && def.isNotEmpty ? def : null,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'locationIds': locationIds,
        if (defaultLocationId != null && defaultLocationId!.isNotEmpty)
          'defaultLocationId': defaultLocationId,
      };
}
