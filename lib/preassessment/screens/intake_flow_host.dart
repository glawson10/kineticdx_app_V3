// lib/preassessment/screens/intake_flow_host.dart
//
// PA-P3.1: Route graph is registry-driven. Fixed entries: /consent, /patient-details.
// Post–patient-details routes and their screen keys come from flow_registry;
// no hardcoded route path list in the host.

import 'package:flutter/material.dart';

import '../domain/flow_registry.dart';
import '../flows/consent/consent_screen.dart';
import '../flows/patient_details/patient_details_screen.dart';
import '../flows/region_select/region_select_screen.dart';
import '../flows/general_visit/general_visit_start_screen.dart';

class IntakeFlowHost extends StatelessWidget {
  const IntakeFlowHost({
    super.key,
    this.flowArgs,
  });

  /// Optional arguments to pass through the entire intake flow.
  final Map<String, dynamic>? flowArgs;

  static final GlobalKey<NavigatorState> navKey =
      GlobalKey<NavigatorState>(debugLabel: 'IntakeFlowHostNav');

  static Map<String, WidgetBuilder> _buildRouteBuilders() {
    final map = <String, WidgetBuilder>{};
    final consentBuilder = (BuildContext ctx) => const ConsentScreen();
    map['/consent'] = consentBuilder;
    map['/patient-details'] = (BuildContext ctx) => const PatientDetailsScreen();

    final screenKeyToBuilder = <String, WidgetBuilder>{
      'region_select': (BuildContext ctx) => const RegionSelectScreen(),
      'general_visit_start': (BuildContext ctx) => const GeneralVisitStartScreen(),
    };
    for (final routeName in getPostPatientDetailsRouteNames()) {
      final screenKey = getScreenKeyForPostDetailsRoute(routeName);
      if (screenKey != null && screenKeyToBuilder.containsKey(screenKey)) {
        map[routeName] = screenKeyToBuilder[screenKey]!;
      }
    }
    return map;
  }

  static final Map<String, WidgetBuilder> _routeBuilders = _buildRouteBuilders();

  Route<dynamic> _route(WidgetBuilder builder, RouteSettings settings) {
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
    final consentBuilder = _routeBuilders['/consent']!;
    return Navigator(
      key: navKey,
      initialRoute: '/consent',
      onGenerateRoute: (settings) {
        final name = settings.name;
        final builder = name != null ? _routeBuilders[name] : null;
        if (builder != null) return _route(builder, settings);
        return _route(consentBuilder, settings);
      },
    );
  }
}
