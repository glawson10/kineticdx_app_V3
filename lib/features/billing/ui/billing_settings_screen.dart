// lib/features/billing/ui/billing_settings_screen.dart
// Invoice settings, supplier profile, payment methods (stub).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/clinic_context.dart';

class BillingSettingsScreen extends StatelessWidget {
  const BillingSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final clinicId = context.watch<ClinicContext>().clinicId;
    return Scaffold(
      appBar: AppBar(title: const Text('Billing settings')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Billing settings for clinic $clinicId.\nPlaceholder screen.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
