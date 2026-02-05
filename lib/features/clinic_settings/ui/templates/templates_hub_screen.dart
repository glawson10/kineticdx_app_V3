import 'package:flutter/material.dart';

import 'clinical_tests_settings_screen.dart';
import 'outcome_measures_settings_screen.dart';

class TemplatesHubScreen extends StatelessWidget {
  final String clinicId;

  const TemplatesHubScreen({
    super.key,
    required this.clinicId,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Templates'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Objective Tests'),
              Tab(text: 'Outcome Measures'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ClinicalTestsSettingsScreen(clinicId: clinicId),
            OutcomeMeasuresSettingsScreen(clinicId: clinicId),
          ],
        ),
      ),
    );
  }
}