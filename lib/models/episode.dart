class Episode {
  final String id;
  final String status; // open | closed
  final String title;
  final String? primaryComplaint;
  final String? onsetDate; // YYYY-MM-DD for now
  final String? referralSource;
  final String? assignedPractitionerId;
  final List<String> tags;

  Episode({
    required this.id,
    required this.status,
    required this.title,
    this.primaryComplaint,
    this.onsetDate,
    this.referralSource,
    this.assignedPractitionerId,
    required this.tags,
  });

  factory Episode.fromFirestore(String id, Map<String, dynamic> data) {
    return Episode(
      id: id,
      status: (data['status'] ?? 'open').toString(),
      title: (data['title'] ?? '').toString(),
      primaryComplaint: data['primaryComplaint'] as String?,
      onsetDate: data['onsetDate'] as String?,
      referralSource: data['referralSource'] as String?,
      assignedPractitionerId: data['assignedPractitionerId'] as String?,
      tags: (data['tags'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
    );
  }
}
