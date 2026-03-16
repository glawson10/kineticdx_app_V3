class CalendarDisplaySettings {
  final int displayStartHour;
  final int displayEndHour;
  final int slotMinutes;
  final double slotHeightPx;
  final int timePickerIncrement;
  final bool showCurrentTimeIndicator;
  final bool hidePatientNames;
  final bool confirmMove;
  final bool showFinancialIndicators;
  final bool showWaitlistMatches;
  final bool smartOneDayView;
  final String defaultView;
  final String weekStartsOn;
  final bool showWeekends;
  final bool showClosedDayLabel;
  final bool condensedHeader;
  final bool clientNameSeparateLine;

  const CalendarDisplaySettings({
    this.displayStartHour = 7,
    this.displayEndHour = 20,
    this.slotMinutes = 15,
    this.slotHeightPx = 48.0,
    this.timePickerIncrement = 5,
    this.showCurrentTimeIndicator = true,
    this.hidePatientNames = false,
    this.confirmMove = true,
    this.showFinancialIndicators = false,
    this.showWaitlistMatches = true,
    this.smartOneDayView = false,
    this.defaultView = 'week',
    this.weekStartsOn = 'monday',
    this.showWeekends = true,
    this.showClosedDayLabel = true,
    this.condensedHeader = false,
    this.clientNameSeparateLine = false,
  });

  static const defaults = CalendarDisplaySettings();

  int get minutesPerBlock => slotMinutes;
  int get timePickerIncrementMinutes => timePickerIncrement;

  factory CalendarDisplaySettings.fromMap(Map<String, dynamic> data) {
    return CalendarDisplaySettings(
      displayStartHour: (data['displayStartHour'] as num?)?.toInt() ?? 7,
      displayEndHour: (data['displayEndHour'] as num?)?.toInt() ?? 20,
      slotMinutes: (data['slotMinutes'] as num?)?.toInt() ?? 15,
      slotHeightPx: (data['slotHeightPx'] as num?)?.toDouble() ?? 48.0,
      timePickerIncrement: (data['timePickerIncrement'] as num?)?.toInt() ?? 5,
      showCurrentTimeIndicator: data['showCurrentTimeIndicator'] as bool? ?? true,
      hidePatientNames: data['hidePatientNames'] as bool? ?? false,
      confirmMove: data['confirmMove'] as bool? ?? true,
      showFinancialIndicators: data['showFinancialIndicators'] as bool? ?? false,
      showWaitlistMatches: data['showWaitlistMatches'] as bool? ?? true,
      smartOneDayView: data['smartOneDayView'] as bool? ?? false,
      defaultView: (data['defaultView'] as String?) ?? 'week',
      weekStartsOn: (data['weekStartsOn'] as String?) ?? 'monday',
      showWeekends: data['showWeekends'] as bool? ?? true,
      showClosedDayLabel: data['showClosedDayLabel'] as bool? ?? true,
      condensedHeader: data['condensedHeader'] as bool? ?? false,
      clientNameSeparateLine: data['clientNameSeparateLine'] as bool? ?? false,
    );
  }

  bool get confirmAppointmentMoves => confirmMove;
  bool get showWaitlistMatchesOnCancel => showWaitlistMatches;

  CalendarDisplaySettings copyWith({
    int? displayStartHour,
    int? displayEndHour,
    int? slotMinutes,
    int? minutesPerBlock,
    double? slotHeightPx,
    int? timePickerIncrement,
    int? timePickerIncrementMinutes,
    bool? showCurrentTimeIndicator,
    bool? hidePatientNames,
    bool? confirmMove,
    bool? confirmAppointmentMoves,
    bool? showFinancialIndicators,
    bool? showWaitlistMatches,
    bool? showWaitlistMatchesOnCancel,
    bool? smartOneDayView,
    String? defaultView,
    String? weekStartsOn,
    bool? showWeekends,
    bool? showClosedDayLabel,
    bool? condensedHeader,
    bool? clientNameSeparateLine,
  }) {
    return CalendarDisplaySettings(
      displayStartHour: displayStartHour ?? this.displayStartHour,
      displayEndHour: displayEndHour ?? this.displayEndHour,
      slotMinutes: minutesPerBlock ?? slotMinutes ?? this.slotMinutes,
      slotHeightPx: slotHeightPx ?? this.slotHeightPx,
      timePickerIncrement: timePickerIncrementMinutes ?? timePickerIncrement ?? this.timePickerIncrement,
      showCurrentTimeIndicator: showCurrentTimeIndicator ?? this.showCurrentTimeIndicator,
      hidePatientNames: hidePatientNames ?? this.hidePatientNames,
      confirmMove: confirmMove ?? this.confirmMove,
      showFinancialIndicators: showFinancialIndicators ?? this.showFinancialIndicators,
      showWaitlistMatches: showWaitlistMatchesOnCancel ?? showWaitlistMatches ?? this.showWaitlistMatches,
      smartOneDayView: smartOneDayView ?? this.smartOneDayView,
      defaultView: defaultView ?? this.defaultView,
      weekStartsOn: weekStartsOn ?? this.weekStartsOn,
      showWeekends: showWeekends ?? this.showWeekends,
      showClosedDayLabel: showClosedDayLabel ?? this.showClosedDayLabel,
      condensedHeader: condensedHeader ?? this.condensedHeader,
      clientNameSeparateLine: clientNameSeparateLine ?? this.clientNameSeparateLine,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'displayStartHour': displayStartHour,
      'displayEndHour': displayEndHour,
      'slotMinutes': slotMinutes,
      'slotHeightPx': slotHeightPx,
      'timePickerIncrement': timePickerIncrement,
      'showCurrentTimeIndicator': showCurrentTimeIndicator,
      'hidePatientNames': hidePatientNames,
      'confirmMove': confirmMove,
      'showFinancialIndicators': showFinancialIndicators,
      'showWaitlistMatches': showWaitlistMatches,
      'smartOneDayView': smartOneDayView,
      'defaultView': defaultView,
      'weekStartsOn': weekStartsOn,
      'showWeekends': showWeekends,
      'showClosedDayLabel': showClosedDayLabel,
      'condensedHeader': condensedHeader,
      'clientNameSeparateLine': clientNameSeparateLine,
    };
  }

  /// Patch payload for the update callable. Uses canonical field names only (e.g. slotMinutes, not minutesPerBlock).
  Map<String, dynamic> toPatchMap() {
    return toMap();
  }
}
