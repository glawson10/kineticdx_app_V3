class Service {
  final String id;
  final String name;
  final String description;
  final int defaultMinutes;
  final bool active;

  Service({
    required this.id,
    required this.name,
    required this.description,
    required this.defaultMinutes,
    required this.active,
  });

  factory Service.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return Service(
      id: id,
      name: (data['name'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      defaultMinutes: (data['defaultMinutes'] as num?)?.toInt() ?? 0,
      active: (data['active'] ?? false) == true,
    );
  }
}
