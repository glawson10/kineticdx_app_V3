import 'package:kineticdx_app_v3/preassessment/domain/flow_definition.dart';

/// ---------------------------------------------------------------------------
/// KNEE v1 — TS-aligned question set
/// Authoritative scorer: functions/src/knee/processKneeAssessment.ts
///
/// Scorer reads (must be captured for valid triage + ranking):
///
///  TRIAGE (computeTriage)
///   - K_rf_cantWB_initial
///   - K_rf_lockedNow
///   - K_rf_hotRedFeverish
///   - K_rf_newNumbFoot
///   - K_rf_coldPaleFoot
///   - K_rf_highEnergyTrauma
///   - (amber signals) K_feltPop, K_rapidSwellingUnder2h
///
///  SCORING (score)
///   - K_onsetType
///   - K_painLocation (multi)
///   - K_painTriggers (multi)
///   - K_feltPop
///   - K_rapidSwellingUnder2h
///   - K_currentInstability
///   - K_blockedExtension
///   - K_tendonFocus
///   - K_stiffMorning
///   - K_lateralRunPain
///
/// Your canonical IDs are preserved; the TS adapter maps canonical → legacy.
/// ---------------------------------------------------------------------------

/// ---------------------------------------------------------------------------
/// PAGE 1 — RED FLAGS (ASK FIRST)
/// This is a dedicated page for urgent triage signals.
/// ---------------------------------------------------------------------------
final List<QuestionDef> kneeRedflagsPageV1 = [
  QuestionDef(
    questionId: 'knee.redflags.highEnergyTrauma',
    valueType: QuestionValueType.boolType,
    promptKey: 'knee.redflags.highEnergyTrauma',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'knee.redflags.lockedKnee',
    valueType: QuestionValueType.boolType,
    promptKey: 'knee.redflags.lockedKnee',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  /// NOTE:
  /// The scorer uses K_rf_hotRedFeverish (hot/red + fever/unwell).
  /// Previously we only captured "hotSwollenJoint". We keep it, but ALSO add
  /// a direct fever/unwell redflag question so the adapter can map correctly.
  QuestionDef(
    questionId: 'knee.redflags.hotSwollenJoint',
    valueType: QuestionValueType.boolType,
    promptKey: 'knee.redflags.hotSwollenJoint',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'knee.redflags.feverUnwell',
    valueType: QuestionValueType.boolType,
    promptKey: 'knee.redflags.feverUnwell',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'knee.redflags.unableToWeightBear',
    valueType: QuestionValueType.boolType,
    promptKey: 'knee.redflags.unableToWeightBear',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'knee.redflags.newNumbFoot',
    valueType: QuestionValueType.boolType,
    promptKey: 'knee.redflags.newNumbFoot',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'knee.redflags.coldPaleFoot',
    valueType: QuestionValueType.boolType,
    promptKey: 'knee.redflags.coldPaleFoot',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'knee.redflags.historyOfCancer',
    valueType: QuestionValueType.boolType,
    promptKey: 'knee.redflags.historyOfCancer',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),
];

/// ---------------------------------------------------------------------------
/// PAGE 2+ — MAIN ASSESSMENT (context → pain → history → symptoms → function)
/// ---------------------------------------------------------------------------
final List<QuestionDef> kneeMainQuestionsV1 = [
  // -------------------------------------------------------------------------
  // CONTEXT
  // -------------------------------------------------------------------------
  QuestionDef(
    questionId: 'knee.context.side',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'knee.context.side',
    required: true,
    options: const [
      OptionDef(id: 'side.left', labelKey: 'side.left'),
      OptionDef(id: 'side.right', labelKey: 'side.right'),
      OptionDef(id: 'side.both', labelKey: 'side.both'),
      OptionDef(id: 'side.unsure', labelKey: 'side.unsure'),
    ],
    domain: 'context',
  ),

  QuestionDef(
    questionId: 'knee.context.ageBand',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'knee.context.ageBand',
    required: true,
    options: const [
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
    questionId: 'knee.pain.now',
    valueType: QuestionValueType.intType,
    promptKey: 'knee.pain.now',
    required: true,
    numeric: NumericConstraints(min: 0, max: 10),
    domain: 'pain',
  ),

  QuestionDef(
    questionId: 'knee.pain.worst24h',
    valueType: QuestionValueType.intType,
    promptKey: 'knee.pain.worst24h',
    required: true,
    numeric: NumericConstraints(min: 0, max: 10),
    domain: 'pain',
  ),

  // -------------------------------------------------------------------------
  // HISTORY (SCORER-CRITICAL)
  // -------------------------------------------------------------------------
  /// Maps to scorer K_onsetType via adapter.
  QuestionDef(
    questionId: 'knee.history.onset',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'knee.history.onset',
    required: true,
    options: const [
      OptionDef(id: 'onset.gradual', labelKey: 'onset.gradual'),
      OptionDef(id: 'onset.twist', labelKey: 'onset.twist'),
      OptionDef(id: 'onset.directBlow', labelKey: 'onset.directBlow'),
      OptionDef(id: 'onset.afterLoad', labelKey: 'onset.afterLoad'),
      OptionDef(id: 'onset.unsure', labelKey: 'onset.unsure'),
    ],
    domain: 'history',
  ),

  /// Scorer discriminator: K_feltPop
  QuestionDef(
    questionId: 'knee.history.feltPop',
    valueType: QuestionValueType.boolType,
    promptKey: 'knee.history.feltPop',
    required: true,
    domain: 'history',
  ),

  /// Scorer discriminator: K_rapidSwellingUnder2h
  QuestionDef(
    questionId: 'knee.history.rapidSwellingUnder2h',
    valueType: QuestionValueType.boolType,
    promptKey: 'knee.history.rapidSwellingUnder2h',
    required: true,
    domain: 'history',
  ),

  // -------------------------------------------------------------------------
  // SYMPTOMS (SCORER-CRITICAL)
  // -------------------------------------------------------------------------
  /// Maps to scorer K_painLocation (multi) via adapter.
  QuestionDef(
    questionId: 'knee.symptoms.painLocation',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'knee.symptoms.painLocation',
    required: true,
    options: const [
      OptionDef(id: 'loc.front', labelKey: 'loc.front'),
      OptionDef(id: 'loc.medial', labelKey: 'loc.medial'),
      OptionDef(id: 'loc.lateral', labelKey: 'loc.lateral'),
      OptionDef(id: 'loc.back', labelKey: 'loc.back'),
      OptionDef(id: 'loc.diffuse', labelKey: 'loc.diffuse'),
    ],
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'knee.symptoms.swelling',
    valueType: QuestionValueType.boolType,
    promptKey: 'knee.symptoms.swelling',
    required: true,
    domain: 'symptoms',
  ),

  /// Maps to scorer K_currentInstability
  QuestionDef(
    questionId: 'knee.symptoms.givingWay',
    valueType: QuestionValueType.boolType,
    promptKey: 'knee.symptoms.givingWay',
    required: true,
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'knee.symptoms.clickingLocking',
    valueType: QuestionValueType.boolType,
    promptKey: 'knee.symptoms.clickingLocking',
    required: true,
    domain: 'symptoms',
  ),

  /// Keep your original stiffness question (patient-friendly),
  /// but add scorer-specific morning stiffness signal too.
  QuestionDef(
    questionId: 'knee.symptoms.stiffness',
    valueType: QuestionValueType.boolType,
    promptKey: 'knee.symptoms.stiffness',
    required: true,
    domain: 'symptoms',
  ),

  /// Scorer discriminator: K_blockedExtension
  QuestionDef(
    questionId: 'knee.symptoms.blockedExtension',
    valueType: QuestionValueType.boolType,
    promptKey: 'knee.symptoms.blockedExtension',
    required: true,
    domain: 'symptoms',
  ),

  /// Scorer discriminator: K_tendonFocus (yes/no “tendon-like pain” pattern)
  QuestionDef(
    questionId: 'knee.symptoms.tendonFocus',
    valueType: QuestionValueType.boolType,
    promptKey: 'knee.symptoms.tendonFocus',
    required: true,
    domain: 'symptoms',
  ),

  /// Scorer discriminator: K_stiffMorning
  QuestionDef(
    questionId: 'knee.symptoms.morningStiffness',
    valueType: QuestionValueType.boolType,
    promptKey: 'knee.symptoms.morningStiffness',
    required: true,
    domain: 'symptoms',
  ),

  /// Scorer discriminator: K_lateralRunPain
  QuestionDef(
    questionId: 'knee.symptoms.lateralRunPain',
    valueType: QuestionValueType.boolType,
    promptKey: 'knee.symptoms.lateralRunPain',
    required: true,
    domain: 'symptoms',
  ),

  // -------------------------------------------------------------------------
  // FUNCTION / LOAD (SCORER-CRITICAL: triggers)
  // -------------------------------------------------------------------------
  /// Maps to scorer K_painTriggers (multi) via adapter.
  QuestionDef(
    questionId: 'knee.function.aggravators',
    valueType: QuestionValueType.multiChoice,
    promptKey: 'knee.function.aggravators',
    required: false,
    options: const [
      OptionDef(id: 'aggs.walk', labelKey: 'aggs.walk'),
      OptionDef(id: 'aggs.stairs', labelKey: 'aggs.stairs'),
      OptionDef(id: 'aggs.squat', labelKey: 'aggs.squat'),
      OptionDef(id: 'aggs.run', labelKey: 'aggs.run'),
      OptionDef(id: 'aggs.kneel', labelKey: 'aggs.kneel'),
      OptionDef(id: 'aggs.none', labelKey: 'aggs.none'),
    ],
    domain: 'function',
  ),

  QuestionDef(
    questionId: 'knee.function.dayImpact',
    valueType: QuestionValueType.intType,
    promptKey: 'knee.function.dayImpact',
    required: true,
    numeric: NumericConstraints(min: 0, max: 10),
    domain: 'function',
  ),

  // -------------------------------------------------------------------------
  // Narrative
  // -------------------------------------------------------------------------
  QuestionDef(
    questionId: 'knee.history.additionalInfo',
    valueType: QuestionValueType.textType,
    promptKey: 'knee.history.additionalInfo',
    required: false,
    domain: 'history',
  ),
];

/// The combined question list: RED FLAGS page first, then main assessment.
final List<QuestionDef> kneeQuestionsV1 = [
  ...kneeRedflagsPageV1,
  ...kneeMainQuestionsV1,
];
