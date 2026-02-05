import 'package:kineticdx_app_v3/preassessment/domain/flow_definition.dart';
import 'thoracic_questions_v1.dart';

final FlowDefinition thoracicFlowV1 = FlowDefinition(
  flowId: 'thoracic',
  flowVersion: 1,
  titleKey: 'thoracic.title',
  descriptionKey: 'thoracic.description',
  questions: thoracicQuestionsV1,

  keyAnswerIds: const [
    // Triage drivers
    'thoracic.redflags.trauma',
    'thoracic.redflags.redCluster',
    'thoracic.redflags.neuro',
    'thoracic.symptoms.restPattern',
    'thoracic.symptoms.breathProvocation',
    'thoracic.pain.now',

    // Differential drivers
    'thoracic.history.onset',
    'thoracic.symptoms.location',
    'thoracic.symptoms.worse',
    'thoracic.symptoms.better',
    'thoracic.symptoms.irritability',
    'thoracic.symptoms.sleep',
    'thoracic.symptoms.band',
  ],
)..assertKeyAnswersValid();
