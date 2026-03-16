import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import '../../models/calendar_display_settings.dart';

class CalendarDisplaySettingsRepository {
  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'europe-west3');

  final Map<String, StreamController<CalendarDisplaySettings>> _controllers = {};
  final Map<String, CalendarDisplaySettings> _cache = {};

  Stream<CalendarDisplaySettings> streamSettings(String clinicId) {
    final c = clinicId.trim();
    if (c.isEmpty) return Stream.value(CalendarDisplaySettings.defaults);

    if (!_controllers.containsKey(c) || _controllers[c]!.isClosed) {
      _controllers[c] = StreamController<CalendarDisplaySettings>.broadcast();
      _fetchAndEmit(c);
    }
    
    final cached = _cache[c];
    if (cached != null) {
      return Stream.value(cached).followedBy(_controllers[c]!.stream);
    }
    return _controllers[c]!.stream;
  }

  Future<CalendarDisplaySettings> getSettings(String clinicId) async {
    final c = clinicId.trim();
    final cached = _cache[c];
    if (cached != null) return cached;

    final fn = _functions.httpsCallable('settingsGetCalendarDisplayConfig');
    final result = await fn.call({'clinicId': c});
    final data = Map<String, dynamic>.from(result.data as Map? ?? {});
    final settings = CalendarDisplaySettings.fromMap(data);
    _cache[c] = settings;
    return settings;
  }

  void clearDisplaySettingsCache() {
    _cache.clear();
    for (final ctrl in _controllers.values) {
      if (!ctrl.isClosed) ctrl.close();
    }
    _controllers.clear();
  }

  Future<void> updateSettings(String clinicId, Map<String, dynamic> data) async {
    final fn = _functions.httpsCallable('settingsUpdateCalendarDisplayConfig');
    await fn.call({'clinicId': clinicId, 'patch': data});
    _cache.remove(clinicId.trim());
    _fetchAndEmit(clinicId.trim());
  }

  Future<void> _fetchAndEmit(String clinicId) async {
    try {
      final settings = await getSettings(clinicId);
      final ctrl = _controllers[clinicId];
      if (ctrl != null && !ctrl.isClosed) {
        ctrl.add(settings);
      }
    } catch (_) {
      final ctrl = _controllers[clinicId];
      if (ctrl != null && !ctrl.isClosed) {
        ctrl.add(CalendarDisplaySettings.defaults);
      }
    }
  }
}

extension _StreamFollowedBy<T> on Stream<T> {
  Stream<T> followedBy(Stream<T> other) async* {
    yield* this;
    yield* other;
  }
}
