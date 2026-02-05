import 'package:kineticdx_app_v3/preassessment/domain/flow_definition.dart';
import 'knee_questions_v1.dart';

final FlowDefinition kneeFlowV1 = FlowDefinition(
  flowId: 'knee',
  flowVersion: 1,
  titleKey: 'knee.title',
  descriptionKey: 'knee.description',
  questions: kneeQuestionsV1,

  keyAnswerIds: const [
    // -----------------------------------------------------------------------
    // SAFETY / TRIAGE DRIVERS (ASKED FIRST ON RED FLAGS PAGE)
    // -----------------------------------------------------------------------
    'knee.redflags.highEnergyTrauma',
    'knee.redflags.lockedKnee',
    'knee.redflags.hotSwollenJoint',
    'knee.redflags.feverUnwell',
    'knee.redflags.unableToWeightBear',
    'knee.redflags.newNumbFoot',
    'knee.redflags.coldPaleFoot',
    'knee.redflags.historyOfCancer',

    // -----------------------------------------------------------------------
    // DIFFERENTIAL DRIVERS (SCORER-CRITICAL)
    // -----------------------------------------------------------------------
    'knee.history.onset',
    'knee.history.feltPop',
    'knee.history.rapidSwellingUnder2h',

    'knee.symptoms.painLocation',
    'knee.symptoms.swelling',
    'knee.symptoms.givingWay',
    'knee.symptoms.clickingLocking',
    'knee.symptoms.blockedExtension',
    'knee.symptoms.tendonFocus',
    'knee.symptoms.morningStiffness',
    'knee.symptoms.lateralRunPain',

    'knee.function.aggravators',

    // -----------------------------------------------------------------------
    // PATIENT EXPERIENCE (GOOD FOR NARRATIVE/SUMMARY)
    // -----------------------------------------------------------------------
    'knee.pain.worst24h',
    'knee.pain.now',
    'knee.function.dayImpact',
    'knee.history.additionalInfo',
  ],
)..assertKeyAnswersValid();
