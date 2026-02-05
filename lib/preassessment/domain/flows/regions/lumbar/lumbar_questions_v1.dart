import 'package:kineticdx_app_v3/preassessment/domain/flow_definition.dart';

/// ---------------------------------------------------------------------------
/// LUMBAR FLOW v1 — Question Definitions (TS-aligned)
/// ---------------------------------------------------------------------------
/// This set is designed to capture the exact input signals required by:
/// `functions/src/lumbar/processLumbarAssessment.ts`
///
/// The TS scorer expects legacy keys like:
///  - L_rf_bladderBowel, L_rf_saddleNumbness, L_rf_progressiveWeak,
///    L_rf_fever, L_rf_cancerHistory, L_rf_highEnergyTrauma, L_rf_nightConstant
///  - L_age_band, L_painPattern, L_whereLeg (multi), L_aggs (multi), L_eases (multi).
///  - L_pinsNeedles, L_numbness
///  - L_gaitAbility
///
/// Canonical IDs remain: lumbar.{domain}.{concept}
/// Legacy scorer IDs are produced via a Cloud Function adapter.
/// ---------------------------------------------------------------------------

final List<QuestionDef> lumbarQuestionsV1 = [
  // -------------------------------------------------------------------------
  // RED FLAGS / SAFETY — ASK FIRST (triageColour() depends on these)
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'lumbar.redflags.bladderBowelChange',
    valueType: QuestionValueType.boolType,
    promptKey: 'lumbar.redflags.bladderBowelChange',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'lumbar.redflags.saddleAnaesthesia',
    valueType: QuestionValueType.boolType,
    promptKey: 'lumbar.redflags.saddleAnaesthesia',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'lumbar.redflags.progressiveWeakness',
    valueType: QuestionValueType.boolType,
    promptKey: 'lumbar.redflags.progressiveWeakness',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'lumbar.redflags.feverUnwell',
    valueType: QuestionValueType.boolType,
    promptKey: 'lumbar.redflags.feverUnwell',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'lumbar.redflags.historyOfCancer',
    valueType: QuestionValueType.boolType,
    promptKey: 'lumbar.redflags.historyOfCancer',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'lumbar.redflags.recentTrauma',
    valueType: QuestionValueType.boolType,
    promptKey: 'lumbar.redflags.recentTrauma',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'lumbar.redflags.constantNightPain',
    valueType: QuestionValueType.boolType,
    promptKey: 'lumbar.redflags.constantNightPain',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  // -------------------------------------------------------------------------
  // PAIN
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'lumbar.pain.now',
    valueType: QuestionValueType.intType,
    promptKey: 'lumbar.pain.now',
    required: true,
    numeric: NumericConstraints(min: 0, max: 10),
    domain: 'pain',
  ),

  QuestionDef(
    questionId: 'lumbar.pain.worst24h',
    valueType: QuestionValueType.intType,
    promptKey: 'lumbar.pain.worst24h',
    required: true,
    numeric: NumericConstraints(min: 0, max: 10),
    domain: 'pain',
  ),

  // -------------------------------------------------------------------------
  // CONTEXT / HISTORY — TS expects L_age_band
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'lumbar.context.ageBand',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'lumbar.context.ageBand',
    required: true,
    options: const [
      OptionDef(id: 'age.18_35', labelKey: 'age.18_35'),
      OptionDef(id: 'age.36_50', labelKey: 'age.36_50'),
      OptionDef(id: 'age.51_65', labelKey: 'age.51_65'),
      OptionDef(id: 'age.65plus', labelKey: 'age.65plus'),
    ],
    domain: 'context',
  ),

  QuestionDef(
    questionId: 'lumbar.history.timeSinceStart',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'lumbar.history.timeSinceStart',
    required: true,
    options: const [
      OptionDef(id: 'time.lt48h', labelKey: 'time.lt48h'),
      OptionDef(id: 'time.2_14d', labelKey: 'time.2_14d'),
      OptionDef(id: 'time.2_6wk', labelKey: 'time.2_6wk'),
      OptionDef(id: 'time.gt6wk', labelKey: 'time.gt6wk'),
    ],
    domain: 'history',
  ),

  QuestionDef(
    questionId: 'lumbar.history.onset',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'lumbar.history.onset',
    required: true,
    options: const [
      OptionDef(id: 'onset.sudden', labelKey: 'onset.sudden'),
      OptionDef(id: 'onset.gradual', labelKey: 'onset.gradual'),
      OptionDef(id: 'onset.recurrent', labelKey: 'onset.recurrent'),
    ],
    domain: 'history',
  ),

  // -------------------------------------------------------------------------
  // SYMPTOMS — TS expects L_painPattern and L_whereLeg (multi)
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'lumbar.symptoms.painPattern',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'lumbar.symptoms.painPattern',
    required: true,
    options: const [
      OptionDef(id: 'pattern.central', labelKey: 'pattern.central'),
      OptionDef(id: 'pattern.oneSide', labelKey: 'pattern.oneSide'),
      OptionDef(id: 'pattern.bothSides', labelKey: 'pattern.bothSides'),
    ],
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'lumbar.symptoms.whereLeg',
    valueType: QuestionValueType.multiChoice,
    promptKey: 'lumbar.symptoms.whereLeg',
    required: true,
    options: const [
      OptionDef(id: 'where.none', labelKey: 'where.none'),
      OptionDef(id: 'where.buttock', labelKey: 'where.buttock'),
      OptionDef(id: 'where.thigh', labelKey: 'where.thigh'),
      OptionDef(id: 'where.belowKnee', labelKey: 'where.belowKnee'),
      OptionDef(id: 'where.foot', labelKey: 'where.foot'),
    ],
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'lumbar.symptoms.pinsNeedles',
    valueType: QuestionValueType.boolType,
    promptKey: 'lumbar.symptoms.pinsNeedles',
    required: true,
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'lumbar.symptoms.numbness',
    valueType: QuestionValueType.boolType,
    promptKey: 'lumbar.symptoms.numbness',
    required: true,
    domain: 'symptoms',
  ),

  // -------------------------------------------------------------------------
  // BEHAVIOUR / MECHANICAL — TS expects L_aggs and L_eases
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'lumbar.symptoms.aggravators',
    valueType: QuestionValueType.multiChoice,
    promptKey: 'lumbar.symptoms.aggravators',
    required: true,
    options: const [
      OptionDef(id: 'aggs.none', labelKey: 'aggs.none'),
      OptionDef(id: 'aggs.bendLift', labelKey: 'aggs.bendLift'),
      OptionDef(id: 'aggs.coughSneeze', labelKey: 'aggs.coughSneeze'),
      OptionDef(id: 'aggs.walk', labelKey: 'aggs.walk'),
      OptionDef(id: 'aggs.extend', labelKey: 'aggs.extend'),
      OptionDef(id: 'aggs.sitProlonged', labelKey: 'aggs.sitProlonged'),
      OptionDef(id: 'aggs.stand', labelKey: 'aggs.stand'),
    ],
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'lumbar.symptoms.easers',
    valueType: QuestionValueType.multiChoice,
    promptKey: 'lumbar.symptoms.easers',
    required: true,
    options: const [
      OptionDef(id: 'eases.none', labelKey: 'eases.none'),
      OptionDef(id: 'eases.backArched', labelKey: 'eases.backArched'),
      OptionDef(id: 'eases.lieKneesBent', labelKey: 'eases.lieKneesBent'),
      OptionDef(id: 'eases.shortWalk', labelKey: 'eases.shortWalk'),
    ],
    domain: 'symptoms',
  ),

  // -------------------------------------------------------------------------
  // FUNCTION — TS expects L_gaitAbility, and uses it as a small modifier
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'lumbar.function.gaitAbility',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'lumbar.function.gaitAbility',
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
    questionId: 'lumbar.function.dayImpact',
    valueType: QuestionValueType.intType,
    promptKey: 'lumbar.function.dayImpact',
    required: true,
    numeric: NumericConstraints(min: 0, max: 10),
    domain: 'function',
  ),

  // Optional narrative (not used by TS scorer, but critical clinically)
  QuestionDef(
    questionId: 'lumbar.history.additionalInfo',
    valueType: QuestionValueType.textType,
    promptKey: 'lumbar.history.additionalInfo',
    required: false,
    domain: 'history',
  ),
];
