import 'package:kineticdx_app_v3/preassessment/domain/flow_definition.dart';

/// ---------------------------------------------------------------------------
/// SHOULDER FLOW v1 — TS-aligned question set
/// Authoritative scorer: functions/src/shoulder/processShoulderAssessment.ts
///
/// TS expects (after normalize):
///  answers.side
///  answers.onset                gradual | afterOverhead | afterLiftPull | minorFallJar | appeared
///  answers.painArea             top_front | outer_side | back | diffuse
///  answers.nightPain            bool
///  answers.overheadAggravates   bool
///  answers.weakness             bool
///  answers.stiffness            bool
///  answers.clicking             bool
///  answers.neckInvolved         bool
///  answers.handNumbness         bool
///  answers.tenderSpot           ac_point | bicipital_groove | none_unsure
///  answers.functionLimits       strings (exact match):
///     "Reaching overhead", "Sports/overhead work", "Putting on a jacket", "Sleeping on that side"
///
/// redFlags.*:
///  feverOrHotRedJoint
///  deformityAfterInjury
///  newNeuroSymptoms
///  constantUnrelentingPain
///  cancerHistoryOrWeightLoss
///  traumaHighEnergy
///  canActiveElevateToShoulderHeight (YES means can elevate)
/// ---------------------------------------------------------------------------

final List<QuestionDef> shoulderQuestionsV1 = [
  // -------------------------------------------------------------------------
  // RED FLAGS / SAFETY — ASK FIRST
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'shoulder.redflags.feverOrHotRedJoint',
    valueType: QuestionValueType.boolType,
    promptKey: 'shoulder.redflags.feverOrHotRedJoint',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'shoulder.redflags.deformityAfterInjury',
    valueType: QuestionValueType.boolType,
    promptKey: 'shoulder.redflags.deformityAfterInjury',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'shoulder.redflags.newNeuroSymptoms',
    valueType: QuestionValueType.boolType,
    promptKey: 'shoulder.redflags.newNeuroSymptoms',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'shoulder.redflags.constantUnrelentingPain',
    valueType: QuestionValueType.boolType,
    promptKey: 'shoulder.redflags.constantUnrelentingPain',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'shoulder.redflags.cancerHistoryOrWeightLoss',
    valueType: QuestionValueType.boolType,
    promptKey: 'shoulder.redflags.cancerHistoryOrWeightLoss',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'shoulder.redflags.traumaHighEnergy',
    valueType: QuestionValueType.boolType,
    promptKey: 'shoulder.redflags.traumaHighEnergy',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  // IMPORTANT: TS uses `can_active_elevate` as YES means can elevate.
  QuestionDef(
    questionId: 'shoulder.redflags.canActiveElevateToShoulderHeight',
    valueType: QuestionValueType.boolType,
    promptKey: 'shoulder.redflags.canActiveElevateToShoulderHeight',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  // -------------------------------------------------------------------------
  // CONTEXT
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'shoulder.context.side',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'shoulder.context.side',
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
  // PAIN (not used in TS scoring directly, but essential clinically + previews)
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'shoulder.pain.now',
    valueType: QuestionValueType.intType,
    promptKey: 'shoulder.pain.now',
    required: true,
    numeric: NumericConstraints(min: 0, max: 10),
    domain: 'pain',
  ),

  QuestionDef(
    questionId: 'shoulder.pain.worst24h',
    valueType: QuestionValueType.intType,
    promptKey: 'shoulder.pain.worst24h',
    required: true,
    numeric: NumericConstraints(min: 0, max: 10),
    domain: 'pain',
  ),

  // -------------------------------------------------------------------------
  // HISTORY (TS uses onset bucket + context for calcific flare)
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'shoulder.history.onset',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'shoulder.history.onset',
    required: true,
    options: const [
      OptionDef(id: 'onset.gradual', labelKey: 'onset.gradual'),
      OptionDef(id: 'onset.afterOverhead', labelKey: 'onset.afterOverhead'),
      OptionDef(id: 'onset.afterLiftPull', labelKey: 'onset.afterLiftPull'),
      OptionDef(id: 'onset.minorFallJar', labelKey: 'onset.minorFallJar'),
      OptionDef(id: 'onset.appeared', labelKey: 'onset.appeared'),
      OptionDef(id: 'onset.unsure', labelKey: 'onset.unsure'),
    ],
    domain: 'history',
  ),

  // -------------------------------------------------------------------------
  // SYMPTOMS / PATTERN (TS uses painArea + overhead + night + stiffness etc.)
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'shoulder.symptoms.painArea',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'shoulder.symptoms.painArea',
    required: true,
    options: const [
      OptionDef(id: 'painArea.top_front', labelKey: 'painArea.top_front'),
      OptionDef(id: 'painArea.outer_side', labelKey: 'painArea.outer_side'),
      OptionDef(id: 'painArea.back', labelKey: 'painArea.back'),
      OptionDef(id: 'painArea.diffuse', labelKey: 'painArea.diffuse'),
    ],
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'shoulder.symptoms.nightPain',
    valueType: QuestionValueType.boolType,
    promptKey: 'shoulder.symptoms.nightPain',
    required: true,
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'shoulder.symptoms.overheadAggravates',
    valueType: QuestionValueType.boolType,
    promptKey: 'shoulder.symptoms.overheadAggravates',
    required: true,
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'shoulder.symptoms.weakness',
    valueType: QuestionValueType.boolType,
    promptKey: 'shoulder.symptoms.weakness',
    required: true,
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'shoulder.symptoms.stiffness',
    valueType: QuestionValueType.boolType,
    promptKey: 'shoulder.symptoms.stiffness',
    required: true,
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'shoulder.symptoms.clicking',
    valueType: QuestionValueType.boolType,
    promptKey: 'shoulder.symptoms.clicking',
    required: true,
    domain: 'symptoms',
  ),

  // Cervical referred trigger
  QuestionDef(
    questionId: 'shoulder.symptoms.neckInvolved',
    valueType: QuestionValueType.boolType,
    promptKey: 'shoulder.symptoms.neckInvolved',
    required: true,
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'shoulder.symptoms.handNumbness',
    valueType: QuestionValueType.boolType,
    promptKey: 'shoulder.symptoms.handNumbness',
    required: true,
    domain: 'symptoms',
  ),

  // NEW discriminator required by TS (tender spot)
  QuestionDef(
    questionId: 'shoulder.symptoms.tenderSpot',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'shoulder.symptoms.tenderSpot',
    required: true,
    options: const [
      OptionDef(id: 'tender.ac_point', labelKey: 'tender.ac_point'),
      OptionDef(id: 'tender.bicipital_groove', labelKey: 'tender.bicipital_groove'),
      OptionDef(id: 'tender.none_unsure', labelKey: 'tender.none_unsure'),
    ],
    domain: 'symptoms',
  ),

  // -------------------------------------------------------------------------
  // FUNCTION LIMITS — TS expects specific strings in functionLimits array
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'shoulder.function.limits',
    valueType: QuestionValueType.multiChoice,
    promptKey: 'shoulder.function.limits',
    required: false, // allow none
    options: const [
      OptionDef(id: 'limit.reaching_overhead', labelKey: 'limit.reaching_overhead'),
      OptionDef(id: 'limit.sports_overhead_work', labelKey: 'limit.sports_overhead_work'),
      OptionDef(id: 'limit.putting_on_jacket', labelKey: 'limit.putting_on_jacket'),
      OptionDef(id: 'limit.sleeping_on_side', labelKey: 'limit.sleeping_on_side'),
      OptionDef(id: 'limit.none', labelKey: 'limit.none'),
    ],
    domain: 'function',
  ),

  QuestionDef(
    questionId: 'shoulder.function.dayImpact',
    valueType: QuestionValueType.intType,
    promptKey: 'shoulder.function.dayImpact',
    required: true,
    numeric: NumericConstraints(min: 0, max: 10),
    domain: 'function',
  ),

  // Optional narrative (not used in TS scoring but important clinically)
  QuestionDef(
    questionId: 'shoulder.history.additionalInfo',
    valueType: QuestionValueType.textType,
    promptKey: 'shoulder.history.additionalInfo',
    required: false,
    domain: 'history',
  ),
];
