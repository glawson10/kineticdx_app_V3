import 'package:kineticdx_app_v3/preassessment/domain/flow_definition.dart';

/// ---------------------------------------------------------------------------
/// WRIST v1 — TS-aligned question set
/// Authoritative scorer: functions/src/wrist/processWristAssessment.ts
///
/// Legacy IDs expected by TS:
/// Q1_system (multi), Q2_injury (single yes/no), Q3_injury_cluster (multi),
/// Q4_zone (single), Q5_onset (single), Q6a_mech (multi),
/// Q6b_aggs (multi), Q7_features (multi), Q8_weightbear (single),
/// Q10_risks (multi), Q_side (single)
/// ---------------------------------------------------------------------------

final List<QuestionDef> wristQuestionsV1 = [
  // -------------------------------------------------------------------------
  // RED FLAGS / SAFETY — ASK FIRST (triage uses Q1_system + injury cluster)
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'wrist.redflags.systemic',
    valueType: QuestionValueType.multiChoice,
    promptKey: 'wrist.redflags.systemic',
    required: false, // allow empty (no flags)
    contributesToTriage: true,
    options: const [
      OptionDef(id: 'system.fever', labelKey: 'system.fever'),
      OptionDef(id: 'system.wtloss', labelKey: 'system.wtloss'),
      OptionDef(id: 'system.both_hands_tingles', labelKey: 'system.both_hands_tingles'),
      OptionDef(id: 'system.extreme_colour_temp', labelKey: 'system.extreme_colour_temp'),
      OptionDef(id: 'system.constant_night', labelKey: 'system.constant_night'),
    ],
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'wrist.redflags.acuteInjury',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'wrist.redflags.acuteInjury',
    required: true,
    contributesToTriage: true,
    options: const [
      OptionDef(id: 'injury.yes', labelKey: 'injury.yes'),
      OptionDef(id: 'injury.no', labelKey: 'injury.no'),
    ],
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'wrist.redflags.injuryCluster',
    valueType: QuestionValueType.multiChoice,
    promptKey: 'wrist.redflags.injuryCluster',
    required: false,
    contributesToTriage: true,
    options: const [
      OptionDef(id: 'inj.no_weight_bear', labelKey: 'inj.no_weight_bear'),
      OptionDef(id: 'inj.pop_crack', labelKey: 'inj.pop_crack'),
      OptionDef(id: 'inj.deformity', labelKey: 'inj.deformity'),
      OptionDef(id: 'inj.severe_pain', labelKey: 'inj.severe_pain'),
      OptionDef(id: 'inj.immediate_numb', labelKey: 'inj.immediate_numb'),
    ],
    /// NOTE: DynamicFlowScreen already supports required/validation.
    /// Injury cluster is only meaningful when acuteInjury == yes.
    /// We keep required=false and enforce conditional logic in adapter (safe).
    domain: 'redflags',
  ),

  // -------------------------------------------------------------------------
  // CONTEXT
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'wrist.context.side',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'wrist.context.side',
    required: true,
    options: const [
      OptionDef(id: 'side.left', labelKey: 'side.left'),
      OptionDef(id: 'side.right', labelKey: 'side.right'),
      OptionDef(id: 'side.both', labelKey: 'side.both'),
      OptionDef(id: 'side.unsure', labelKey: 'side.unsure'),
    ],
    domain: 'context',
  ),

  // -------------------------------------------------------------------------
  // PAIN LOCATION (zone) — drives key differentials
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'wrist.symptoms.zone',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'wrist.symptoms.zone',
    required: true,
    options: const [
      OptionDef(id: 'zone.radial', labelKey: 'zone.radial'),
      OptionDef(id: 'zone.ulnar', labelKey: 'zone.ulnar'),
      OptionDef(id: 'zone.dorsal', labelKey: 'zone.dorsal'),
      OptionDef(id: 'zone.volar', labelKey: 'zone.volar'),
      OptionDef(id: 'zone.diffuse', labelKey: 'zone.diffuse'),
    ],
    domain: 'symptoms',
  ),

  // -------------------------------------------------------------------------
  // HISTORY
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'wrist.history.onset',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'wrist.history.onset',
    required: true,
    options: const [
      OptionDef(id: 'onset.sudden', labelKey: 'onset.sudden'),
      OptionDef(id: 'onset.gradual', labelKey: 'onset.gradual'),
      OptionDef(id: 'onset.unsure', labelKey: 'onset.unsure'),
    ],
    domain: 'history',
  ),

  QuestionDef(
    questionId: 'wrist.history.mechanism',
    valueType: QuestionValueType.multiChoice,
    promptKey: 'wrist.history.mechanism',
    required: false,
    options: const [
      OptionDef(id: 'mech.foosh', labelKey: 'mech.foosh'),
      OptionDef(id: 'mech.twist', labelKey: 'mech.twist'),
      OptionDef(id: 'mech.typing', labelKey: 'mech.typing'),
      OptionDef(id: 'mech.grip_lift', labelKey: 'mech.grip_lift'),
    ],
    domain: 'history',
  ),

  // -------------------------------------------------------------------------
  // AGGRAVATORS — drives multiple differentials
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'wrist.symptoms.aggravators',
    valueType: QuestionValueType.multiChoice,
    promptKey: 'wrist.symptoms.aggravators',
    required: false,
    options: const [
      OptionDef(id: 'aggs.typing', labelKey: 'aggs.typing'),
      OptionDef(id: 'aggs.grip_lift', labelKey: 'aggs.grip_lift'),
      OptionDef(id: 'aggs.weight_bear', labelKey: 'aggs.weight_bear'),
      OptionDef(id: 'aggs.twist', labelKey: 'aggs.twist'),
    ],
    domain: 'symptoms',
  ),

  // -------------------------------------------------------------------------
  // FEATURES — symptom features + neuro/vascular marker used by TS
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'wrist.symptoms.features',
    valueType: QuestionValueType.multiChoice,
    promptKey: 'wrist.symptoms.features',
    required: false,
    options: const [
      OptionDef(id: 'feat.swelling', labelKey: 'feat.swelling'),
      OptionDef(id: 'feat.bump_shape', labelKey: 'feat.bump_shape'),
      OptionDef(id: 'feat.clicking', labelKey: 'feat.clicking'),
      OptionDef(id: 'feat.weak_grip', labelKey: 'feat.weak_grip'),
      OptionDef(id: 'feat.tingle_thumb_index', labelKey: 'feat.tingle_thumb_index'),
      OptionDef(id: 'feat.extreme_colour_temp', labelKey: 'feat.extreme_colour_temp'),
    ],
    domain: 'symptoms',
  ),

  // -------------------------------------------------------------------------
  // WEIGHT BEARING / LOADING — directly used by TS
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'wrist.function.weightBear',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'wrist.function.weightBear',
    required: true,
    options: const [
      OptionDef(id: 'wb.yes_ok', labelKey: 'wb.yes_ok'),
      OptionDef(id: 'wb.yes_pain', labelKey: 'wb.yes_pain'),
      OptionDef(id: 'wb.no', labelKey: 'wb.no'),
    ],
    domain: 'function',
  ),

  // -------------------------------------------------------------------------
  // RISK FACTORS — directly used by TS
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'wrist.context.risks',
    valueType: QuestionValueType.multiChoice,
    promptKey: 'wrist.context.risks',
    required: false,
    options: const [
      OptionDef(id: 'risk.post_meno', labelKey: 'risk.post_meno'),
      OptionDef(id: 'risk.preg_postpartum', labelKey: 'risk.preg_postpartum'),
    ],
    domain: 'context',
  ),

  // Optional narrative — not in TS scoring, but clinically useful
  QuestionDef(
    questionId: 'wrist.history.additionalInfo',
    valueType: QuestionValueType.textType,
    promptKey: 'wrist.history.additionalInfo',
    required: false,
    domain: 'history',
  ),
];
