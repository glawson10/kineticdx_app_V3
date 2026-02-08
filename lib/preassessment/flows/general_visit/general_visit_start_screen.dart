import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:kineticdx_app_v3/preassessment/state/intake_draft_controller.dart';
import 'package:kineticdx_app_v3/preassessment/domain/answer_value.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flow_definition.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/general_visit/general_visit_flow_v1.dart';
import 'package:kineticdx_app_v3/preassessment/domain/labels/preassessment_label_resolver.dart';

import 'package:kineticdx_app_v3/preassessment/widgets/question_widgets/bool_question.dart';
import 'package:kineticdx_app_v3/preassessment/widgets/question_widgets/multi_choice_question.dart';
import 'package:kineticdx_app_v3/preassessment/widgets/question_widgets/single_choice_question.dart';
import 'package:kineticdx_app_v3/preassessment/widgets/question_widgets/slider_question.dart';
import 'package:kineticdx_app_v3/preassessment/widgets/question_widgets/text_question.dart';

import 'package:kineticdx_app_v3/preassessment/flows/review/review_screen.dart';
import 'package:kineticdx_app_v3/preassessment/flows/general_visit/general_visit_v1_maps.dart';
import 'package:kineticdx_app_v3/preassessment/flows/general_visit/general_visit_body_areas_question.dart';

/// General visit questionnaire (generalVisit.v1)
///
/// - Renders all schema-defined generalVisit.v1 questions using the shared,
///   schema-driven question widgets.
/// - Writes answers into IntakeDraftController via setAnswer(questionId, value).
/// - Enforces required-question validation before progression.
/// - On success, navigates directly to ReviewScreen (no region flow required).
class GeneralVisitStartScreen extends StatefulWidget {
  const GeneralVisitStartScreen({super.key});

  @override
  State<GeneralVisitStartScreen> createState() =>
      _GeneralVisitStartScreenState();
}

class _GeneralVisitStartScreenState extends State<GeneralVisitStartScreen> {
  /// questionId -> errorCode (from QuestionDef.validate)
  Map<String, String> _errors = {};

  FlowDefinition get _flow => generalVisitFlowV1;

  /// Localisation hook for this screen.
  ///
  /// Order:
  /// - generalVisit-specific prompts
  /// - generalVisit option label maps
  /// - shared preassessment labels (common.*, validation.*, etc.)
  String _t(String key) {
    // Question prompts / titles
    const prompts = <String, String>{
      'generalVisit.title': 'Visit context questionnaire',
      'generalVisit.description':
          'Tell us a bit about what brought you to this visit. '
              'These answers help your clinician prepare — they are not a diagnosis.',
      'generalVisit.goals.reasonForVisit': 'What made you book this visit?',
      'generalVisit.meta.concernClarity':
          'Is this one main concern or multiple?',
      'generalVisit.history.bodyAreas': 'Which areas are involved?',
      'generalVisit.function.primaryImpact': 'What is the main impact for you?',
      'generalVisit.function.limitedActivities':
          'Which activities are currently affected? (optional)',
      'generalVisit.history.duration': 'How long has this been going on?',
      'generalVisit.goals.visitIntent': 'What would you like from the visit?',
    };

    final promptHit = prompts[key];
    if (promptHit != null) return promptHit;

    // Option labels from canonical maps (optionId -> label).
    final optLabel = gvConcernClarityLabels[key] ??
        gvBodyAreaLabels[key] ??
        gvPrimaryImpactLabels[key] ??
        gvLimitedActivityLabels[key] ??
        gvDurationLabels[key] ??
        gvVisitIntentLabels[key];
    if (optLabel != null) return optLabel;

    // Shared labels / validation / common.* via central resolver.
    return resolvePreassessmentLabel('generalVisit', key);
  }

  void _setAnswer(
    IntakeDraftController draft,
    String questionId,
    AnswerValue? value,
  ) {
    setState(() {
      draft.setAnswer(questionId, value);
      _errors.remove(questionId);
    });
  }

  /// Validates all questions in the generalVisit flow.
  ///
  /// Returns true if valid; otherwise updates _errors and shows a snackbar.
  bool _validateAll(IntakeDraftController draft) {
    final answers = draft.answers;
    final errors = <String, String>{};

    for (final q in _flow.questions) {
      final err = q.validate(answers[q.questionId]);
      if (err != null) {
        errors[q.questionId] = err;
      }
    }

    setState(() => _errors = errors);

    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('preassessment.validation.fixErrors'))),
      );
      return false;
    }

    return true;
  }

  Widget _buildQuestionTile({
    required QuestionDef q,
    required AnswerValue? value,
    required IntakeDraftController draft,
  }) {
    final errKey = _errors[q.questionId];
    final errorText =
        errKey == null ? null : _t('preassessment.validation.$errKey');

    // Custom renderer for bodyAreas: reuse the body-map style selector and
    // write into the existing multiChoice question.
    if (q.questionId == 'generalVisit.history.bodyAreas') {
      return GeneralVisitBodyAreasQuestion(
        q: q,
        value: value,
        onChanged: (v) => _setAnswer(draft, q.questionId, v),
        errorText: errorText,
        t: _t,
      );
    }

    switch (q.valueType) {
      case QuestionValueType.boolType:
        return BoolQuestion(
          q: q,
          value: value,
          onChanged: (v) => _setAnswer(draft, q.questionId, v),
          errorText: errorText,
          t: _t,
        );

      case QuestionValueType.singleChoice:
        return SingleChoiceQuestion(
          q: q,
          value: value,
          onChanged: (v) => _setAnswer(draft, q.questionId, v),
          errorText: errorText,
          t: _t,
        );

      case QuestionValueType.multiChoice:
        return MultiChoiceQuestion(
          q: q,
          value: value,
          onChanged: (v) => _setAnswer(draft, q.questionId, v),
          errorText: errorText,
          t: _t,
        );

      case QuestionValueType.intType:
      case QuestionValueType.numType:
        return SliderQuestion(
          q: q,
          value: value,
          onChanged: (v) => _setAnswer(draft, q.questionId, v),
          errorText: errorText,
          t: _t,
        );

      case QuestionValueType.textType:
        return TextQuestion(
          q: q,
          value: value,
          onChanged: (v) => _setAnswer(draft, q.questionId, v),
          errorText: errorText,
          t: _t,
        );

      case QuestionValueType.dateType:
      case QuestionValueType.mapType:
        // Explicitly flag unsupported types rather than inventing new UI.
        return Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            'Unsupported question type in generalVisit renderer: ${q.valueType}',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        );
    }
  }

  void _continue(IntakeDraftController draft) {
    final ok = _validateAll(draft);
    if (!ok) return;

    // Route directly to review; ReviewScreen will submit generalVisit using
    // the same IntakeDraftController answers map.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReviewScreen(t: _t),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = context.watch<IntakeDraftController>();
    final answers = draft.answers;

    final title = _t(_flow.titleKey);
    final descKey = _flow.descriptionKey;

    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottomInset),
        children: [
          if (descKey != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _t(descKey),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),

          // Questions in schema order
          ..._flow.questions.map((q) {
            final value = answers[q.questionId];
            return _buildQuestionTile(
              q: q,
              value: value,
              draft: draft,
            );
          }),

          const SizedBox(height: 18),
          SizedBox(
            height: 44,
            child: ElevatedButton(
              onPressed: () => _continue(draft),
              child: Text(_t('common.continue')),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Questions marked with * are required.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
