import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PractitionerVisibilityPrefs {
  final List<String> visiblePractitionerIds;
  final List<String> orderPractitionerIds;

  const PractitionerVisibilityPrefs({
    this.visiblePractitionerIds = const [],
    this.orderPractitionerIds = const [],
  });

  Map<String, dynamic> toJson() => {
    'visiblePractitionerIds': visiblePractitionerIds,
    'orderPractitionerIds': orderPractitionerIds,
  };

  factory PractitionerVisibilityPrefs.fromJson(Map<String, dynamic> json) {
    return PractitionerVisibilityPrefs(
      visiblePractitionerIds: List<String>.from((json['visiblePractitionerIds'] as List?)?.cast<String>() ?? []),
      orderPractitionerIds: List<String>.from((json['orderPractitionerIds'] as List?)?.cast<String>() ?? []),
    );
  }
}

const _keyRailCollapsed = 'booking_rail_collapsed';
const _keyMiniCalExpanded = 'booking_mini_cal_expanded';
const _keyPractPrefs = 'booking_practitioner_prefs';

Future<bool> loadBookingRailCollapsed() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_keyRailCollapsed) ?? false;
}

Future<void> saveBookingRailCollapsed(bool collapsed) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_keyRailCollapsed, collapsed);
}

Future<bool> loadMiniCalendarExpanded() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_keyMiniCalExpanded) ?? true;
}

Future<void> saveMiniCalendarExpanded(bool expanded) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_keyMiniCalExpanded, expanded);
}

Future<PractitionerVisibilityPrefs> loadPractitionerVisibilityPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_keyPractPrefs);
  if (raw == null) return const PractitionerVisibilityPrefs();
  try {
    return PractitionerVisibilityPrefs.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
  } catch (_) {
    return const PractitionerVisibilityPrefs();
  }
}

Future<void> savePractitionerVisibilityPrefs(PractitionerVisibilityPrefs p) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_keyPractPrefs, jsonEncode(p.toJson()));
}
