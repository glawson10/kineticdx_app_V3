import 'package:flutter/material.dart';
import '../../domain/answer_value.dart';
import '../../domain/flow_definition.dart';
import 'question_card.dart';

class BoolQuestion extends StatelessWidget {
  final QuestionDef q;
  final AnswerValue? value;
  final ValueChanged<AnswerValue?> onChanged;
  final String? errorText;
  final String Function(String key) t;

  const BoolQuestion({
    super.key,
    required this.q,
    required this.value,
    required this.onChanged,
    required this.t,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final current = value?.asBool;
    return QuestionCard(
      title: t(q.promptKey),
      errorText: errorText,
      child: Column(
        children: [
          RadioListTile<bool>(
            value: true,
            groupValue: current,
            title: const Text('Yes'),
            onChanged: (_) => onChanged(AnswerValue.bool(true)),
          ),
          RadioListTile<bool>(
            value: false,
            groupValue: current,
            title: const Text('No'),
            onChanged: (_) => onChanged(AnswerValue.bool(false)),
          ),
          if (!q.required)
            TextButton(
              onPressed: () => onChanged(null),
              child: const Text('Clear'),
            ),
        ],
      ),
    );
  }
}
