import 'package:kineticdx_app_v3/preassessment/domain/flow_definition.dart';
import 'lumbar_questions_v1.dart';

/// ---------------------------------------------------------------------------
/// LUMBAR FLOW v1 — Registration (TS-aligned)
/// ---------------------------------------------------------------------------

final FlowDefinition lumbarFlowV1 = FlowDefinition(
  flowId: 'lumbar',
  flowVersion: 1,
  titleKey: 'lumbar.title',
  descriptionKey: 'lumbar.description',
  questions: lumbarQuestionsV1,

  /// Whitelist for clinician preview + future Phase 5 reference
  keyAnswerIds: const [
    // Red flags / triage
    'lumbar.redflags.bladderBowelChange',
    'lumbar.redflags.saddleAnaesthesia',
    'lumbar.redflags.progressiveWeakness',
    'lumbar.redflags.feverUnwell',
    'lumbar.redflags.historyOfCancer',
    'lumbar.redflags.recentTrauma',
    'lumbar.redflags.constantNightPain',

    // High-value scoring features
    'lumbar.context.ageBand',
    'lumbar.symptoms.painPattern',
    'lumbar.symptoms.whereLeg',
    'lumbar.symptoms.pinsNeedles',
    'lumbar.symptoms.numbness',
    'lumbar.symptoms.aggravators',
    'lumbar.symptoms.easers',
    'lumbar.function.gaitAbility',

    // Patient experience
    'lumbar.pain.now',
    'lumbar.pain.worst24h',
    'lumbar.function.dayImpact',
  ],
)..assertKeyAnswersValid();
