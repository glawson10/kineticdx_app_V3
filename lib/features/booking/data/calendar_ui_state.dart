// lib/features/booking/data/calendar_ui_state.dart
//
// Unified calendar UI state for the booking calendar screen.
// Persisted via booking_calendar_prefs where applicable.

/// Semantic density for the week grid; maps to slot height internally.
enum CalendarDensityMode {
  compact,
  comfortable,
  spacious,
}

extension CalendarDensityModeExtension on CalendarDensityMode {
  int get index {
    switch (this) {
      case CalendarDensityMode.compact:
        return 0;
      case CalendarDensityMode.comfortable:
        return 1;
      case CalendarDensityMode.spacious:
        return 2;
    }
  }

  static CalendarDensityMode fromIndex(int i) {
    switch (i.clamp(0, 2)) {
      case 0:
        return CalendarDensityMode.compact;
      case 1:
        return CalendarDensityMode.comfortable;
      case 2:
        return CalendarDensityMode.spacious;
      default:
        return CalendarDensityMode.comfortable;
    }
  }

  /// Slot height in logical pixels when not using "fit to viewport".
  double get slotHeightPx {
    switch (this) {
      case CalendarDensityMode.compact:
        return 38.0;
      case CalendarDensityMode.comfortable:
        return 48.0;
      case CalendarDensityMode.spacious:
        return 60.0;
    }
  }
}

/// Active section in the calendar tools panel.
enum CalendarToolsSection {
  overview,
  dateNavigator,
  clinicians,
  waitlist,
}

extension CalendarToolsSectionExtension on CalendarToolsSection {
  String get value {
    switch (this) {
      case CalendarToolsSection.overview:
        return 'overview';
      case CalendarToolsSection.dateNavigator:
        return 'dateNavigator';
      case CalendarToolsSection.clinicians:
        return 'clinicians';
      case CalendarToolsSection.waitlist:
        return 'waitlist';
    }
  }

  static CalendarToolsSection fromValue(String v) {
    switch (v) {
      case 'dateNavigator':
        return CalendarToolsSection.dateNavigator;
      case 'clinicians':
        return CalendarToolsSection.clinicians;
      case 'waitlist':
        return CalendarToolsSection.waitlist;
      default:
        return CalendarToolsSection.overview;
    }
  }
}

/// Holds all calendar UI state used by the booking calendar screen.
/// The screen owns an instance and calls setState when updating.
class CalendarUIState {
  final int currentViewMode; // 1, 3, 7, 30
  final String? selectedPractitionerId; // null = all
  final List<String> selectedClinicianIds; // for filter; empty = all
  final bool showCancelled;
  final bool showAdminBlocks;
  final bool showClosedShading;
  final CalendarDensityMode densityMode;
  final bool showWeekend;
  final bool showToolsPanel;
  final CalendarToolsSection activeToolsSection;
  final bool enableKeyboardShortcuts;
  final bool showShortcutHints;
  final bool enableHoverQuickActions;
  final bool fitWeek; // fullscreen / fit to viewport

  const CalendarUIState({
    this.currentViewMode = 7,
    this.selectedPractitionerId,
    this.selectedClinicianIds = const [],
    this.showCancelled = true,
    this.showAdminBlocks = true,
    this.showClosedShading = true,
    this.densityMode = CalendarDensityMode.comfortable,
    this.showWeekend = true,
    this.showToolsPanel = false,
    this.activeToolsSection = CalendarToolsSection.overview,
    this.enableKeyboardShortcuts = true,
    this.showShortcutHints = false,
    this.enableHoverQuickActions = true,
    this.fitWeek = false,
  });

  CalendarUIState copyWith({
    int? currentViewMode,
    String? selectedPractitionerId,
    List<String>? selectedClinicianIds,
    bool? showCancelled,
    bool? showAdminBlocks,
    bool? showClosedShading,
    CalendarDensityMode? densityMode,
    bool? showWeekend,
    bool? showToolsPanel,
    CalendarToolsSection? activeToolsSection,
    bool? enableKeyboardShortcuts,
    bool? showShortcutHints,
    bool? enableHoverQuickActions,
    bool? fitWeek,
  }) {
    return CalendarUIState(
      currentViewMode: currentViewMode ?? this.currentViewMode,
      selectedPractitionerId: selectedPractitionerId ?? this.selectedPractitionerId,
      selectedClinicianIds: selectedClinicianIds ?? this.selectedClinicianIds,
      showCancelled: showCancelled ?? this.showCancelled,
      showAdminBlocks: showAdminBlocks ?? this.showAdminBlocks,
      showClosedShading: showClosedShading ?? this.showClosedShading,
      densityMode: densityMode ?? this.densityMode,
      showWeekend: showWeekend ?? this.showWeekend,
      showToolsPanel: showToolsPanel ?? this.showToolsPanel,
      activeToolsSection: activeToolsSection ?? this.activeToolsSection,
      enableKeyboardShortcuts: enableKeyboardShortcuts ?? this.enableKeyboardShortcuts,
      showShortcutHints: showShortcutHints ?? this.showShortcutHints,
      enableHoverQuickActions: enableHoverQuickActions ?? this.enableHoverQuickActions,
      fitWeek: fitWeek ?? this.fitWeek,
    );
  }
}
