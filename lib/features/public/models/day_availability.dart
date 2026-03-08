class DayAvailability {
  const DayAvailability({
    required this.count,
    this.corporateOnly = false,
  });

  final int count;
  final bool corporateOnly;

  bool get hasAvailability => count > 0;
}
