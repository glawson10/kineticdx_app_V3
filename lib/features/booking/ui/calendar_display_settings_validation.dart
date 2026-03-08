String? validateDisplayStartHour(String? value) {
  final v = int.tryParse(value ?? '');
  if (v == null) return 'Enter a number';
  if (v < 0 || v > 23) return 'Must be 0–23';
  return null;
}

String? validateDisplayEndHour(String? value, [int startHour = 0]) {
  final v = int.tryParse(value ?? '');
  if (v == null) return 'Enter a number';
  if (v < 1 || v > 24) return 'Must be 1–24';
  if (v <= startHour) return 'Must be after start hour ($startHour)';
  return null;
}

String? validateMinutesPerBlock(String? value) {
  final v = int.tryParse(value ?? '');
  if (v == null) return 'Enter a number';
  if (v < 5 || v > 60) return 'Must be 5–60';
  return null;
}

String? validateSlotHeightPx(String? value) {
  final v = double.tryParse(value ?? '');
  if (v == null) return 'Enter a number';
  if (v < 16 || v > 96) return 'Must be 16–96';
  return null;
}

String? validateTimePickerIncrement(String? value) {
  final v = int.tryParse(value ?? '');
  if (v == null) return 'Enter a number';
  if (v < 1 || v > 60) return 'Must be 1–60';
  return null;
}
