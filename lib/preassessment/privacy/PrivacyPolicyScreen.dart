import 'package:flutter/material.dart';

/// V3 Privacy Policy screen (V2 UI style, V3 legal/architecture logic)
/// - Clinic-scoped controller
/// - Kinetic Dx as processor/tech provider
/// - Applies only to Phase 3 pre-assessment tool
/// - Automated decision-support disclosed (non-diagnostic)
///
/// Based on the existing V2 screen structure/helpers. :contentReference[oaicite:2]{index=2}
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({
    super.key,
    required this.clinicId,
    required this.clinicName,
    this.clinicContactEmail,
    this.clinicContactPhone,
    this.kineticPrivacyEmail = 'admin@kineticdx.com',
    this.lastUpdated = '4 January 2026',
  });

  /// Clinic tenant context (required in V3: everything is clinic-scoped).
  final String clinicId;
  final String clinicName;

  /// Optional clinic contact details (nice to show if you have them).
  final String? clinicContactEmail;
  final String? clinicContactPhone;

  /// Platform privacy contact (processor).
  final String kineticPrivacyEmail;

  /// Update when published.
  final String lastUpdated;

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(top: 16.0, bottom: 6.0),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  Widget _para(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12.0),
        child: Text(
          text,
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
      );

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('•  ', style: TextStyle(fontSize: 14, height: 1.5)),
            Expanded(
              child: Text(text, style: const TextStyle(fontSize: 14, height: 1.5)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final controllerContact = <String>[
      if ((clinicContactEmail ?? '').trim().isNotEmpty) 'Email: $clinicContactEmail',
      if ((clinicContactPhone ?? '').trim().isNotEmpty) 'Phone: $clinicContactPhone',
    ].join('\n');

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$clinicName – Pre-assessment Privacy Policy',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Clinic ID: $clinicId',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
              const SizedBox(height: 2),
              Text(
                'Last updated: $lastUpdated',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
              const Divider(height: 24),

              // 1. Intro (scope limited to preassessment)
              _sectionTitle('1. Introduction'),
              _para(
                'This Privacy Policy explains how personal and health information collected through the '
                'pre-assessment questionnaire is collected, used, stored, and protected.',
              ),
              _para(
                'This policy applies only to the pre-assessment tool and related assessment-preparation features. '
                'It does not replace privacy notices provided by your clinic for clinical care or other services.',
              ),

              // 2. Roles (clinic controller, platform processor)
              _sectionTitle('2. Who Is Responsible for Your Data'),
              _para(
                'In this pre-assessment workflow, your clinic is responsible for your clinical care and for deciding '
                'how your information is used. Kinetic Dx provides the secure technology used to collect and process '
                'the pre-assessment data on behalf of your clinic.',
              ),
              _bullet('Data Controller: $clinicName (Clinic ID: $clinicId)'),
              _bullet('Technology Provider / Data Processor: Kinetic Dx'),
              _bullet('Processor contact (privacy): $kineticPrivacyEmail'),
              if (controllerContact.isNotEmpty) ...[
                const SizedBox(height: 6),
                _para('Clinic contact:\n$controllerContact'),
              ],

              // 3. What we collect (preassessment-specific)
              _sectionTitle('3. What Information We Collect'),
              _para('Through the pre-assessment questionnaire, we may collect:'),
              _bullet('Identity/contact details (if provided): name, email, phone.'),
              _bullet(
                'Health information (special category): symptoms, pain levels, functional impact, relevant history, '
                'red/amber flag screening responses, and goals.',
              ),
              _bullet('Technical information: device/OS, basic diagnostics logs (e.g. crash reports).'),
              _para(
                'We do not sell your information and we do not use your health information for advertising.',
              ),

              // 4. How we use it (Phase 3 + clinician prep + safety)
              _sectionTitle('4. How We Use Your Information'),
              _para('Your clinic and authorised staff may use your pre-assessment information to:'),
              _bullet('Prepare for your appointment and understand your reported symptoms.'),
              _bullet('Identify safety concerns and appropriate triage level.'),
              _bullet('Maintain an assessment record and audit trail where required.'),
              _para(
                'This pre-assessment is not a substitute for a clinical assessment, does not provide a diagnosis, '
                'and does not produce a treatment plan.',
              ),

              // 5. Automated decision-support (Layer B safe)
              _sectionTitle('5. Automated Processing / Decision Support'),
              _para(
                'Some information may be processed using automated systems to organise responses and support clinician '
                'assessment planning.',
              ),
              _bullet('These systems do not provide medical advice or a diagnosis.'),
              _bullet('They do not replace professional clinical judgement.'),
              _bullet('Any outputs are clinician-facing and interpreted by a qualified clinician.'),
              _para(
                'Automated processing is used solely to support assessment preparation and safe clinical workflow.',
              ),

              // 6. Legal basis (GDPR-friendly, but clinic-scoped)
              _sectionTitle('6. Legal Basis for Processing'),
              _para(
                'Your clinic processes your health information to support healthcare delivery and safe assessment, '
                'and may rely on consent and/or other lawful bases permitted under applicable privacy law '
                '(including UK/EU GDPR where applicable).',
              ),
              _para(
                'If you wish to withdraw consent or exercise your rights, contact your clinic using the details above. '
                'Your clinic will advise what can be withdrawn and what must be retained under healthcare record obligations.',
              ),

              // 7. Storage & security (keep general unless you want exact regions)
              _sectionTitle('7. Storage, Security, and Access'),
              _para(
                'Pre-assessment information is stored securely and access is restricted to authorised clinic staff '
                'and approved technical service providers under contractual confidentiality and data protection obligations.',
              ),
              _bullet('Encryption in transit and at rest (industry standard).'),
              _bullet('Role-based access controls (clinic membership and permissions).'),
              _bullet('Auditability for security-relevant actions.'),
              _para(
                'Because the platform is clinic-scoped, your information is stored and accessed within the context of '
                'your clinic (Clinic ID: $clinicId).',
              ),

              // 8. Sharing
              _sectionTitle('8. Data Sharing'),
              _para('Your information may be shared only with:'),
              _bullet('Your treating clinician / authorised clinic staff.'),
              _bullet('Approved service providers who support the secure operation of the platform (as processors).'),
              _bullet('Regulators or law enforcement where legally required.'),
              _para('Your information is not shared with third parties for marketing purposes.'),

              // 9. Retention (clinic-led)
              _sectionTitle('9. Data Retention'),
              _para(
                'Your clinic determines retention periods in line with healthcare record-keeping requirements and '
                'local regulations. Pre-assessment records may be retained for the period required by law or clinic policy.',
              ),

              // 10. Rights
              _sectionTitle('10. Your Rights'),
              _para('Depending on your jurisdiction, you may have rights including:'),
              _bullet('Access – request a copy of your information.'),
              _bullet('Rectification – correct inaccurate information.'),
              _bullet('Erasure – request deletion where applicable.'),
              _bullet('Restriction/objection – limit or object to certain processing.'),
              _bullet('Portability – request a portable copy where applicable.'),
              _para(
                'To exercise these rights, contact $clinicName. If your request relates to platform processing, '
                'your clinic may coordinate with Kinetic Dx as needed.',
              ),

              // 11. Not for emergencies
              _sectionTitle('11. Not for Emergencies'),
              _para(
                'The pre-assessment tool is not monitored in real time. If you believe you are experiencing a medical emergency, '
                'contact emergency services or attend your nearest emergency department.',
              ),

              // 12. Changes
              _sectionTitle('12. Changes to This Policy'),
              _para(
                'This policy may be updated from time to time. The latest version will be available within the pre-assessment '
                'experience and will show an updated “Last updated” date.',
              ),

              // 13. Contacts
              _sectionTitle('13. Contact Details'),
              _para(
                '$clinicName (Data Controller)\n'
                'Clinic ID: $clinicId\n'
                '${controllerContact.isEmpty ? 'Contact: Please contact your clinic directly.' : controllerContact}\n\n'
                'Kinetic Dx (Technology Provider / Data Processor)\n'
                'Privacy contact: $kineticPrivacyEmail',
              ),

              const SizedBox(height: 12),
              Text(
                'Note: This policy is designed for the pre-assessment tool only. '
                'Clinically binding diagnosis and treatment decisions are made by a qualified clinician.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
