class PublicBookingSettings {
  static const int maxAdvanceDaysMin = 1;
  static const int maxAdvanceDaysMax = 365;
  static const List<int> slotStepOptions = [5, 10, 15, 20, 30, 45, 60];

  final int slotStepMinutes;
  final int minNoticeMinutes;
  final int maxAdvanceDays;
  final bool requirePhone;
  final bool requireEmail;
  final bool allowNewPatients;
  final int cancellationPolicyHours;
  final Map<String, List<Map<String, dynamic>>> weeklyHours;

  const PublicBookingSettings({
    this.slotStepMinutes = 15,
    this.minNoticeMinutes = 60,
    this.maxAdvanceDays = 90,
    this.requirePhone = false,
    this.requireEmail = true,
    this.allowNewPatients = true,
    this.cancellationPolicyHours = 24,
    this.weeklyHours = const {},
  });

  factory PublicBookingSettings.fromDoc(Map<String, dynamic>? data) {
    if (data == null) return const PublicBookingSettings();
    return PublicBookingSettings(
      slotStepMinutes: (data['slotStepMinutes'] as num?)?.toInt() ?? 15,
      minNoticeMinutes: (data['minNoticeMinutes'] as num?)?.toInt() ?? 60,
      maxAdvanceDays: (data['maxAdvanceDays'] as num?)?.toInt() ?? 90,
      requirePhone: data['requirePhone'] as bool? ?? false,
      requireEmail: data['requireEmail'] as bool? ?? true,
      allowNewPatients: data['allowNewPatients'] as bool? ?? true,
      cancellationPolicyHours: (data['cancellationPolicyHours'] as num?)?.toInt() ?? 24,
      weeklyHours: _parseWeeklyHours(data['weeklyHours']),
    );
  }

  static Map<String, List<Map<String, dynamic>>> _parseWeeklyHours(dynamic raw) {
    if (raw == null || raw is! Map) return {};
    final out = <String, List<Map<String, dynamic>>>{};
    for (final entry in (raw as Map).entries) {
      final key = entry.key.toString();
      final val = entry.value;
      if (val is List) {
        out[key] = val
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
    return out;
  }

  Map<String, dynamic> toPatch() {
    return {
      'slotStepMinutes': slotStepMinutes,
      'minNoticeMinutes': minNoticeMinutes,
      'maxAdvanceDays': maxAdvanceDays,
      'requirePhone': requirePhone,
      'requireEmail': requireEmail,
      'allowNewPatients': allowNewPatients,
      'cancellationPolicyHours': cancellationPolicyHours,
      if (weeklyHours.isNotEmpty) 'weeklyHours': weeklyHours,
    };
  }
}
