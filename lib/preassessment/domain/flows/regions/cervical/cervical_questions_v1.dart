import 'package:kineticdx_app_v3/preassessment/domain/flow_definition.dart';

final List<QuestionDef> cervicalQuestionsV1 = [
  // ---------------------------------------------------------------------------
  // PAGE 1 — RED FLAGS / SAFETY (ASK FIRST)
  // ---------------------------------------------------------------------------

  // Canadian C-spine / trauma risk factors
  QuestionDef(
    questionId: 'cervical.redflags.age65plus',
    valueType: QuestionValueType.boolType,
    promptKey: 'cervical.redflags.age65plus',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'cervical.redflags.highSpeedCrash',
    valueType: QuestionValueType.boolType,
    promptKey: 'cervical.redflags.highSpeedCrash',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  // Keep existing (already in your file)
  QuestionDef(
    questionId: 'cervical.redflags.majorTrauma',
    valueType: QuestionValueType.boolType,
    promptKey: 'cervical.redflags.majorTrauma',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'cervical.redflags.paresthesiaPostIncident',
    valueType: QuestionValueType.boolType,
    promptKey: 'cervical.redflags.paresthesiaPostIncident',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'cervical.redflags.unableWalkImmediately',
    valueType: QuestionValueType.boolType,
    promptKey: 'cervical.redflags.unableWalkImmediately',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'cervical.redflags.immediateNeckPain',
    valueType: QuestionValueType.boolType,
    promptKey: 'cervical.redflags.immediateNeckPain',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'cervical.redflags.rotationLt45Both',
    valueType: QuestionValueType.boolType,
    promptKey: 'cervical.redflags.rotationLt45Both',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  // Neuro / myelopathy style flags
  // Keep existing (already in your file)
  QuestionDef(
    questionId: 'cervical.redflags.progressiveNeurology',
    valueType: QuestionValueType.boolType,
    promptKey: 'cervical.redflags.progressiveNeurology',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  // NEW: separate concept for "widespread neuro deficit" (engine expects this distinctly)
  QuestionDef(
    questionId: 'cervical.redflags.widespreadNeuroDeficit',
    valueType: QuestionValueType.boolType,
    promptKey: 'cervical.redflags.widespreadNeuroDeficit',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  // Keep existing (already in your file)
  QuestionDef(
    questionId: 'cervical.redflags.armWeakness',
    valueType: QuestionValueType.boolType,
    promptKey: 'cervical.redflags.armWeakness',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  // Keep existing; can map to gait unsteady in adapter if your wording matches
  QuestionDef(
    questionId: 'cervical.redflags.balanceOrWalkingIssues',
    valueType: QuestionValueType.boolType,
    promptKey: 'cervical.redflags.balanceOrWalkingIssues',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'cervical.redflags.handClumsiness',
    valueType: QuestionValueType.boolType,
    promptKey: 'cervical.redflags.handClumsiness',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  // Keep existing (already in your file)
  QuestionDef(
    questionId: 'cervical.redflags.bowelBladderChange',
    valueType: QuestionValueType.boolType,
    promptKey: 'cervical.redflags.bowelBladderChange',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  // Inflammatory/systemic style flags
  // NEW: dedicated night pain (don’t overload with “constant pain”)
  QuestionDef(
    questionId: 'cervical.redflags.nightPain',
    valueType: QuestionValueType.boolType,
    promptKey: 'cervical.redflags.nightPain',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  QuestionDef(
    questionId: 'cervical.redflags.morningStiffnessOver30min',
    valueType: QuestionValueType.boolType,
    promptKey: 'cervical.redflags.morningStiffnessOver30min',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  // Keep existing (already in your file) — multi-select with none-of-the-above allowed
  QuestionDef(
    questionId: 'cervical.redflags.systemicSymptoms',
    valueType: QuestionValueType.multiChoice,
    promptKey: 'cervical.redflags.systemicSymptoms',
    required: false, // none-of-the-above allowed
    contributesToTriage: true,
    options: const [
      OptionDef(id: 'systemic.fever', labelKey: 'systemic.fever'),
      OptionDef(
          id: 'systemic.unexplainedWeightLoss',
          labelKey: 'systemic.unexplainedWeightLoss'),
      OptionDef(id: 'systemic.feelsUnwell', labelKey: 'systemic.feelsUnwell'),
    ],
    domain: 'redflags',
  ),

  // Vascular / CAD cluster
  QuestionDef(
    questionId: 'cervical.redflags.visualDisturbance',
    valueType: QuestionValueType.boolType,
    promptKey: 'cervical.redflags.visualDisturbance',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  // NEW: explicit CAD cluster yes/no (define in copy/labels what “cluster” means)
  QuestionDef(
    questionId: 'cervical.redflags.cadCluster',
    valueType: QuestionValueType.boolType,
    promptKey: 'cervical.redflags.cadCluster',
    required: true,
    contributesToTriage: true,
    domain: 'redflags',
  ),

  // ---------------------------------------------------------------------------
  // PAGE 2 — PAIN
  // ---------------------------------------------------------------------------

  QuestionDef(
    questionId: 'cervical.pain.now',
    valueType: QuestionValueType.intType,
    promptKey: 'cervical.pain.now',
    required: true,
    numeric: NumericConstraints(min: 0, max: 10),
    domain: 'pain',
  ),

  QuestionDef(
    questionId: 'cervical.pain.worst24h',
    valueType: QuestionValueType.intType,
    promptKey: 'cervical.pain.worst24h',
    required: true,
    numeric: NumericConstraints(min: 0, max: 10),
    domain: 'pain',
  ),

  // ---------------------------------------------------------------------------
  // PAGE 3 — HISTORY / CONTEXT
  // ---------------------------------------------------------------------------

  QuestionDef(
    questionId: 'cervical.history.onset',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'cervical.history.onset',
    required: true,
    options: const [
      OptionDef(id: 'onset.sudden', labelKey: 'onset.sudden'),
      OptionDef(id: 'onset.gradual', labelKey: 'onset.gradual'),
      OptionDef(id: 'onset.unsure', labelKey: 'onset.unsure'),
    ],
    domain: 'history',
  ),

  QuestionDef(
    questionId: 'cervical.history.timeSinceStart',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'cervical.history.timeSinceStart',
    required: true,
    options: const [
      OptionDef(id: 'time.lt48h', labelKey: 'time.lt48h'),
      OptionDef(id: 'time.2_14d', labelKey: 'time.2_14d'),
      OptionDef(id: 'time.2_6wk', labelKey: 'time.2_6wk'),
      OptionDef(id: 'time.gt6wk', labelKey: 'time.gt6wk'),
    ],
    domain: 'history',
  ),

  // Optional clinical narrative
  QuestionDef(
    questionId: 'cervical.history.additionalInfo',
    valueType: QuestionValueType.textType,
    promptKey: 'cervical.history.additionalInfo',
    required: false,
    domain: 'history',
  ),

  // ---------------------------------------------------------------------------
  // PAGE 4 — SYMPTOMS (SCORING INPUTS)
  // ---------------------------------------------------------------------------

  // Pain distribution (engine expects central/one_side/both_sides)
  QuestionDef(
    questionId: 'cervical.symptoms.painLocation',
    valueType: QuestionValueType.singleChoice,
    promptKey: 'cervical.symptoms.painLocation',
    required: true,
    options: const [
      OptionDef(id: 'painLocation.central', labelKey: 'painLocation.central'),
      OptionDef(id: 'painLocation.oneSide', labelKey: 'painLocation.oneSide'),
      OptionDef(id: 'painLocation.bothSides', labelKey: 'painLocation.bothSides'),
    ],
    domain: 'symptoms',
  ),

  // Keep existing (already in your file)
  QuestionDef(
    questionId: 'cervical.symptoms.armSymptoms',
    valueType: QuestionValueType.multiChoice,
    promptKey: 'cervical.symptoms.armSymptoms',
    required: true,
    options: const [
      OptionDef(id: 'arm.numbness', labelKey: 'arm.numbness'),
      OptionDef(id: 'arm.tingling', labelKey: 'arm.tingling'),
      OptionDef(id: 'arm.weakness', labelKey: 'arm.weakness'),
      OptionDef(id: 'arm.none', labelKey: 'arm.none'),
    ],
    domain: 'symptoms',
  ),

  // NEW: explicit single booleans the scoring engine expects
  QuestionDef(
    questionId: 'cervical.symptoms.painIntoShoulder',
    valueType: QuestionValueType.boolType,
    promptKey: 'cervical.symptoms.painIntoShoulder',
    required: true,
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'cervical.symptoms.painBelowElbow',
    valueType: QuestionValueType.boolType,
    promptKey: 'cervical.symptoms.painBelowElbow',
    required: true,
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'cervical.symptoms.armTingling',
    valueType: QuestionValueType.boolType,
    promptKey: 'cervical.symptoms.armTingling',
    required: true,
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'cervical.symptoms.coughSneezeWorse',
    valueType: QuestionValueType.boolType,
    promptKey: 'cervical.symptoms.coughSneezeWorse',
    required: true,
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'cervical.symptoms.neckMovementWorse',
    valueType: QuestionValueType.boolType,
    promptKey: 'cervical.symptoms.neckMovementWorse',
    required: true,
    domain: 'symptoms',
  ),

  // Headache presence (keep existing)
  QuestionDef(
    questionId: 'cervical.symptoms.headache',
    valueType: QuestionValueType.boolType,
    promptKey: 'cervical.symptoms.headache',
    required: true,
    domain: 'symptoms',
  ),

  // NEW: headache modifiers (make required=false unless your engine supports conditional required)
  QuestionDef(
    questionId: 'cervical.symptoms.headacheOneSide',
    valueType: QuestionValueType.boolType,
    promptKey: 'cervical.symptoms.headacheOneSide',
    required: false,
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'cervical.symptoms.headacheWorseWithNeck',
    valueType: QuestionValueType.boolType,
    promptKey: 'cervical.symptoms.headacheWorseWithNeck',
    required: false,
    domain: 'symptoms',
  ),

  QuestionDef(
    questionId: 'cervical.symptoms.headacheBetterWithNeckCare',
    valueType: QuestionValueType.boolType,
    promptKey: 'cervical.symptoms.headacheBetterWithNeckCare',
    required: false,
    domain: 'symptoms',
  ),

  // Keep existing dizziness/visual screen item (still useful clinically),
  // but we now also ask explicit redflags.visualDisturbance above for scoring/triage mapping.
  QuestionDef(
    questionId: 'cervical.symptoms.dizzinessOrVisual',
    valueType: QuestionValueType.boolType,
    promptKey: 'cervical.symptoms.dizzinessOrVisual',
    required: true,
    domain: 'symptoms',
  ),

  // Keep existing symptom (still useful), but redflags.nightPain is now asked explicitly above.
  QuestionDef(
    questionId: 'cervical.symptoms.nightOrConstantPain',
    valueType: QuestionValueType.boolType,
    promptKey: 'cervical.symptoms.nightOrConstantPain',
    required: true,
    domain: 'symptoms',
  ),

  // ---------------------------------------------------------------------------
  // PAGE 5 — FUNCTION
  // ---------------------------------------------------------------------------

  QuestionDef(
    questionId: 'cervical.function.dayImpact',
    valueType: QuestionValueType.intType,
    promptKey: 'cervical.function.dayImpact',
    required: true,
    numeric: NumericConstraints(min: 0, max: 10),
    domain: 'function',
  ),
];
