import 'package:kineticdx_app_v3/preassessment/domain/flow_definition.dart';
import 'shoulder_questions_v1.dart';

final FlowDefinition shoulderFlowV1 = FlowDefinition(
  flowId: 'shoulder',
  flowVersion: 1,
  titleKey: 'shoulder.title',
  descriptionKey: 'shoulder.description',
  questions: shoulderQuestionsV1,

  keyAnswerIds: const [
    // Triage drivers
    'shoulder.redflags.feverOrHotRedJoint',
    'shoulder.redflags.deformityAfterInjury',
    'shoulder.redflags.newNeuroSymptoms',
    'shoulder.redflags.constantUnrelentingPain',
    'shoulder.redflags.cancerHistoryOrWeightLoss',
    'shoulder.redflags.traumaHighEnergy',
    'shoulder.redflags.canActiveElevateToShoulderHeight',

    // High-value differential drivers
    'shoulder.history.onset',
    'shoulder.symptoms.painArea',
    'shoulder.symptoms.nightPain',
    'shoulder.symptoms.overheadAggravates',
    'shoulder.symptoms.weakness',
    'shoulder.symptoms.stiffness',
    'shoulder.symptoms.clicking',
    'shoulder.symptoms.neckInvolved',
    'shoulder.symptoms.handNumbness',
    'shoulder.symptoms.tenderSpot',
    'shoulder.function.limits',

    // Patient experience
    'shoulder.pain.worst24h',
    'shoulder.function.dayImpact',
  ],
)..assertKeyAnswersValid();
