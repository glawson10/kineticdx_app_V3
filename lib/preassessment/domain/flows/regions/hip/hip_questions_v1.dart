import 'package:kineticdx_app_v3/preassessment/domain/flow_definition.dart';

/// ---------------------------------------------------------------------------
/// HIP v1 — scorer-aligned question set
/// Authoritative scorer: functions/src/hip/processHipAssessment.ts
///
/// Scorer reads these legacy ids (adapter must supply):
///  TRIAGE:
///   - H_rf_high_energy
///   - H_rf_fall_impact
///   - H_rf_cant_weightbear
///   - H_rf_fever
///   - H_rf_tiny_movement_agony
///   - H_rf_under16_new_limp
///   - H_rf_cancer_history
///   - H_rf_amber_risks (multi)
///
///  SCORING:
///   - H_onset
///   - H_where (multi; includes "lateral")
///   - H_aggs (multi; includes "stairs","stand_walk","side-lying")
///   - H_sleep (single; "wakes_side")
///   - H_walk (single; "support"|"limp"|...)
///   - H_irrit_on
///   - H_irrit_off
///   - H_hx_dysplasia, H_hx_hypermobility
///   - H_neuro_pins_needles
///   - H_feat_cough_strain, H_feat_reproducible_snap, H_feat_sitbone
///   - H_side (summary label)
///
/// Canonical IDs preserved; adapter converts to legacy.
/// ---------------------------------------------------------------------------

final List<QuestionDef> hipQuestionsV1 = [
  // -------------------------------------------------------------------------
  // RED FLAGS — ASK FIRST
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'hip.redflags.highEnergyTrauma',
    valueType: QuestionValueType.boolType,
    promptKey: 'hip.redflags.highEnergyTrauma',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  // ✅ NEW (triage)
  QuestionDef(
    questionId: 'hip.redflags.fallImpact',
    valueType: QuestionValueType.boolType,
    promptKey: 'hip.redflags.fallImpact',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'hip.redflags.feverUnwell',
    valueType: QuestionValueType.boolType,
    promptKey: 'hip.redflags.feverUnwell',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  // ✅ NEW (triage — paired with fever)
  QuestionDef(
    questionId: 'hip.redflags.tinyMovementAgony',
    valueType: QuestionValueType.boolType,
    promptKey: 'hip.redflags.tinyMovementAgony',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  // ✅ NEW (triage — SUFE)
  QuestionDef(
    questionId: 'hip.redflags.under16NewLimp',
    valueType: QuestionValueType.boolType,
    promptKey: 'hip.redflags.under16NewLimp',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'hip.redflags.historyOfCancer',
    valueType: QuestionValueType.boolType,
    promptKey: 'hip.redflags.historyOfCancer',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'hip.redflags.unableToWeightBear',
    valueType: QuestionValueType.boolType,
    promptKey: 'hip.redflags.unableToWeightBear',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  // ✅ NEW (triage — AMBER risks; scorer only checks length > 0)
  QuestionDef(
    questionId: 'hip.redflags.amberRisks',
    valueType: QuestionValueType.multiChoice,
    promptKey: 'hip.redflags.amberRisks',
    required: false,
    contributesToTriage: true,
    options: const [
      OptionDef(id: 'risks.immunosuppression', labelKey: 'risks.immunosuppression'),
      OptionDef(id: 'risks.steroidUse', labelKey: 'risks.steroidUse'),
      OptionDef(id: 'risks.diabetes', labelKey: 'risks.diabetes'),
      OptionDef(id: 'risks.other', labelKey: 'risks.other'),
      OptionDef(id: 'risks.none', labelKey: 'risks.none'),
    ],
    domain: 'redflags',
  ),

  // -------------------------------------------------------------------------
  // CONTEXT
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'hip.context.side',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'hip.context.side',
    required: true,
    options: const [
      OptionDef(id: 'side.left', labelKey: 'side.left'),
      OptionDef(id: 'side.right', labelKey: 'side.right'),
      OptionDef(id: 'side.both', labelKey: 'side.both'),
      OptionDef(id: 'side.unsure', labelKey: 'side.unsure'),
    ],
    domain: 'context',
  ),

  // Keep age band (may be used by UI/analytics)
  QuestionDef(
    questionId: 'hip.context.ageBand',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'hip.context.ageBand',
    required: true,
    options: const [
      // ✅ NEW (helps match SUFE logic if you ever gate by age later)
      OptionDef(id: 'age.under16', labelKey: 'age.under16'),
      OptionDef(id: 'age.16_17', labelKey: 'age.16_17'),
      OptionDef(id: 'age.18_35', labelKey: 'age.18_35'),
      OptionDef(id: 'age.36_50', labelKey: 'age.36_50'),
      OptionDef(id: 'age.51_65', labelKey: 'age.51_65'),
      OptionDef(id: 'age.65plus', labelKey: 'age.65plus'),
    ],
    domain: 'context',
  ),

  // -------------------------------------------------------------------------
  // PAIN
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'hip.pain.now',
    valueType: QuestionValueType.intType,
    promptKey: 'hip.pain.now',
    required: true,
    numeric: NumericConstraints(min: 0, max: 10),
    domain: 'pain',
  ),

  QuestionDef(
    questionId: 'hip.pain.worst24h',
    valueType: QuestionValueType.intType,
    promptKey: 'hip.pain.worst24h',
    required: true,
    numeric: NumericConstraints(min: 0, max: 10),
    domain: 'pain',
  ),

  // -------------------------------------------------------------------------
  // HISTORY (scorer needs onset)
  // -------------------------------------------------------------------------

  // ✅ NEW (required by scorer)
  QuestionDef(
    questionId: 'hip.history.onset',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'hip.history.onset',
    required: true,
    options: const [
      OptionDef(id: 'onset.sudden', labelKey: 'onset.sudden'),
      OptionDef(id: 'onset.gradual', labelKey: 'onset.gradual'),
      OptionDef(id: 'onset.unsure', labelKey: 'onset.unsure'),
    ],
    domain: 'history',
  ),

  // ✅ NEW (instability spectrum)
  QuestionDef(
    questionId: 'hip.history.dysplasiaHistory',
    valueType: QuestionValueType.boolType,
    promptKey: 'hip.history.dysplasiaHistory',
    required: true,
    domain: 'history',
  ),

  QuestionDef(
    questionId: 'hip.history.hypermobilityHistory',
    valueType: QuestionValueType.boolType,
    promptKey: 'hip.history.hypermobilityHistory',
    required: true,
    domain: 'history',
  ),

  // -------------------------------------------------------------------------
  // SYMPTOMS / LOCATION
  // -------------------------------------------------------------------------

  // Keep existing painLocation; adapter will emit H_where (multi)
  QuestionDef(
    questionId: 'hip.symptoms.painLocation',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'hip.symptoms.painLocation',
    required: true,
    options: const [
      OptionDef(id: 'loc.groin', labelKey: 'loc.groin'),
      OptionDef(id: 'loc.outer', labelKey: 'loc.outer'),
      OptionDef(id: 'loc.buttock', labelKey: 'loc.buttock'),
      OptionDef(id: 'loc.diffuse', labelKey: 'loc.diffuse'),
    ],
    domain: 'symptoms',
  ),

  // These are still useful for UI; adapter will map to scorer features where possible
  QuestionDef(
    questionId: 'hip.symptoms.groinPain',
    valueType: QuestionValueType.boolType,
    promptKey: 'hip.symptoms.groinPain',
    required: true,
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'hip.symptoms.clickingCatching',
    valueType: QuestionValueType.boolType,
    promptKey: 'hip.symptoms.clickingCatching',
    required: true,
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'hip.symptoms.stiffness',
    valueType: QuestionValueType.boolType,
    promptKey: 'hip.symptoms.stiffness',
    required: true,
    domain: 'symptoms',
  ),

  // ✅ NEW (sleep token drives GTPS pathway)
  QuestionDef(
    questionId: 'hip.symptoms.sleep',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'hip.symptoms.sleep',
    required: true,
    options: const [
      OptionDef(id: 'sleep.none', labelKey: 'sleep.none'),
      OptionDef(id: 'sleep.wakesSide', labelKey: 'sleep.wakesSide'),
      OptionDef(id: 'sleep.wakesOther', labelKey: 'sleep.wakesOther'),
    ],
    domain: 'symptoms',
  ),

  // ✅ NEW (irritability on/off)
  QuestionDef(
    questionId: 'hip.symptoms.irritabilityOn',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'hip.symptoms.irritabilityOn',
    required: true,
    options: const [
      OptionDef(id: 'irritOn.immediate', labelKey: 'irritOn.immediate'),
      OptionDef(id: 'irritOn.afterMinutes', labelKey: 'irritOn.afterMinutes'),
      OptionDef(id: 'irritOn.afterHours', labelKey: 'irritOn.afterHours'),
      OptionDef(id: 'irritOn.variable', labelKey: 'irritOn.variable'),
    ],
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'hip.symptoms.irritabilityOff',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'hip.symptoms.irritabilityOff',
    required: true,
    options: const [
      OptionDef(id: 'irritOff.minutes', labelKey: 'irritOff.minutes'),
      OptionDef(id: 'irritOff.hours', labelKey: 'irritOff.hours'),
      OptionDef(id: 'irritOff.days', labelKey: 'irritOff.days'),
      OptionDef(id: 'irritOff.doesNotSettle', labelKey: 'irritOff.doesNotSettle'),
    ],
    domain: 'symptoms',
  ),

  // ✅ NEW (neuro and specific features used by scorer)
  QuestionDef(
    questionId: 'hip.symptoms.pinsNeedles',
    valueType: QuestionValueType.boolType,
    promptKey: 'hip.symptoms.pinsNeedles',
    required: true,
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'hip.symptoms.coughStrain',
    valueType: QuestionValueType.boolType,
    promptKey: 'hip.symptoms.coughStrain',
    required: true,
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'hip.symptoms.reproducibleSnapping',
    valueType: QuestionValueType.boolType,
    promptKey: 'hip.symptoms.reproducibleSnapping',
    required: true,
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'hip.symptoms.sitBonePain',
    valueType: QuestionValueType.boolType,
    promptKey: 'hip.symptoms.sitBonePain',
    required: true,
    domain: 'symptoms',
  ),

  // -------------------------------------------------------------------------
  // BEHAVIOUR
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'hip.symptoms.aggravators',
    valueType: QuestionValueType.multiChoice,
    promptKey: 'hip.symptoms.aggravators',
    required: false,
    options: const [
      // Existing
      OptionDef(id: 'aggs.walk', labelKey: 'aggs.walk'),
      OptionDef(id: 'aggs.stairs', labelKey: 'aggs.stairs'),
      OptionDef(id: 'aggs.sitLong', labelKey: 'aggs.sitLong'),
      OptionDef(id: 'aggs.twist', labelKey: 'aggs.twist'),
      OptionDef(id: 'aggs.run', labelKey: 'aggs.run'),

      // ✅ NEW (direct scorer tokens)
      OptionDef(id: 'aggs.standWalk', labelKey: 'aggs.standWalk'),
      OptionDef(id: 'aggs.sideLying', labelKey: 'aggs.sideLying'),

      OptionDef(id: 'aggs.none', labelKey: 'aggs.none'),
    ],
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'hip.symptoms.easers',
    valueType: QuestionValueType.multiChoice,
    promptKey: 'hip.symptoms.easers',
    required: false,
    options: const [
      OptionDef(id: 'eases.rest', labelKey: 'eases.rest'),
      OptionDef(id: 'eases.shortWalk', labelKey: 'eases.shortWalk'),
      OptionDef(id: 'eases.heat', labelKey: 'eases.heat'),
      OptionDef(id: 'eases.none', labelKey: 'eases.none'),
    ],
    domain: 'symptoms',
  ),

  // -------------------------------------------------------------------------
  // FUNCTION
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'hip.function.gaitAbility',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'hip.function.gaitAbility',
    required: true,
    options: const [
      OptionDef(id: 'gait.normal', labelKey: 'gait.normal'),
      OptionDef(id: 'gait.limp', labelKey: 'gait.limp'),
      OptionDef(id: 'gait.support', labelKey: 'gait.support'),
      OptionDef(id: 'gait.cannot', labelKey: 'gait.cannot'),
    ],
    domain: 'function',
  ),

  QuestionDef(
    questionId: 'hip.function.dayImpact',
    valueType: QuestionValueType.intType,
    promptKey: 'hip.function.dayImpact',
    required: true,
    numeric: NumericConstraints(min: 0, max: 10),
    domain: 'function',
  ),

  // Narrative
  QuestionDef(
    questionId: 'hip.history.additionalInfo',
    valueType: QuestionValueType.textType,
    promptKey: 'hip.history.additionalInfo',
    required: false,
    domain: 'history',
  ),
];
