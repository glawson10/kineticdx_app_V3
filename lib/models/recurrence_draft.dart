// lib/models/recurrence_draft.dart
// Draft recurrence for series (e.g. weekly count).

class RecurrenceDraft {
  const RecurrenceDraft({
    required this.freq,
    required this.interval,
    required this.byWeekday,
    required this.count,
  });

  final String? freq; // e.g. 'WEEKLY'
  final int interval;
  final List<String> byWeekday; // e.g. ['MO','WE','FR']
  final int count;

  /// No recurrence / one-off.
  static const RecurrenceDraft none = RecurrenceDraft(
    freq: null,
    interval: 0,
    byWeekday: [],
    count: 0,
  );

  bool get isNone => freq == null && count == 0;

  /// Default weekday list from [day]: that weekday only.
  static List<String> defaultByWeekdayFrom(DateTime day) {
    const weekdays = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
    final wd = day.weekday - 1; // DateTime.weekday 1=Mon
    return [weekdays[wd]];
  }

  Map<String, dynamic> toJson() => {
        if (freq != null) 'freq': freq,
        'interval': interval,
        if (byWeekday.isNotEmpty) 'byWeekday': byWeekday,
        if (count > 0) 'count': count,
      };
}
