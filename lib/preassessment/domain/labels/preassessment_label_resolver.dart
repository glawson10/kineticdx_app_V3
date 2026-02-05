// lib/preassessment/domain/labels/preassessment_label_resolver.dart

import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/ankle/ankle_labels_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/cervical/cervical_labels_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/elbow/elbow_labels_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/hip/hip_labels_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/knee/knee_labels_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/lumbar/lumbar_labels_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/shoulder/shoulder_labels_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/thoracic/thoracic_labels_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/regions/wrist/wrist_labels_v1.dart';

/// Central label resolver for Phase 3 preassessment.
/// - Region-specific labels are chosen by flowId
/// - Shared/common labels live here (e.g. common.continue)
///
/// Later: swap this whole thing to proper i18n without changing flows/screens.
String resolvePreassessmentLabel(String flowId, String key) {
  // Shared labels used across screens/widgets
  const shared = <String, String>{
    'common.continue': 'Continue',
    'common.back': 'Back',
    'common.submit': 'Submit',
    'common.review': 'Review',

    // Common validation keys we’ve seen leak into the UI
    'preassessment.validation.fixErrors':
        'Please answer the highlighted questions.',
    'preassessment.validation.required': 'This question is optional.',
    'preassessment.validation.selectOne': 'Please select one option.',
    'preassessment.validation.selectAtLeastOne':
        'Please select at least one option.',
  };

  // Try shared first
  final sharedHit = shared[key];
  if (sharedHit != null) return sharedHit;

  // Region labels map
  final regionMap = _regionLabelsFor(flowId);
  final regionHit = regionMap[key];
  if (regionHit != null) return regionHit;

  // Fallback: if some option keys are shared across regions (time.*, mechanism.* etc),
  // try to resolve them from a small shared-options dictionary.
  final sharedOptionHit = _sharedOptions[key];
  if (sharedOptionHit != null) return sharedOptionHit;

  // Final fallback: show key (better than blank)
  return key;
}

Map<String, String> _regionLabelsFor(String flowId) {
  switch (flowId) {
    case 'ankle':
      return ankleLabelsV1;
    case 'knee':
      return kneeLabelsV1;
    case 'hip':
      return hipLabelsV1;
    case 'lumbar':
      return lumbarLabelsV1;
    case 'cervical':
      return cervicalLabelsV1;
    case 'thoracic':
      return thoracicLabelsV1;
    case 'shoulder':
      return shoulderLabelsV1;
    case 'elbow':
      return elbowLabelsV1;
    case 'wrist':
      return wristLabelsV1;
    default:
      return const <String, String>{};
  }
}

/// Shared option labels used in multiple regions.
/// Keep this small; region maps can also define these, but this catches gaps.
const Map<String, String> _sharedOptions = {
  // Generic time buckets (commonly reused)
  'time.lt48h': 'Less than 48 hours',
  'time.2to7d': '2–7 days',
  'time.2_14d': '2–14 days',
  'time.1to4w': '1–4 weeks',
  'time.1to6w': '1–6 weeks',
  'time.2_6wk': '2–6 weeks',
  'time.6wto3m': '6 weeks – 3 months',
  'time.1to3m': '1–3 months',
  'time.gt3m': 'More than 3 months',
  'time.gt6wk': 'More than 6 weeks',
  'time.unsure': 'Not sure',

  // Generic mechanism buckets
  'mechanism.fall': 'Fall or impact',
  'mechanism.twist': 'Twist / awkward movement',
  'mechanism.directBlow': 'Direct blow / collision',
  'mechanism.overuse': 'Overuse / repetitive activity',
  'mechanism.repetitiveLoad': 'Repetitive use / overload',
  'mechanism.suddenForce': 'Sudden force (lift/pull/push)',
  'mechanism.gradual': 'Gradual onset / unsure',

  // Generic function impact buckets
  'impact.none': 'None',
  'impact.some': 'Some',
  'impact.major': 'Major',

  // Generic walking labels
  'walk.normal': 'Normal',
  'walk.limited': 'Limited',
  'walk.unable': 'Unable',

  // Common yes/no style option keys (if used)
  'yes': 'Yes',
  'no': 'No',
};
