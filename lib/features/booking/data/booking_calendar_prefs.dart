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

// Calendar UI state (local-only; TODO: optional backend sync later)
const _keyShowToolsPanelByDefault = 'calendar_show_tools_panel_by_default';
const _keyLastViewMode = 'calendar_last_view_mode';
const _keyDensityMode = 'calendar_density_mode';
const _keyEnableKeyboardShortcuts = 'calendar_enable_keyboard_shortcuts';
const _keyShowShortcutHints = 'calendar_show_shortcut_hints';
const _keyEnableHoverQuickActions = 'calendar_enable_hover_quick_actions';
const _keyHideCancelledByDefault = 'calendar_hide_cancelled_by_default';
const _keyShowAdminBlocks = 'calendar_show_admin_blocks';
const _keyShowClosedShading = 'calendar_show_closed_shading';
const _keyShowWeekend = 'calendar_show_weekend';
const _keyActiveToolsSection = 'calendar_active_tools_section';
const _keyRememberLastView = 'calendar_remember_last_view';
const _keyStartOnCurrentDay = 'calendar_start_on_current_day';

Future<bool> loadBookingRailCollapsed() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_keyRailCollapsed) ?? true;
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

// ---------------------------------------------------------------------------
// Calendar UI prefs (local persistence)
// ---------------------------------------------------------------------------

Future<bool> loadShowToolsPanelByDefault() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_keyShowToolsPanelByDefault) ?? false;
}

Future<void> saveShowToolsPanelByDefault(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_keyShowToolsPanelByDefault, value);
}

Future<int> loadLastViewMode() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt(_keyLastViewMode) ?? 7;
}

Future<void> saveLastViewMode(int value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_keyLastViewMode, value);
}

/// Density: 0 = compact, 1 = comfortable, 2 = spacious
Future<int> loadDensityMode() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt(_keyDensityMode) ?? 1;
}

Future<void> saveDensityMode(int value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_keyDensityMode, value.clamp(0, 2));
}

Future<bool> loadEnableKeyboardShortcuts() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_keyEnableKeyboardShortcuts) ?? true;
}

Future<void> saveEnableKeyboardShortcuts(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_keyEnableKeyboardShortcuts, value);
}

Future<bool> loadShowShortcutHints() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_keyShowShortcutHints) ?? false;
}

Future<void> saveShowShortcutHints(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_keyShowShortcutHints, value);
}

Future<bool> loadEnableHoverQuickActions() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_keyEnableHoverQuickActions) ?? true;
}

Future<void> saveEnableHoverQuickActions(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_keyEnableHoverQuickActions, value);
}

Future<bool> loadHideCancelledByDefault() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_keyHideCancelledByDefault) ?? false;
}

Future<void> saveHideCancelledByDefault(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_keyHideCancelledByDefault, value);
}

Future<bool> loadShowAdminBlocks() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_keyShowAdminBlocks) ?? true;
}

Future<void> saveShowAdminBlocks(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_keyShowAdminBlocks, value);
}

Future<bool> loadShowClosedShading() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_keyShowClosedShading) ?? true;
}

Future<void> saveShowClosedShading(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_keyShowClosedShading, value);
}

Future<bool> loadShowWeekend() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_keyShowWeekend) ?? true;
}

Future<void> saveShowWeekend(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_keyShowWeekend, value);
}

Future<String> loadActiveToolsSection() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_keyActiveToolsSection) ?? 'overview';
}

Future<void> saveActiveToolsSection(String value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_keyActiveToolsSection, value);
}

Future<bool> loadRememberLastView() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_keyRememberLastView) ?? true;
}

Future<void> saveRememberLastView(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_keyRememberLastView, value);
}

Future<bool> loadStartOnCurrentDay() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_keyStartOnCurrentDay) ?? true;
}

Future<void> saveStartOnCurrentDay(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_keyStartOnCurrentDay, value);
}
