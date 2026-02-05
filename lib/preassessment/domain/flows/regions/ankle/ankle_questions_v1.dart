import 'package:kineticdx_app_v3/preassessment/domain/flow_definition.dart';

/// ---------------------------------------------------------------------------
/// ANKLE v1 — TS-aligned question set
/// Authoritative scorer: functions/src/ankle/processAnkleAssessment.ts
///
/// TS expects legacy IDs:
///  Singles:
///   - A_mech: inversionRoll | footFixedTwist | hardLanding | gradual
///   - A_timeSince: lt48h | _2_14d | _2_6wk | gt6wk
///   - A_onsetStyle: explosive | creeping | recurrent
///   - A_instability: never | sometimes | often
///   - A_rf_fromFallTwistLanding: yes|no
///   - A_rf_walk4Now: yes|barely|no
///   - A_rf_hotRedFever: yes|no
///   - A_rf_calfHotTight: yes|no
///   - A_rf_tiptoes: yes|no
///   - A_rf_highSwelling: yes|no
///
///  Multi:
///   - A_painSite: lateralATFL | syndesmosisHigh | achilles | plantar | midfoot
///   - A_loadAggs: walkFlat | stairsHillsTiptoe | cuttingLanding | firstStepsWorse | throbsAtRest
///   - A_rf_followUps: fourStepsImmediate | popHeard | deformity | numbPins
///
///  Slider:
///   - A_impactScore (0–10)
///
/// Canonical IDs used in Flutter; adapter maps canonical -> legacy.
/// ---------------------------------------------------------------------------

final List<QuestionDef> ankleQuestionsV1 = [
  // -------------------------------------------------------------------------
  // PAIN + IMPACT (used in TS: A_impactScore)
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'ankle.pain.now',
    valueType: QuestionValueType.intType,
    promptKey: 'ankle.pain.now',
    required: true,
    numeric: NumericConstraints(min: 0, max: 10),
    domain: 'pain',
  ),

  QuestionDef(
    questionId: 'ankle.pain.worst24h',
    valueType: QuestionValueType.intType,
    promptKey: 'ankle.pain.worst24h',
    required: true,
    numeric: NumericConstraints(min: 0, max: 10),
    domain: 'pain',
  ),

  QuestionDef(
    questionId: 'ankle.function.dayImpact',
    valueType: QuestionValueType.intType,
    promptKey: 'ankle.function.dayImpact',
    required: true,
    numeric: NumericConstraints(min: 0, max: 10),
    domain: 'function',
  ),

  // -------------------------------------------------------------------------
  // RED FLAGS — ask early (TS: multiple A_rf_*)
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'ankle.redflags.fromFallTwistLanding',
    valueType: QuestionValueType.boolType,
    promptKey: 'ankle.redflags.fromFallTwistLanding',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  /// TS A_rf_followUps (multi)
  QuestionDef(
    questionId: 'ankle.redflags.followUps',
    valueType: QuestionValueType.multiChoice,
    promptKey: 'ankle.redflags.followUps',
    required: false, // ✅ not required — allow progress even if skipped
    contributesToTriage: true,
    options: const [
      OptionDef(id: 'follow.fourStepsImmediate', labelKey: 'follow.fourStepsImmediate'),
      OptionDef(id: 'follow.popHeard', labelKey: 'follow.popHeard'),
      OptionDef(id: 'follow.deformity', labelKey: 'follow.deformity'),
      OptionDef(id: 'follow.numbPins', labelKey: 'follow.numbPins'),
      OptionDef(id: 'follow.none', labelKey: 'follow.none'),
    ],
    domain: 'redflags',
  ),

  /// TS A_rf_walk4Now (single yes/barely/no)
  QuestionDef(
    questionId: 'ankle.redflags.walk4StepsNow',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'ankle.redflags.walk4StepsNow',
    required: true,
    contributesToTriage: true,
    options: const [
      OptionDef(id: 'walk4.yes', labelKey: 'walk4.yes'),
      OptionDef(id: 'walk4.barely', labelKey: 'walk4.barely'),
      OptionDef(id: 'walk4.no', labelKey: 'walk4.no'),
    ],
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'ankle.redflags.hotRedFeverish',
    valueType: QuestionValueType.boolType,
    promptKey: 'ankle.redflags.hotRedFeverish',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'ankle.redflags.calfHotTight',
    valueType: QuestionValueType.boolType,
    promptKey: 'ankle.redflags.calfHotTight',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  /// TS A_rf_tiptoes
  QuestionDef(
    questionId: 'ankle.redflags.tiptoes',
    valueType: QuestionValueType.boolType,
    promptKey: 'ankle.redflags.tiptoes',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  /// TS A_rf_highSwelling
  QuestionDef(
    questionId: 'ankle.redflags.highSwelling',
    valueType: QuestionValueType.boolType,
    promptKey: 'ankle.redflags.highSwelling',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  // -------------------------------------------------------------------------
  // HISTORY (TS: A_mech, A_timeSince, A_onsetStyle)
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'ankle.history.mechanism',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'ankle.history.mechanism',
    required: true,
    options: const [
      OptionDef(id: 'mechanism.inversionRoll', labelKey: 'mechanism.inversionRoll'),
      OptionDef(id: 'mechanism.footFixedTwist', labelKey: 'mechanism.footFixedTwist'),
      OptionDef(id: 'mechanism.hardLanding', labelKey: 'mechanism.hardLanding'),
      OptionDef(id: 'mechanism.gradual', labelKey: 'mechanism.gradual'),
    ],
    domain: 'history',
  ),

  QuestionDef(
    questionId: 'ankle.history.timeSinceStart',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'ankle.history.timeSinceStart',
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
    questionId: 'ankle.history.onsetStyle',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'ankle.history.onsetStyle',
    required: true,
    options: const [
      OptionDef(id: 'onset.explosive', labelKey: 'onset.explosive'),
      OptionDef(id: 'onset.creeping', labelKey: 'onset.creeping'),
      OptionDef(id: 'onset.recurrent', labelKey: 'onset.recurrent'),
    ],
    domain: 'history',
  ),

  // -------------------------------------------------------------------------
  // SYMPTOMS / SITES (TS: A_painSite)
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'ankle.symptoms.painSite',
    valueType: QuestionValueType.multiChoice,
    promptKey: 'ankle.symptoms.painSite',
    required: true,
    options: const [
      OptionDef(id: 'painSite.lateralATFL', labelKey: 'painSite.lateralATFL'),
      OptionDef(id: 'painSite.syndesmosisHigh', labelKey: 'painSite.syndesmosisHigh'),
      OptionDef(id: 'painSite.achilles', labelKey: 'painSite.achilles'),
      OptionDef(id: 'painSite.plantar', labelKey: 'painSite.plantar'),
      OptionDef(id: 'painSite.midfoot', labelKey: 'painSite.midfoot'),
    ],
    domain: 'symptoms',
  ),

  // -------------------------------------------------------------------------
  // FUNCTION LOAD (TS: A_loadAggs + A_instability)
  // -------------------------------------------------------------------------

  QuestionDef(
    questionId: 'ankle.function.loadAggravators',
    valueType: QuestionValueType.multiChoice,
    promptKey: 'ankle.function.loadAggravators',
    required: false, // ✅ not required
    options: const [
      OptionDef(id: 'load.walkFlat', labelKey: 'load.walkFlat'),
      OptionDef(id: 'load.stairsHillsTiptoe', labelKey: 'load.stairsHillsTiptoe'),
      OptionDef(id: 'load.cuttingLanding', labelKey: 'load.cuttingLanding'),
      OptionDef(id: 'load.firstStepsWorse', labelKey: 'load.firstStepsWorse'),
      OptionDef(id: 'load.throbsAtRest', labelKey: 'load.throbsAtRest'),
      OptionDef(id: 'load.none', labelKey: 'load.none'),
    ],
    domain: 'function',
  ),

  QuestionDef(
    questionId: 'ankle.function.instability',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'ankle.function.instability',
    required: true,
    options: const [
      OptionDef(id: 'instability.never', labelKey: 'instability.never'),
      OptionDef(id: 'instability.sometimes', labelKey: 'instability.sometimes'),
      OptionDef(id: 'instability.often', labelKey: 'instability.often'),
    ],
    domain: 'function',
  ),

  // Narrative (not used by TS but useful clinically)
  QuestionDef(
    questionId: 'ankle.history.additionalInfo',
    valueType: QuestionValueType.textType,
    promptKey: 'ankle.history.additionalInfo',
    required: false,
    domain: 'history',
  ),
];
