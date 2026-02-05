import 'package:kineticdx_app_v3/preassessment/domain/flow_definition.dart';
import 'wrist_questions_v1.dart';

final FlowDefinition wristFlowV1 = FlowDefinition(
  flowId: 'wrist',
  flowVersion: 1,
  titleKey: 'wrist.title',
  descriptionKey: 'wrist.description',
  questions: wristQuestionsV1,

  keyAnswerIds: const [
    // Triage-driving
    'wrist.redflags.systemic',
    'wrist.redflags.acuteInjury',
    'wrist.redflags.injuryCluster',

    // Differential-driving
    'wrist.symptoms.zone',
    'wrist.history.onset',
    'wrist.history.mechanism',
    'wrist.symptoms.aggravators',
    'wrist.symptoms.features',
    'wrist.function.weightBear',
    'wrist.context.risks',
    'wrist.context.side',
  ],
)..assertKeyAnswersValid();
