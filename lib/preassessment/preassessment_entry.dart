// lib/preassessment/preassessment_entry.dart
import 'package:flutter/material.dart';

import 'screens/intake_start_screen.dart';

class PreassessmentEntry extends StatelessWidget {
  const PreassessmentEntry({
    super.key,
    required this.clinicId,
  });

  final String clinicId;

  @override
  Widget build(BuildContext context) {
    // ✅ Option A: in-app entry passes clinicId directly
    return IntakeStartScreen(
      clinicIdOverride: clinicId,
      // Optional: easiest dev path while wiring UI:
      devBypassOverride: true,
    );
  }
}
