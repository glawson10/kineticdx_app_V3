import 'package:kineticdx_app_v3/preassessment/domain/flow_definition.dart';
import 'elbow_questions_v1.dart';

final FlowDefinition elbowFlowV1 = FlowDefinition(
  flowId: 'elbow',
  flowVersion: 1,
  titleKey: 'elbow.title',
  descriptionKey: 'elbow.description',
  questions: elbowQuestionsV1,

  keyAnswerIds: const [
    // Safety
    'elbow.redflags.trauma',
    'elbow.redflags.injuryForce',
    'elbow.redflags.rapidSwelling',
    'elbow.redflags.visibleDeformity',
    'elbow.redflags.canStraighten',
    'elbow.redflags.fever',
    'elbow.redflags.infectionRisk',
    'elbow.redflags.hotSwollenNoFever',
    'elbow.redflags.neuroDeficit',

    // Differential drivers
    'elbow.history.onset',
    'elbow.symptoms.painLocation',
    'elbow.symptoms.grippingPain',
    'elbow.symptoms.stiffness',
    'elbow.symptoms.swelling',
    'elbow.symptoms.swellingAfterActivity',
    'elbow.symptoms.clickSnap',
    'elbow.symptoms.catching',
    'elbow.symptoms.morningStiffness',
    'elbow.symptoms.popAnterior',
    'elbow.symptoms.forearmThumbSidePain',
    'elbow.symptoms.paraUlnar',
    'elbow.symptoms.paraThumbIndex',
    'elbow.symptoms.neckRadiation',
    'elbow.symptoms.pronationPain',
    'elbow.symptoms.resistedExtensionPain',
    'elbow.symptoms.throwValgusPain',
    'elbow.symptoms.posteromedialEndRangeExtensionPain',
    'elbow.function.aggravators',

    // Patient experience
    'elbow.pain.worst24h',
    'elbow.function.dayImpact',
  ],
)..assertKeyAnswersValid();
