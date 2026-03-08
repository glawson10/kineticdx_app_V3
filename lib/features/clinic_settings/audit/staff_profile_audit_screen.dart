// lib/features/clinic_settings/audit/staff_profile_audit_screen.dart
// Staff profile and availability change audit (stub).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/clinic_context.dart';

class StaffProfileAuditScreen extends StatelessWidget {
  const StaffProfileAuditScreen({super.key});

  static Route<void> route() => MaterialPageRoute(
        builder: (_) => const StaffProfileAuditScreen(),
      );

  @override
  Widget build(BuildContext context) {
    final clinicId = context.watch<ClinicContext>().clinicId;
    return Scaffold(
      appBar: AppBar(title: const Text('Staff profile audit')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Staff profile audit for clinic $clinicId.\nPlaceholder screen.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
