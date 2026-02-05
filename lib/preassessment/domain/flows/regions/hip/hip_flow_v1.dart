import 'package:kineticdx_app_v3/preassessment/domain/flow_definition.dart';
import 'hip_questions_v1.dart';

final FlowDefinition hipFlowV1 = FlowDefinition(
  flowId: 'hip',
  flowVersion: 1,
  titleKey: 'hip.title',
  descriptionKey: 'hip.description',
  questions: hipQuestionsV1,

  keyAnswerIds: const [
    // Triage (scorer-aligned)
    'hip.redflags.highEnergyTrauma',
    'hip.redflags.fallImpact',
    'hip.redflags.feverUnwell',
    'hip.redflags.tinyMovementAgony',
    'hip.redflags.under16NewLimp',
    'hip.redflags.historyOfCancer',
    'hip.redflags.unableToWeightBear',
    'hip.redflags.amberRisks',

    // Scoring drivers
    'hip.history.onset',
    'hip.context.side',
    'hip.symptoms.painLocation',
    'hip.symptoms.aggravators',
    'hip.symptoms.sleep',
    'hip.function.gaitAbility',

    // Key additional discriminators
    'hip.history.dysplasiaHistory',
    'hip.history.hypermobilityHistory',
    'hip.symptoms.pinsNeedles',
    'hip.symptoms.coughStrain',
    'hip.symptoms.reproducibleSnapping',
    'hip.symptoms.sitBonePain',
    'hip.symptoms.irritabilityOn',
    'hip.symptoms.irritabilityOff',

    // Patient experience
    'hip.pain.worst24h',
    'hip.function.dayImpact',
  ],
)..assertKeyAnswersValid();
