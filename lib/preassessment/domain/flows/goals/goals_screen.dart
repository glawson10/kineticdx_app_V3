import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../answer_value.dart';
import '../../flow_definition.dart';
import '../../../state/intake_draft_controller.dart';
import '../../../flows/review/review_screen.dart';

class GoalsScreen extends StatefulWidget {
  final FlowDefinition flow;

  /// Localisation hook (same pattern as DynamicFlowScreen/ReviewScreen).
  final String Function(String key) t;

  const GoalsScreen({
    super.key,
    required this.flow,
    required this.t,
  });

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  late final TextEditingController _goal1;
  late final TextEditingController _goal2;
  late final TextEditingController _goal3;
  late final TextEditingController _moreInfo;

  bool _hydrated = false;

  String Function(String key) get t => widget.t;
  String _qid(String suffix) => '${widget.flow.flowId}.$suffix';

  String _readTextAnswer(IntakeDraftController draft, String qid) {
    final v = draft.answers[qid];
    final s = v?.asText;
    return s ?? '';
  }

  void _writeTextAnswer(IntakeDraftController draft, String qid, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      draft.setAnswer(qid, null);
    } else {
      draft.setAnswer(qid, AnswerValue.text(trimmed));
    }
  }

  @override
  void initState() {
    super.initState();
    _goal1 = TextEditingController();
    _goal2 = TextEditingController();
    _goal3 = TextEditingController();
    _moreInfo = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hydrated) return;

    final draft = context.read<IntakeDraftController>();

    _goal1.text = _readTextAnswer(draft, _qid('goals.goal1'));
    _goal2.text = _readTextAnswer(draft, _qid('goals.goal2'));
    _goal3.text = _readTextAnswer(draft, _qid('goals.goal3'));
    _moreInfo.text = _readTextAnswer(draft, _qid('history.additionalInfo'));

    _hydrated = true;
  }

  @override
  void dispose() {
    _goal1.dispose();
    _goal2.dispose();
    _goal3.dispose();
    _moreInfo.dispose();
    super.dispose();
  }

  void _continue(IntakeDraftController draft) {
    // Persist into AnswerValue map
    _writeTextAnswer(draft, _qid('goals.goal1'), _goal1.text);
    _writeTextAnswer(draft, _qid('goals.goal2'), _goal2.text);
    _writeTextAnswer(draft, _qid('goals.goal3'), _goal3.text);
    _writeTextAnswer(draft, _qid('history.additionalInfo'), _moreInfo.text);

    // ✅ Provider-safe: DO NOT re-wrap the draft. It already exists above the flow.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReviewScreen(t: t),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Use read() so we don't rebuild while typing due to notifyListeners().
    final draft = context.read<IntakeDraftController>();

    return Scaffold(
      appBar: AppBar(
        title: Text(t('preassessment.goals.title')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            t('preassessment.goals.subtitle'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _goal1,
            decoration: InputDecoration(
              labelText: t('preassessment.goals.goal1.label'),
              hintText: t('preassessment.goals.goal1.hint'),
              border: const OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _goal2,
            decoration: InputDecoration(
              labelText: t('preassessment.goals.goal2.label'),
              hintText: t('preassessment.goals.goal2.hint'),
              border: const OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _goal3,
            decoration: InputDecoration(
              labelText: t('preassessment.goals.goal3.label'),
              hintText: t('preassessment.goals.goal3.hint'),
              border: const OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),

          const SizedBox(height: 20),
          Text(
            t('preassessment.moreInfo.title'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            t('preassessment.moreInfo.subtitle'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),

          TextField(
            controller: _moreInfo,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: t('preassessment.moreInfo.label'),
              hintText: t('preassessment.moreInfo.hint'),
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            textInputAction: TextInputAction.newline,
          ),

          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: () => _continue(draft),
            child: Text(t('common.continue')),
          ),
        ],
      ),
    );
  }
}
