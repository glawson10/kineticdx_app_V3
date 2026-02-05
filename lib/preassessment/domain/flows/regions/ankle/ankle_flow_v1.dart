import 'package:kineticdx_app_v3/preassessment/domain/flow_definition.dart';
import 'ankle_questions_v1.dart';

final FlowDefinition ankleFlowV1 = FlowDefinition(
  flowId: 'ankle',
  flowVersion: 1,
  titleKey: 'ankle.title',
  descriptionKey: 'ankle.description',
  questions: ankleQuestionsV1,

  keyAnswerIds: const [
    // Red flags
    'ankle.redflags.fromFallTwistLanding',
    'ankle.redflags.followUps',
    'ankle.redflags.walk4StepsNow',
    'ankle.redflags.hotRedFeverish',
    'ankle.redflags.calfHotTight',
    'ankle.redflags.tiptoes',
    'ankle.redflags.highSwelling',

    // Key differential drivers
    'ankle.history.mechanism',
    'ankle.history.timeSinceStart',
    'ankle.history.onsetStyle',
    'ankle.symptoms.painSite',
    'ankle.function.loadAggravators',
    'ankle.function.instability',

    // Patient experience
    'ankle.pain.worst24h',
    'ankle.function.dayImpact',
  ],
)..assertKeyAnswersValid();
