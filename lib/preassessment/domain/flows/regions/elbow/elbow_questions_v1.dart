import 'package:kineticdx_app_v3/preassessment/domain/flow_definition.dart';

/// ---------------------------------------------------------------------------
/// ELBOW v1 — TS-aligned question set
/// Authoritative scorer: functions/src/elbow/processElbowAssessment.ts
///
/// Goal: ask every input required for "exact" parity with the TS elbow scorer.
/// Canonical questionIds are patient-friendly; the adapter maps to legacy E_* ids.
/// Red flags are asked first.
/// ---------------------------------------------------------------------------

final List<QuestionDef> elbowQuestionsV1 = [
  // -------------------------------------------------------------------------
  // RED FLAGS — ASK FIRST (triage)
  // -------------------------------------------------------------------------

  // Existing (kept)
  QuestionDef(
    questionId: 'elbow.redflags.trauma',
    valueType: QuestionValueType.boolType,
    promptKey: 'elbow.redflags.trauma',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'elbow.redflags.fever',
    valueType: QuestionValueType.boolType,
    promptKey: 'elbow.redflags.fever',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'elbow.redflags.infectionRisk',
    valueType: QuestionValueType.boolType,
    promptKey: 'elbow.redflags.infectionRisk',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'elbow.redflags.neuroDeficit',
    valueType: QuestionValueType.boolType,
    promptKey: 'elbow.redflags.neuroDeficit',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  // Missing triage drivers used by TS
  QuestionDef(
    questionId: 'elbow.redflags.injuryForce',
    valueType: QuestionValueType.boolType,
    promptKey: 'elbow.redflags.injuryForce',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'elbow.redflags.rapidSwelling',
    valueType: QuestionValueType.boolType,
    promptKey: 'elbow.redflags.rapidSwelling',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'elbow.redflags.visibleDeformity',
    valueType: QuestionValueType.boolType,
    promptKey: 'elbow.redflags.visibleDeformity',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  // TS uses E_can_straighten
  QuestionDef(
    questionId: 'elbow.redflags.canStraighten',
    valueType: QuestionValueType.boolType,
    promptKey: 'elbow.redflags.canStraighten',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  // TS uses E_hot_swollen_no_fever
  QuestionDef(
    questionId: 'elbow.redflags.hotSwollenNoFever',
    valueType: QuestionValueType.boolType,
    promptKey: 'elbow.redflags.hotSwollenNoFever',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  // -------------------------------------------------------------------------
  // CONTEXT
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'elbow.context.side',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'elbow.context.side',
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
    questionId: 'elbow.context.dominantSide',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'elbow.context.dominantSide',
    required: true,
    options: const [
      OptionDef(id: 'dom.left', labelKey: 'dom.left'),
      OptionDef(id: 'dom.right', labelKey: 'dom.right'),
      OptionDef(id: 'dom.unsure', labelKey: 'dom.unsure'),
    ],
    domain: 'context',
  ),

  // -------------------------------------------------------------------------
  // PAIN
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'elbow.pain.now',
    valueType: QuestionValueType.intType,
numeric: NumericConstraints(min: 0, max: 10),
    promptKey: 'elbow.pain.now',
    required: true,
    domain: 'pain',
  ),

  QuestionDef(
    questionId: 'elbow.pain.worst24h',
    valueType: QuestionValueType.intType,
numeric: NumericConstraints(min: 0, max: 10),
    promptKey: 'elbow.pain.worst24h',
    required: true,
    domain: 'pain',
  ),

  // -------------------------------------------------------------------------
  // HISTORY
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'elbow.history.onset',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'elbow.history.onset',
    required: true,
    options: const [
      OptionDef(id: 'onset.gradual', labelKey: 'onset.gradual'),
      OptionDef(id: 'onset.afterLoad', labelKey: 'onset.afterLoad'),
      OptionDef(id: 'onset.afterTrauma', labelKey: 'onset.afterTrauma'),
      OptionDef(id: 'onset.unsure', labelKey: 'onset.unsure'),
    ],
    domain: 'history',
  ),

  // -------------------------------------------------------------------------
  // SYMPTOMS
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'elbow.symptoms.painLocation',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'elbow.symptoms.painLocation',
    required: true,
    options: const [
      OptionDef(id: 'loc.lateral', labelKey: 'loc.lateral'),
      OptionDef(id: 'loc.medial', labelKey: 'loc.medial'),
      OptionDef(id: 'loc.posterior', labelKey: 'loc.posterior'),
      OptionDef(id: 'loc.anterior', labelKey: 'loc.anterior'),
      OptionDef(id: 'loc.diffuse', labelKey: 'loc.diffuse'),
    ],
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'elbow.symptoms.grippingPain',
    valueType: QuestionValueType.boolType,
    promptKey: 'elbow.symptoms.grippingPain',
    required: true,
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'elbow.symptoms.stiffness',
    valueType: QuestionValueType.boolType,
    promptKey: 'elbow.symptoms.stiffness',
    required: true,
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'elbow.symptoms.swelling',
    valueType: QuestionValueType.boolType,
    promptKey: 'elbow.symptoms.swelling',
    required: true,
    domain: 'symptoms',
  ),

  // Missing symptom/provocation inputs used by TS scorer
  QuestionDef(
    questionId: 'elbow.symptoms.swellingAfterActivity',
    valueType: QuestionValueType.boolType,
    promptKey: 'elbow.symptoms.swellingAfterActivity',
    required: true,
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'elbow.symptoms.clickSnap',
    valueType: QuestionValueType.boolType,
    promptKey: 'elbow.symptoms.clickSnap',
    required: true,
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'elbow.symptoms.catching',
    valueType: QuestionValueType.boolType,
    promptKey: 'elbow.symptoms.catching',
    required: true,
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'elbow.symptoms.morningStiffness',
    valueType: QuestionValueType.boolType,
    promptKey: 'elbow.symptoms.morningStiffness',
    required: true,
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'elbow.symptoms.popAnterior',
    valueType: QuestionValueType.boolType,
    promptKey: 'elbow.symptoms.popAnterior',
    required: true,
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'elbow.symptoms.forearmThumbSidePain',
    valueType: QuestionValueType.boolType,
    promptKey: 'elbow.symptoms.forearmThumbSidePain',
    required: true,
    domain: 'symptoms',
  ),

  // Nerve distribution symptoms used by TS
  QuestionDef(
    questionId: 'elbow.symptoms.paraUlnar',
    valueType: QuestionValueType.boolType,
    promptKey: 'elbow.symptoms.paraUlnar',
    required: true,
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'elbow.symptoms.paraThumbIndex',
    valueType: QuestionValueType.boolType,
    promptKey: 'elbow.symptoms.paraThumbIndex',
    required: true,
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'elbow.symptoms.neckRadiation',
    valueType: QuestionValueType.boolType,
    promptKey: 'elbow.symptoms.neckRadiation',
    required: true,
    domain: 'symptoms',
  ),

  // Provocation / load tests (self-report)
  QuestionDef(
    questionId: 'elbow.symptoms.pronationPain',
    valueType: QuestionValueType.boolType,
    promptKey: 'elbow.symptoms.pronationPain',
    required: true,
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'elbow.symptoms.resistedExtensionPain',
    valueType: QuestionValueType.boolType,
    promptKey: 'elbow.symptoms.resistedExtensionPain',
    required: true,
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'elbow.symptoms.throwValgusPain',
    valueType: QuestionValueType.boolType,
    promptKey: 'elbow.symptoms.throwValgusPain',
    required: true,
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'elbow.symptoms.posteromedialEndRangeExtensionPain',
    valueType: QuestionValueType.boolType,
    promptKey: 'elbow.symptoms.posteromedialEndRangeExtensionPain',
    required: true,
    domain: 'symptoms',
  ),

  // -------------------------------------------------------------------------
  // FUNCTION
  // -------------------------------------------------------------------------

  // Expanded to match TS coded strings (adapter maps aggs.* -> E_aggs values)
  QuestionDef(
    questionId: 'elbow.function.aggravators',
    valueType: QuestionValueType.multiChoice,
    promptKey: 'elbow.function.aggravators',
    required: false,
    options: const [
      OptionDef(id: 'aggs.palmDownGrip', labelKey: 'aggs.palmDownGrip'),
      OptionDef(id: 'aggs.twistJar', labelKey: 'aggs.twistJar'),
      OptionDef(id: 'aggs.palmUpCarry', labelKey: 'aggs.palmUpCarry'),
      OptionDef(id: 'aggs.overheadThrow', labelKey: 'aggs.overheadThrow'),
      OptionDef(id: 'aggs.restOnOlecranon', labelKey: 'aggs.restOnOlecranon'),
      OptionDef(id: 'aggs.pushUpWB', labelKey: 'aggs.pushUpWB'),
      OptionDef(id: 'aggs.none', labelKey: 'aggs.none'),
    ],
    domain: 'function',
  ),

  QuestionDef(
    questionId: 'elbow.function.dayImpact',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'elbow.function.dayImpact',
    required: true,
    options: const [
      OptionDef(id: 'impact.none', labelKey: 'impact.none'),
      OptionDef(id: 'impact.mild', labelKey: 'impact.mild'),
      OptionDef(id: 'impact.moderate', labelKey: 'impact.moderate'),
      OptionDef(id: 'impact.severe', labelKey: 'impact.severe'),
    ],
    domain: 'function',
  ),

  // -------------------------------------------------------------------------
  // OTHER
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'elbow.history.additionalInfo',
    valueType: QuestionValueType.textType,
    promptKey: 'elbow.history.additionalInfo',
    required: false,
    domain: 'other',
  ),
];
