import 'package:kineticdx_app_v3/preassessment/domain/flow_definition.dart';

/// ---------------------------------------------------------------------------
/// THORACIC v1 — TS-aligned question set
/// Authoritative scorer: processThoracicAssessment.ts
///
/// TS reads Answer[] with IDs:
///  Q1_trauma (single): none | minor | major
///  Q2_redcluster (multi): none | chest_pressure | sob | fever_ache | wtloss
///  Q3_neuro (multi): none | (anything else -> red)
///  Q4_rest (single): movement_only | some_positions | all_positions
///  Q5_onset (single): gradual | lift_twist | sport | woke
///  Q6_location (single): between_blades | front_chest | band_one_side
///  Q7_worse (multi): sitting | overhead | breath | bed
///  Q8_better (multi): move | posture | nothing
///  Q9_irritability (single): lt5 | _5_30 | gt30
///  Q10_breathprov (single): none | local_sharp | sob
///  Q11_sleep (single): ok | hard
///  Q12_band (single): none | one_side
///  Q13_pain_now (single numeric): 0–10 (string->Number in TS)
///
/// Canonical IDs used in Flutter; adapter maps to Q IDs.
/// ---------------------------------------------------------------------------

final List<QuestionDef> thoracicQuestionsV1 = [
  // -------------------------------------------------------------------------
  // RED FLAGS / SAFETY — ASK FIRST
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'thoracic.redflags.trauma',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'thoracic.redflags.trauma',
    required: true,
    contributesToTriage: true,
    options: const [
      OptionDef(id: 'none', labelKey: 'thoracic.trauma.none'),
      OptionDef(id: 'minor', labelKey: 'thoracic.trauma.minor'),
      OptionDef(id: 'major', labelKey: 'thoracic.trauma.major'),
    ],
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'thoracic.redflags.redCluster',
    valueType: QuestionValueType.multiChoice,
    promptKey: 'thoracic.redflags.redCluster',
    required: false,
    contributesToTriage: true,
    options: const [
      OptionDef(id: 'none', labelKey: 'thoracic.redcluster.none'),
      OptionDef(id: 'chest_pressure', labelKey: 'thoracic.redcluster.chest_pressure'),
      OptionDef(id: 'sob', labelKey: 'thoracic.redcluster.sob'),
      OptionDef(id: 'fever_ache', labelKey: 'thoracic.redcluster.fever_ache'),
      OptionDef(id: 'wtloss', labelKey: 'thoracic.redcluster.wtloss'),
    ],
    domain: 'redflags',
  ),

  // TS: if ANY neuro option selected (besides "none"), triage -> red
  QuestionDef(
    questionId: 'thoracic.redflags.neuro',
    valueType: QuestionValueType.multiChoice,
    promptKey: 'thoracic.redflags.neuro',
    required: false,
    contributesToTriage: true,
    options: const [
      OptionDef(id: 'none', labelKey: 'thoracic.neuro.none'),
      OptionDef(id: 'bilateral_symptoms', labelKey: 'thoracic.neuro.bilateral_symptoms'),
      OptionDef(id: 'gait_change', labelKey: 'thoracic.neuro.gait_change'),
      OptionDef(id: 'bowel_bladder', labelKey: 'thoracic.neuro.bowel_bladder'),
    ],
    domain: 'redflags',
  ),

  // -------------------------------------------------------------------------
  // SEVERITY / CONSTANCY
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'thoracic.symptoms.restPattern',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'thoracic.symptoms.restPattern',
    required: true,
    contributesToTriage: true,
    options: const [
      OptionDef(id: 'movement_only', labelKey: 'thoracic.rest.movement_only'),
      OptionDef(id: 'some_positions', labelKey: 'thoracic.rest.some_positions'),
      OptionDef(id: 'all_positions', labelKey: 'thoracic.rest.all_positions'),
    ],
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'thoracic.symptoms.breathProvocation',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'thoracic.symptoms.breathProvocation',
    required: true,
    contributesToTriage: true,
    options: const [
      OptionDef(id: 'none', labelKey: 'thoracic.breath.none'),
      OptionDef(id: 'local_sharp', labelKey: 'thoracic.breath.local_sharp'),
      OptionDef(id: 'sob', labelKey: 'thoracic.breath.sob'),
    ],
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'thoracic.pain.now',
    valueType: QuestionValueType.intType,
    promptKey: 'thoracic.pain.now',
    required: true,
    numeric: NumericConstraints(min: 0, max: 10),
    domain: 'pain',
  ),

  // -------------------------------------------------------------------------
  // HISTORY / PATTERN
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'thoracic.history.onset',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'thoracic.history.onset',
    required: true,
    options: const [
      OptionDef(id: 'gradual', labelKey: 'thoracic.onset.gradual'),
      OptionDef(id: 'lift_twist', labelKey: 'thoracic.onset.lift_twist'),
      OptionDef(id: 'sport', labelKey: 'thoracic.onset.sport'),
      OptionDef(id: 'woke', labelKey: 'thoracic.onset.woke'),
    ],
    domain: 'history',
  ),

  QuestionDef(
    questionId: 'thoracic.symptoms.location',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'thoracic.symptoms.location',
    required: true,
    options: const [
      OptionDef(id: 'between_blades', labelKey: 'thoracic.loc.between_blades'),
      OptionDef(id: 'front_chest', labelKey: 'thoracic.loc.front_chest'),
      OptionDef(id: 'band_one_side', labelKey: 'thoracic.loc.band_one_side'),
    ],
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'thoracic.symptoms.worse',
    valueType: QuestionValueType.multiChoice,
    promptKey: 'thoracic.symptoms.worse',
    required: false,
    options: const [
      OptionDef(id: 'sitting', labelKey: 'thoracic.worse.sitting'),
      OptionDef(id: 'overhead', labelKey: 'thoracic.worse.overhead'),
      OptionDef(id: 'breath', labelKey: 'thoracic.worse.breath'),
      OptionDef(id: 'bed', labelKey: 'thoracic.worse.bed'),
      OptionDef(id: 'none', labelKey: 'thoracic.worse.none'),
    ],
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'thoracic.symptoms.better',
    valueType: QuestionValueType.multiChoice,
    promptKey: 'thoracic.symptoms.better',
    required: false,
    options: const [
      OptionDef(id: 'move', labelKey: 'thoracic.better.move'),
      OptionDef(id: 'posture', labelKey: 'thoracic.better.posture'),
      OptionDef(id: 'nothing', labelKey: 'thoracic.better.nothing'),
      OptionDef(id: 'none', labelKey: 'thoracic.better.none'),
    ],
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'thoracic.symptoms.irritability',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'thoracic.symptoms.irritability',
    required: true,
    options: const [
      OptionDef(id: 'lt5', labelKey: 'thoracic.irrit.lt5'),
      OptionDef(id: '_5_30', labelKey: 'thoracic.irrit._5_30'),
      OptionDef(id: 'gt30', labelKey: 'thoracic.irrit.gt30'),
    ],
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'thoracic.symptoms.sleep',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'thoracic.symptoms.sleep',
    required: true,
    options: const [
      OptionDef(id: 'ok', labelKey: 'thoracic.sleep.ok'),
      OptionDef(id: 'hard', labelKey: 'thoracic.sleep.hard'),
    ],
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'thoracic.symptoms.band',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'thoracic.symptoms.band',
    required: true,
    options: const [
      OptionDef(id: 'none', labelKey: 'thoracic.band.none'),
      OptionDef(id: 'one_side', labelKey: 'thoracic.band.one_side'),
    ],
    domain: 'symptoms',
  ),

  // Narrative (not used in TS scoring, but valuable clinically)
  QuestionDef(
    questionId: 'thoracic.history.additionalInfo',
    valueType: QuestionValueType.textType,
    promptKey: 'thoracic.history.additionalInfo',
    required: false,
    domain: 'history',
  ),
];
