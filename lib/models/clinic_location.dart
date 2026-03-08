class ClinicLocation {
  final String id;
  final String name;
  final String addressText;
  final bool showInOnlineBooking;
  final bool active;

  const ClinicLocation({
    required this.id,
    required this.name,
    required this.addressText,
    required this.showInOnlineBooking,
    required this.active,
  });

  factory ClinicLocation.fromDoc(String id, Map<String, dynamic> data) {
    return ClinicLocation(
      id: id,
      name: (data['name'] as String?) ?? '',
      addressText: (data['addressText'] as String?) ?? '',
      showInOnlineBooking: data['showInOnlineBooking'] as bool? ?? true,
      active: data['active'] as bool? ?? true,
    );
  }
}
