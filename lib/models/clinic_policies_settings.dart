// lib/models/clinic_policies_settings.dart
//
// Practice policies: optional text for cancellation, late arrival, no-show,
// and consent/policy bundle. Stored at clinics/{clinicId}/settings/policies.

class ClinicPoliciesSettings {
  const ClinicPoliciesSettings({
    this.cancellationPolicyText = '',
    this.lateArrivalPolicyText = '',
    this.noShowPolicyText = '',
    this.policyBundleId = 'default',
    this.policyBundleVersion = 1,
  });

  final String cancellationPolicyText;
  final String lateArrivalPolicyText;
  final String noShowPolicyText;
  final String policyBundleId;
  final int policyBundleVersion;

  factory ClinicPoliciesSettings.fromDoc(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return const ClinicPoliciesSettings();
    return ClinicPoliciesSettings(
      cancellationPolicyText:
          (data['cancellationPolicyText'] as String?)?.trim() ?? '',
      lateArrivalPolicyText:
          (data['lateArrivalPolicyText'] as String?)?.trim() ?? '',
      noShowPolicyText: (data['noShowPolicyText'] as String?)?.trim() ?? '',
      policyBundleId: (data['policyBundleId'] as String?)?.trim() ?? 'default',
      policyBundleVersion:
          (data['policyBundleVersion'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'cancellationPolicyText': cancellationPolicyText.trim(),
      'lateArrivalPolicyText': lateArrivalPolicyText.trim(),
      'noShowPolicyText': noShowPolicyText.trim(),
      'policyBundleId': policyBundleId.trim().isEmpty ? 'default' : policyBundleId.trim(),
      'policyBundleVersion': policyBundleVersion,
    };
  }
}
