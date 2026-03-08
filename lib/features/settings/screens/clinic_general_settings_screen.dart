import 'package:flutter/material.dart';

import '../widgets/clinic_general_settings_form.dart';

/// Settings → Clinic → General: clinic profile, branding, contact, public links, locale.
/// Reuses [ClinicGeneralSettingsForm]; backend persists to profile.* and runs public mirror.
class ClinicGeneralSettingsScreen extends StatelessWidget {
  const ClinicGeneralSettingsScreen({super.key, required this.clinicId});
  final String clinicId;

  @override
  Widget build(BuildContext context) {
    return ClinicGeneralSettingsForm(
      clinicId: clinicId,
      showSaveButton: true,
    );
  }
}
