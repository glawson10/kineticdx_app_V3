import 'package:kineticdx_app_v3/preassessment/domain/flow_definition.dart';

/// ---------------------------------------------------------------------------
/// generalVisit.v1 — General questionnaire (visit context)
/// ---------------------------------------------------------------------------
///
/// This is a single-screen, non-region flow that captures broad visit context:
/// - Reason for visit (free text)
/// - Clarity of concern (single)
/// - Broad body areas involved (multi)
/// - Primary impact (single)
/// - Activities affected (multi, optional)
/// - Duration (single)
/// - Visit intent (multi)
///
/// QuestionIds and optionIds mirror the backend renderer:
/// functions/src/preassessment/renderers/generalVisitV1Renderer.ts
///
/// IMPORTANT:
/// - Do NOT change questionId meanings or value types without bumping
///   flowVersion and updating backend renderers.

final FlowDefinition generalVisitFlowV1 = FlowDefinition(
  flowId: 'generalVisit',
  flowVersion: 1,
  titleKey: 'generalVisit.title',
  descriptionKey: 'generalVisit.description',
  questions: const [
    // -----------------------------------------------------------------------
    // Core reason
    // -----------------------------------------------------------------------
    QuestionDef(
      questionId: 'generalVisit.goals.reasonForVisit',
      valueType: QuestionValueType.textType,
      promptKey: 'generalVisit.goals.reasonForVisit',
      required: true,
      contributesToTriage: false,
      domain: 'goals',
    ),

    // -----------------------------------------------------------------------
    // High-level context
    // -----------------------------------------------------------------------
    QuestionDef(
      questionId: 'generalVisit.meta.concernClarity',
      valueType: QuestionValueType.singleChoice,
      promptKey: 'generalVisit.meta.concernClarity',
      required: true,
      options: [
        OptionDef(id: 'concern.single', labelKey: 'concern.single'),
        OptionDef(id: 'concern.multiple', labelKey: 'concern.multiple'),
        OptionDef(id: 'concern.unsure', labelKey: 'concern.unsure'),
      ],
      domain: 'meta',
    ),

    QuestionDef(
      questionId: 'generalVisit.history.bodyAreas',
      valueType: QuestionValueType.multiChoice,
      promptKey: 'generalVisit.history.bodyAreas',
      required: true,
      options: [
        OptionDef(id: 'area.neck', labelKey: 'area.neck'),
        OptionDef(id: 'area.upperBack', labelKey: 'area.upperBack'),
        OptionDef(id: 'area.lowerBack', labelKey: 'area.lowerBack'),
        OptionDef(id: 'area.shoulder', labelKey: 'area.shoulder'),
        OptionDef(id: 'area.elbow', labelKey: 'area.elbow'),
        OptionDef(id: 'area.wristHand', labelKey: 'area.wristHand'),
        OptionDef(id: 'area.hip', labelKey: 'area.hip'),
        OptionDef(id: 'area.knee', labelKey: 'area.knee'),
        OptionDef(id: 'area.ankleFoot', labelKey: 'area.ankleFoot'),
        OptionDef(id: 'area.multiple', labelKey: 'area.multiple'),
        OptionDef(id: 'area.general', labelKey: 'area.general'),
      ],
      domain: 'history',
    ),

    // -----------------------------------------------------------------------
    // Impact / function
    // -----------------------------------------------------------------------
    QuestionDef(
      questionId: 'generalVisit.function.primaryImpact',
      valueType: QuestionValueType.singleChoice,
      promptKey: 'generalVisit.function.primaryImpact',
      required: true,
      options: [
        OptionDef(id: 'impact.work', labelKey: 'impact.work'),
        OptionDef(id: 'impact.sport', labelKey: 'impact.sport'),
        OptionDef(id: 'impact.sleep', labelKey: 'impact.sleep'),
        OptionDef(
          id: 'impact.dailyActivities',
          labelKey: 'impact.dailyActivities',
        ),
        OptionDef(
          id: 'impact.generalMovement',
          labelKey: 'impact.generalMovement',
        ),
        OptionDef(id: 'impact.unclear', labelKey: 'impact.unclear'),
      ],
      domain: 'function',
    ),

    QuestionDef(
      questionId: 'generalVisit.function.limitedActivities',
      valueType: QuestionValueType.multiChoice,
      promptKey: 'generalVisit.function.limitedActivities',
      required: false, // explicitly optional in renderer copy
      options: [
        OptionDef(id: 'activity.sitting', labelKey: 'activity.sitting'),
        OptionDef(id: 'activity.standing', labelKey: 'activity.standing'),
        OptionDef(id: 'activity.walking', labelKey: 'activity.walking'),
        OptionDef(id: 'activity.lifting', labelKey: 'activity.lifting'),
        OptionDef(id: 'activity.exercise', labelKey: 'activity.exercise'),
        OptionDef(id: 'activity.workTasks', labelKey: 'activity.workTasks'),
        OptionDef(id: 'activity.sleep', labelKey: 'activity.sleep'),
        OptionDef(id: 'activity.other', labelKey: 'activity.other'),
      ],
      domain: 'function',
    ),

    // -----------------------------------------------------------------------
    // Duration / intent
    // -----------------------------------------------------------------------
    QuestionDef(
      questionId: 'generalVisit.history.duration',
      valueType: QuestionValueType.singleChoice,
      promptKey: 'generalVisit.history.duration',
      required: true,
      options: [
        OptionDef(id: 'duration.days', labelKey: 'duration.days'),
        OptionDef(id: 'duration.weeks', labelKey: 'duration.weeks'),
        OptionDef(id: 'duration.months', labelKey: 'duration.months'),
        OptionDef(id: 'duration.years', labelKey: 'duration.years'),
        OptionDef(id: 'duration.unsure', labelKey: 'duration.unsure'),
      ],
      domain: 'history',
    ),

    QuestionDef(
      questionId: 'generalVisit.goals.visitIntent',
      valueType: QuestionValueType.multiChoice,
      promptKey: 'generalVisit.goals.visitIntent',
      required: true,
      options: [
        OptionDef(
          id: 'intent.understanding',
          labelKey: 'intent.understanding',
        ),
        OptionDef(
          id: 'intent.reassurance',
          labelKey: 'intent.reassurance',
        ),
        OptionDef(id: 'intent.guidance', labelKey: 'intent.guidance'),
        OptionDef(id: 'intent.nextSteps', labelKey: 'intent.nextSteps'),
        OptionDef(
          id: 'intent.returnToActivity',
          labelKey: 'intent.returnToActivity',
        ),
        OptionDef(id: 'intent.unsure', labelKey: 'intent.unsure'),
      ],
      domain: 'goals',
    ),
  ],

  // Key answers used in clinician review + list summaries.
  keyAnswerIds: const [
    'generalVisit.goals.reasonForVisit',
    'generalVisit.meta.concernClarity',
    'generalVisit.history.bodyAreas',
    'generalVisit.function.primaryImpact',
    'generalVisit.function.limitedActivities',
    'generalVisit.history.duration',
    'generalVisit.goals.visitIntent',
  ],
)..assertKeyAnswersValid();
