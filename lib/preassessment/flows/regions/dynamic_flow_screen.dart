// lib/preassessment/flows/regions/dynamic_flow_screen.dart
//
// ✅ Updated in full:
// - NO provider re-wrapping in navigation (prevents "used after disposed")
// - Removed nav_with_draft helper usage (not needed if your flow has a single provider owner)
// - Keeps 2-step (red flags → main) behavior + validation + per-question error text
// - Keeps default navigation to GoalsScreen via widget route
// - Adds back the step header card + progress indicator (nice UX)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/answer_value.dart';
import '../../domain/flow_definition.dart';
import '../../state/intake_draft_controller.dart';
import 'package:kineticdx_app_v3/preassessment/domain/flows/goals/goals_screen.dart';

import '../../widgets/question_widgets/bool_question.dart';
import '../../widgets/question_widgets/multi_choice_question.dart';
import '../../widgets/question_widgets/single_choice_question.dart';
import '../../widgets/question_widgets/slider_question.dart';
import '../../widgets/question_widgets/text_question.dart';

class DynamicFlowScreen extends StatefulWidget {
  final FlowDefinition flow;

  /// (Legacy) snapshot. We render from provider live state to avoid stale UI.
  final Map<String, AnswerValue> answers;

  /// Called when a question changes (writes to draft in parent).
  final void Function(String questionId, AnswerValue? value) onAnswerChanged;

  /// Localization hook (you’re using the central resolver via RegionSelectScreen).
  final String Function(String key) t;

  /// Called after final step passes validation.
  /// If null, DynamicFlowScreen navigates to GoalsScreen by default.
  final VoidCallback? onContinue;

  const DynamicFlowScreen({
    super.key,
    required this.flow,
    required this.answers,
    required this.onAnswerChanged,
    required this.t,
    this.onContinue,
  });

  @override
  State<DynamicFlowScreen> createState() => _DynamicFlowScreenState();
}

class _DynamicFlowScreenState extends State<DynamicFlowScreen> {
  /// 0 = red flags page, 1 = main questions page
  int _step = 0;

  /// questionId -> errorKey (from QuestionDef.validate)
  Map<String, String> _errors = {};

  @override
  void initState() {
    super.initState();
    widget.flow.assertKeyAnswersValid();

    // If there are no red flag questions, start on main questions.
    final hasRedFlags =
        widget.flow.questions.any((q) => (q.domain ?? '') == 'redflags');
    if (!hasRedFlags) _step = 1;
  }

  Map<String, AnswerValue> _liveAnswers(IntakeDraftController draft) {
    return draft.answers;
  }

  void _set(String qid, AnswerValue? v) {
    setState(() {
      widget.onAnswerChanged(qid, v);
      _errors.remove(qid);
    });
  }

  List<QuestionDef> _redFlagQuestions() {
    return widget.flow.questions
        .where((q) => (q.domain ?? '') == 'redflags')
        .toList();
  }

  List<QuestionDef> _mainQuestions() {
    return widget.flow.questions
        .where((q) => (q.domain ?? '') != 'redflags')
        .toList();
  }

  /// Validates a subset of questions.
  /// Returns true if ok; otherwise updates _errors and shows a snackbar.
  bool _validateSubset({
    required IntakeDraftController draft,
    required List<QuestionDef> questions,
  }) {
    final answers = _liveAnswers(draft);
    final errors = <String, String>{};

    for (final q in questions) {
      final err = q.validate(answers[q.questionId]);
      if (err != null) errors[q.questionId] = err;
    }

    setState(() => _errors = errors);

    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.t('preassessment.validation.fixErrors'))),
      );
      return false;
    }
    return true;
  }

  void _continue(IntakeDraftController draft) {
    final redFlags = _redFlagQuestions();
    final mainQs = _mainQuestions();

    // Step 0 → validate red flags
    if (_step == 0) {
      final ok = _validateSubset(draft: draft, questions: redFlags);
      if (!ok) return;

      setState(() {
        _errors = {};
        _step = 1;
      });
      return;
    }

    // Step 1 → validate main questions
    final okMain = _validateSubset(draft: draft, questions: mainQs);
    if (!okMain) return;

    // If red flags exist, ensure they’re still valid too (safe)
    if (redFlags.isNotEmpty) {
      final okRed = _validateSubset(draft: draft, questions: redFlags);
      if (!okRed) {
        setState(() => _step = 0);
        return;
      }
    }

    // Caller override
    if (widget.onContinue != null) {
      widget.onContinue!();
      return;
    }

    // ✅ Default: go to GoalsScreen with normal widget navigation.
    // DO NOT re-wrap IntakeDraftController here — the flow owner already provides it.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GoalsScreen(
          flow: widget.flow,
          t: widget.t,
        ),
      ),
    );
  }

  Widget _buildQuestionTile({
    required QuestionDef q,
    required AnswerValue? value,
  }) {
    final errKey = _errors[q.questionId];
    final errorText =
        errKey == null ? null : widget.t('preassessment.validation.$errKey');

    switch (q.valueType) {
      case QuestionValueType.boolType:
        return BoolQuestion(
          q: q,
          value: value,
          onChanged: (v) => _set(q.questionId, v),
          errorText: errorText,
          t: widget.t,
        );

      case QuestionValueType.singleChoice:
        return SingleChoiceQuestion(
          q: q,
          value: value,
          onChanged: (v) => _set(q.questionId, v),
          errorText: errorText,
          t: widget.t,
        );

      case QuestionValueType.multiChoice:
        return MultiChoiceQuestion(
          q: q,
          value: value,
          onChanged: (v) => _set(q.questionId, v),
          errorText: errorText,
          t: widget.t,
        );

      case QuestionValueType.intType:
      case QuestionValueType.numType:
        return SliderQuestion(
          q: q,
          value: value,
          onChanged: (v) => _set(q.questionId, v),
          errorText: errorText,
          t: widget.t,
        );

      case QuestionValueType.textType:
        return TextQuestion(
          q: q,
          value: value,
          onChanged: (v) => _set(q.questionId, v),
          errorText: errorText,
          t: widget.t,
        );

      case QuestionValueType.dateType:
      case QuestionValueType.mapType:
        return Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            'Unsupported question type in renderer: ${q.valueType}',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = context.watch<IntakeDraftController>();
    final answers = _liveAnswers(draft);

    final title = widget.t(widget.flow.titleKey);
    final descKey = widget.flow.descriptionKey;

    final redFlags = _redFlagQuestions();
    final mainQs = _mainQuestions();

    final showingRedFlags = (_step == 0 && redFlags.isNotEmpty);
    final questions = showingRedFlags ? redFlags : mainQs;

    final headerTitle = showingRedFlags
        ? 'Safety questions'
        : (redFlags.isNotEmpty ? 'Your symptoms' : 'Questions');

    final headerSubtitle = showingRedFlags
        ? 'Please answer these first. If any apply, we may advise earlier review.'
        : 'Answer as best you can. You can leave optional questions blank.';

    final continueLabel = widget.t('common.continue');

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // If on main questions and red flags exist, go back to red flags first.
            if (_step == 1 && redFlags.isNotEmpty) {
              setState(() {
                _errors = {};
                _step = 0;
              });
              return;
            }
            Navigator.pop(context);
          },
        ),
      ),
      body: ListView(
        children: [
          if (descKey != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: Text(widget.t(descKey)),
            ),

          // Step header card
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headerTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      headerSubtitle,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 10),
                    if (redFlags.isNotEmpty)
                      Row(
                        children: [
                          Expanded(
                            child: LinearProgressIndicator(
                              value: showingRedFlags ? 0.5 : 1.0,
                              minHeight: 6,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(showingRedFlags ? '1/2' : '2/2'),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Questions
          ...questions.map((q) {
            final value = answers[q.questionId];
            return _buildQuestionTile(q: q, value: value);
          }),

          const SizedBox(height: 16),

          // Continue
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
            child: ElevatedButton(
              onPressed: () => _continue(draft),
              child: Text(continueLabel),
            ),
          ),
        ],
      ),
    );
  }
}
