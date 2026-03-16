import 'questionnaire_flow.dart';

// lib/models/public_booking_config_v1.dart
//
// Commit 17: Read-only mirror config from clinics/{clinicId}/public/config/publicBooking/config.
// Schema: docs/PUBLIC_BOOKING_PROJECTION_SCHEMA.md

/// One time interval in a day (HH:mm).
class WeeklyInterval {
  const WeeklyInterval({required this.start, required this.end});
  final String start;
  final String end;
}

/// Day keys for weekly hours (mon..sun).
const List<String> kWeeklyHoursDayKeys = [
  'mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun',
];

/// Valid slot step minutes for validation.
const List<int> kSlotStepOptions = [5, 10, 15, 20, 30];

/// Public booking config v1 (mirror doc). Used by availability engine and public booking only.
class PublicBookingConfigV1 {
  const PublicBookingConfigV1({
    required this.timezone,
    required this.slotStepMinutes,
    required this.minNoticeMinutes,
    required this.maxAdvanceDays,
    required this.allowNewPatients,
    required this.requireEmail,
    required this.requirePhone,
    required this.cancellationPolicyHours,
    required this.weeklyHours,
    required this.questionnaireFlow,
    this.onlineBookingEnabled = true,
    this.clinicId,
    this.schemaVersion,
  });

  final String timezone;
  final int slotStepMinutes;
  final int minNoticeMinutes;
  final int maxAdvanceDays;
  final bool allowNewPatients;
  final bool requireEmail;
  final bool requirePhone;
  final int cancellationPolicyHours;
  final bool onlineBookingEnabled;
  /// All 7 days always present: mon..sun -> list of {start, end}.
  final Map<String, List<WeeklyInterval>> weeklyHours;
  final QuestionnaireFlowPublicConfig questionnaireFlow;
  final String? clinicId;
  final int? schemaVersion;

  /// Defaults when doc missing or invalid (engine degrades gracefully).
  static PublicBookingConfigV1 get defaults => PublicBookingConfigV1(
        timezone: 'UTC',
        slotStepMinutes: 15,
        minNoticeMinutes: 0,
        maxAdvanceDays: 90,
        allowNewPatients: true,
        requireEmail: true,
        requirePhone: false,
        cancellationPolicyHours: 24,
        weeklyHours: _emptyWeeklyHours(),
        questionnaireFlow: const QuestionnaireFlowPublicConfig(),
        onlineBookingEnabled: true,
      );

  static Map<String, List<WeeklyInterval>> _emptyWeeklyHours() {
    return Map.fromEntries(
      kWeeklyHoursDayKeys.map((k) => MapEntry(k, <WeeklyInterval>[])),
    );
  }

  /// Parse from Firestore doc. Returns null if doc missing; uses safe defaults for missing/invalid fields.
  static PublicBookingConfigV1? fromDoc(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return null;

    final jurisdiction = data['jurisdiction'];
    final timezone = _str(
      jurisdiction is Map ? jurisdiction['timezone'] : null,
      'UTC',
    );

    final rules = data['bookingRules'];
    final r = rules is Map ? Map<String, dynamic>.from(rules) : <String, dynamic>{};

    final slotStep = _slotStepFrom(r['slotStepMinutes']);
    final minNotice = _int(r['minNoticeMinutes'], 0, 0, 168 * 60);
    final maxAdvance = _int(r['maxAdvanceDays'], 90, 7, 365);
    final allowNew = r['allowNewPatients'] == true || r['allowNewPatients'] != false;
    final requireEmailVal = r['requireEmail'] != false;
    final requirePhoneVal = r['requirePhone'] == true;
    final cancelHours = _int(r['cancellationPolicyHours'], 24, 0, 168 * 24);
    final questionnaireFlow =
        QuestionnaireFlowPublicConfig.fromJson(r['questionnaireFlow']);
    final onlineBookingEnabled = r['onlineBookingEnabled'] != false;

    final weeklyHours = _parseWeeklyHours(data['weeklyHours']);

    return PublicBookingConfigV1(
      timezone: timezone,
      slotStepMinutes: slotStep,
      minNoticeMinutes: minNotice,
      maxAdvanceDays: maxAdvance,
      allowNewPatients: allowNew,
      requireEmail: requireEmailVal,
      requirePhone: requirePhoneVal,
      cancellationPolicyHours: cancelHours,
      weeklyHours: weeklyHours,
      questionnaireFlow: questionnaireFlow,
      onlineBookingEnabled: onlineBookingEnabled,
      clinicId: data['clinicId'] is String ? data['clinicId'] as String : null,
      schemaVersion: data['schemaVersion'] is int ? data['schemaVersion'] as int : null,
    );
  }

  static int _slotStepFrom(dynamic v) {
    final n = _int(v, 15, 5, 30);
    if (kSlotStepOptions.contains(n)) return n;
    return 15;
  }

  static int _int(dynamic v, int fallback, int minVal, int maxVal) {
    if (v == null) return fallback;
    final n = v is int ? v : (v is num ? v.toInt() : int.tryParse(v.toString()));
    if (n == null) return fallback;
    if (n < minVal) return minVal;
    if (n > maxVal) return maxVal;
    return n;
  }

  static String _str(dynamic v, String fallback) {
    if (v == null) return fallback;
    final s = v.toString().trim();
    return s.isEmpty ? fallback : s;
  }

  static final RegExp _hhMm = RegExp(r'^\d{1,2}:\d{2}$');

  static Map<String, List<WeeklyInterval>> _parseWeeklyHours(dynamic raw) {
    final out = _emptyWeeklyHours();
    if (raw is! Map) return out;

    for (final day in kWeeklyHoursDayKeys) {
      final v = raw[day];
      if (v is! List) continue;
      final list = <WeeklyInterval>[];
      for (final item in v) {
        if (item is! Map) continue;
        final start = _str(item['start'], '');
        final end = _str(item['end'], '');
        if (start.isEmpty || end.isEmpty) continue;
        if (!_hhMm.hasMatch(start) || !_hhMm.hasMatch(end)) continue;
        list.add(WeeklyInterval(start: start, end: end));
      }
      out[day] = list;
    }
    return out;
  }
}
