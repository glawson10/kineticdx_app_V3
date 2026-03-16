// lib/preassessment/domain/flow_registry.dart
//
// PA-P3: Registry-driven intake dispatch.
// Flow definition lookup and firstScreenRoute by flowDefinitionId; legacy flowId shim.

import 'package:kineticdx_app_v3/preassessment/domain/flow_definition.dart';

import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/ankle/ankle_flow_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/cervical/cervical_flow_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/elbow/elbow_flow_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/hip/hip_flow_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/knee/knee_flow_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/lumbar/lumbar_flow_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/shoulder/shoulder_flow_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/thoracic/thoracic_flow_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/wrist/wrist_flow_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/general_visit/general_visit_flow_v1.dart';

/// Registry entry: flowDefinitionId -> flow + first screen route.
final Map<String, _FlowRegistryEntry> _flowDefinitionRegistry = <String, _FlowRegistryEntry>{
  'builtin.ankle.v1': _FlowRegistryEntry(ankleFlowV1, '/region-select'),
  'builtin.cervical.v1': _FlowRegistryEntry(cervicalFlowV1, '/region-select'),
  'builtin.elbow.v1': _FlowRegistryEntry(elbowFlowV1, '/region-select'),
  'builtin.hip.v1': _FlowRegistryEntry(hipFlowV1, '/region-select'),
  'builtin.knee.v1': _FlowRegistryEntry(kneeFlowV1, '/region-select'),
  'builtin.lumbar.v1': _FlowRegistryEntry(lumbarFlowV1, '/region-select'),
  'builtin.shoulder.v1': _FlowRegistryEntry(shoulderFlowV1, '/region-select'),
  'builtin.thoracic.v1': _FlowRegistryEntry(thoracicFlowV1, '/region-select'),
  'builtin.wrist.v1': _FlowRegistryEntry(wristFlowV1, '/region-select'),
  'builtin.generalVisit.v1': _FlowRegistryEntry(generalVisitFlowV1, '/general-visit-start'),
};

/// Legacy flowId -> flowDefinitionId (for sessions/drafts without registry ids).
final Map<String, String> _legacyFlowIdToDefinitionId = <String, String>{
  'ankle': 'builtin.ankle.v1',
  'cervical': 'builtin.cervical.v1',
  'elbow': 'builtin.elbow.v1',
  'hip': 'builtin.hip.v1',
  'knee': 'builtin.knee.v1',
  'lumbar': 'builtin.lumbar.v1',
  'shoulder': 'builtin.shoulder.v1',
  'thoracic': 'builtin.thoracic.v1',
  'wrist': 'builtin.wrist.v1',
  'generalvisit': 'builtin.generalVisit.v1',
  'general_visit': 'builtin.generalVisit.v1',
  'general-visit': 'builtin.generalVisit.v1',
};

class _FlowRegistryEntry {
  const _FlowRegistryEntry(this.flow, this.firstScreenRoute);
  final FlowDefinition flow;
  final String firstScreenRoute;
}

/// Resolve FlowDefinition by flowDefinitionId.
FlowDefinition? getFlowDefinitionByRegistryId(String flowDefinitionId) {
  final id = flowDefinitionId.trim();
  if (id.isEmpty) return null;
  return _flowDefinitionRegistry[id]?.flow;
}

/// Legacy shim: flowId (e.g. from meta.flowId or bodyArea) -> flowDefinitionId.
String? legacyFlowIdToFlowDefinitionId(String flowId) {
  final f = flowId.trim().toLowerCase();
  if (f.isEmpty) return null;
  return _legacyFlowIdToDefinitionId[f];
}

/// PA-P3.1: All intake host route names (fixed entry + registry-derived post–patient-details).
/// Use to build the route graph so the host does not hardcode a fixed switch list.
List<String> getAllIntakeHostRouteNames() {
  const fixed = ['/consent', '/patient-details'];
  final postDetails = _flowDefinitionRegistry.values
      .map((e) => e.firstScreenRoute)
      .toSet()
      .toList();
  return [...fixed, ...postDetails];
}

/// PA-P3.1: Returns the set of route names that follow patient-details (from flow definitions).
/// Deduplicated; e.g. ['/region-select', '/general-visit-start'].
List<String> getPostPatientDetailsRouteNames() {
  return _flowDefinitionRegistry.values
      .map((e) => e.firstScreenRoute)
      .toSet()
      .toList();
}

/// PA-P3.1: Screen key for a post–patient-details route (used by host to resolve widget without hardcoding route paths).
/// Returns null for unknown routes.
const Map<String, String> _postDetailsRouteToScreenKey = <String, String>{
  '/region-select': 'region_select',
  '/general-visit-start': 'general_visit_start',
};

String? getScreenKeyForPostDetailsRoute(String routeName) {
  final r = routeName.trim();
  return r.isEmpty ? null : _postDetailsRouteToScreenKey[r];
}

/// Get first screen route after patient-details (region-select vs general-visit-start).
/// Prefers flowDefinitionId; falls back to legacy flowId.
String getFirstScreenRoute({
  String? flowDefinitionId,
  String? legacyFlowId,
}) {
  if (flowDefinitionId != null && flowDefinitionId.trim().isNotEmpty) {
    final entry = _flowDefinitionRegistry[flowDefinitionId.trim()];
    if (entry != null) return entry.firstScreenRoute;
  }
  final definitionId = legacyFlowId != null
      ? legacyFlowIdToFlowDefinitionId(legacyFlowId)
      : null;
  if (definitionId != null) {
    final entry = _flowDefinitionRegistry[definitionId];
    if (entry != null) return entry.firstScreenRoute;
  }
  return '/region-select';
}

/// Resolve FlowDefinition for a draft/session: prefer flowDefinitionId, else legacy flowId/bodyArea.
FlowDefinition? resolveFlowFromRegistry({
  String? flowDefinitionId,
  String? legacyFlowId,
  String? bodyArea,
}) {
  if (flowDefinitionId != null && flowDefinitionId.trim().isNotEmpty) {
    final flow = getFlowDefinitionByRegistryId(flowDefinitionId.trim());
    if (flow != null) return flow;
  }
  final f = (legacyFlowId ?? bodyArea ?? '').trim().toLowerCase();
  if (f.isEmpty) return null;
  final normalized = f
      .replaceFirst('region.', '')
      .replaceAll(' ', '');
  final definitionId = _legacyFlowIdToDefinitionId[normalized] ??
      _legacyFlowIdToDefinitionId[normalized.toLowerCase()];
  if (definitionId != null) {
    return getFlowDefinitionByRegistryId(definitionId);
  }
  return null;
}
