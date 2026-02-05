// lib/preassessment/screens/intake_flow_host.dart
//
// ✅ Updated in full:
// - Keeps nested Navigator + argument pass-through
// - Adds /general-visit-start route
// - Does NOT depend on IntakeDraftController.flowIdOverride
// - PatientDetailsScreen handles branching to either:
//    /region-select  OR  /general-visit-start
//
// IMPORTANT:
// - Ensure PatientDetailsScreen uses pushReplacementNamed('/general-visit-start')
//   when flowId == 'generalVisit' (your updated version already does).
// - Create the GeneralVisitStartScreen file (or swap to your real screen).

import 'package:flutter/material.dart';

import '../flows/consent/consent_screen.dart';
import '../flows/patient_details/patient_details_screen.dart';
import '../flows/region_select/region_select_screen.dart';

// ✅ Add this screen (create file or wire to your real general visit first screen)
import '../flows/general_visit/general_visit_start_screen.dart';

class IntakeFlowHost extends StatelessWidget {
  const IntakeFlowHost({
    super.key,
    this.flowArgs,
  });

  /// Optional arguments to pass through the entire intake flow.
  /// Example:
  /// {
  ///   'clinicId': '...',
  ///   'bookingRequestId': '...',
  ///   'prefillPatient': {...},
  ///   'flowIdOverride': 'generalVisit'
  /// }
  final Map<String, dynamic>? flowArgs;

  static final GlobalKey<NavigatorState> navKey =
      GlobalKey<NavigatorState>(debugLabel: 'IntakeFlowHostNav');

  Route<dynamic> _route(WidgetBuilder builder, RouteSettings settings) {
    // ✅ Always carry arguments forward
    final merged = <String, dynamic>{};

    final fromSettings = settings.arguments;
    if (fromSettings is Map) {
      merged.addAll(Map<String, dynamic>.from(fromSettings));
    } else if (flowArgs != null) {
      merged.addAll(flowArgs!);
    }

    return MaterialPageRoute(
      settings: RouteSettings(
        name: settings.name,
        arguments: merged.isEmpty ? null : merged,
      ),
      builder: builder,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navKey,
      initialRoute: '/consent',
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/consent':
            return _route((ctx) => const ConsentScreen(), settings);

          case '/patient-details':
            return _route((ctx) => const PatientDetailsScreen(), settings);

          case '/region-select':
            return _route((ctx) => const RegionSelectScreen(), settings);

          case '/general-visit-start':
            return _route((ctx) => const GeneralVisitStartScreen(), settings);

          default:
            return _route((ctx) => const ConsentScreen(), settings);
        }
      },
    );
  }
}
