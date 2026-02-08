// lib/models/clinic_public_profile.dart
//
// Pre-auth branding doc: clinics/{clinicId}/public/profile
// Read-only; used for clinic-specific login portals.

class ClinicPublicProfile {
  final String displayName;
  final String? logoUrl;
  final String? supportEmail;

  const ClinicPublicProfile({
    required this.displayName,
    this.logoUrl,
    this.supportEmail,
  });

  factory ClinicPublicProfile.fromMap(Map<String, dynamic>? data) {
    if (data == null) {
      return const ClinicPublicProfile(displayName: 'KineticDx');
    }
    final name = (data['displayName'] as String?)?.trim();
    return ClinicPublicProfile(
      displayName: name != null && name.isNotEmpty ? name : 'KineticDx',
      logoUrl: (data['logoUrl'] as String?)?.trim().isNotEmpty == true
          ? (data['logoUrl'] as String).trim()
          : null,
      supportEmail: (data['supportEmail'] as String?)?.trim().isNotEmpty == true
          ? (data['supportEmail'] as String).trim()
          : null,
    );
  }
}
