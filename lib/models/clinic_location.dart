/// Same shape as clinic weekly hours: day key -> list of { start: "HH:mm", end: "HH:mm" }.
typedef LocationWeeklyHours = Map<String, List<Map<String, String>>>;

class ClinicLocation {
  final String id;
  final String name;
  final String addressText;
  final bool showInOnlineBooking;
  final bool active;
  /// Location-specific opening hours. Empty or null = no extra restriction (clinic hours apply).
  final LocationWeeklyHours? weeklyHours;
  final String? colorHex;
  final String? phone;
  final String? notes;

  const ClinicLocation({
    required this.id,
    required this.name,
    required this.addressText,
    required this.showInOnlineBooking,
    required this.active,
    this.weeklyHours,
    this.colorHex,
    this.phone,
    this.notes,
  });

  factory ClinicLocation.fromDoc(String id, Map<String, dynamic> data) {
    LocationWeeklyHours? weeklyHours;
    final wh = data['weeklyHours'];
    if (wh is Map) {
      final map = <String, List<Map<String, String>>>{};
      for (final entry in (wh as Map).entries) {
        final key = entry.key.toString();
        final val = entry.value;
        if (val is List) {
          map[key] = val
              .whereType<Map>()
              .map((m) => {
                    'start': (m['start'] ?? '').toString(),
                    'end': (m['end'] ?? '').toString(),
                  })
              .where((m) => m['start']!.isNotEmpty && m['end']!.isNotEmpty)
              .toList();
        } else {
          map[key] = [];
        }
      }
      final hasAny = map.values.any((list) => list.isNotEmpty);
      weeklyHours = hasAny ? map : null;
    }
    final colorHexRaw = data['colorHex'];
    final colorHex = colorHexRaw is String && colorHexRaw.trim().isNotEmpty
        ? colorHexRaw.trim()
        : null;
    final phoneRaw = data['phone'];
    final phone = phoneRaw is String && phoneRaw.trim().isNotEmpty
        ? phoneRaw.trim()
        : null;
    final notesRaw = data['notes'];
    final notes = notesRaw is String && notesRaw.trim().isNotEmpty
        ? notesRaw.trim()
        : null;

    return ClinicLocation(
      id: id,
      name: (data['name'] as String?) ?? '',
      addressText: (data['addressText'] as String?) ?? '',
      showInOnlineBooking: data['showInOnlineBooking'] as bool? ?? true,
      active: data['active'] as bool? ?? true,
      weeklyHours: weeklyHours,
      colorHex: colorHex,
      phone: phone,
      notes: notes,
    );
  }
}
