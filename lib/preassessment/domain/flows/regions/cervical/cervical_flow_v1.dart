import 'package:kineticdx_app_v3/preassessment/domain/flow_definition.dart';
import 'cervical_questions_v1.dart';

final FlowDefinition cervicalFlowV1 = FlowDefinition(
  flowId: 'cervical',
  flowVersion: 1,
  titleKey: 'region.cervical',
  descriptionKey: 'region.cervical.description',
  questions: cervicalQuestionsV1,

  /// Key answers:
  /// - used for summary / validation / quick review
  /// - ALSO (in many flows) used to emphasize "safety first"
  ///
  /// Put red flags first to align with Page 1 = Safety screen.
  keyAnswerIds: const [
    // -----------------------------------------------------------------------
    // PAGE 1 — RED FLAGS / SAFETY (FIRST)
    // -----------------------------------------------------------------------
    'cervical.redflags.age65plus',
    'cervical.redflags.highSpeedCrash',
    'cervical.redflags.majorTrauma',
    'cervical.redflags.paresthesiaPostIncident',
    'cervical.redflags.unableWalkImmediately',
    'cervical.redflags.immediateNeckPain',
    'cervical.redflags.rotationLt45Both',

    // Neuro / myelopathy risk
    'cervical.redflags.widespreadNeuroDeficit',
    'cervical.redflags.progressiveNeurology',
    'cervical.redflags.armWeakness',
    'cervical.redflags.balanceOrWalkingIssues',
    'cervical.redflags.handClumsiness',
    'cervical.redflags.bowelBladderChange',

    // Inflammatory/systemic & vascular risk
    'cervical.redflags.nightPain',
    'cervical.redflags.morningStiffnessOver30min',
    'cervical.redflags.visualDisturbance',
    'cervical.redflags.cadCluster',

    // -----------------------------------------------------------------------
    // CORE SCORING / CLINICAL CONTEXT
    // -----------------------------------------------------------------------
    'cervical.pain.worst24h',
    'cervical.function.dayImpact',
  ],
)..assertKeyAnswersValid();
