import 'package:flutter/material.dart';

class StaffProfileOnboardingScreen extends StatelessWidget {
  const StaffProfileOnboardingScreen({super.key, this.clinicId});

  final String? clinicId;

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Staff profile onboarding — coming soon')),
    );
  }
}
