import 'package:flutter/material.dart';
import '../../domain/answer_value.dart';
import '../../domain/flow_definition.dart';
import 'question_card.dart';

class SingleChoiceQuestion extends StatelessWidget {
  final QuestionDef q;
  final AnswerValue? value;
  final ValueChanged<AnswerValue?> onChanged;
  final String? errorText;
  final String Function(String key) t;

  const SingleChoiceQuestion({
    super.key,
    required this.q,
    required this.value,
    required this.onChanged,
    required this.t,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final current = value?.asSingle;

    return QuestionCard(
      title: t(q.promptKey),
      errorText: errorText,
      child: Column(
        children: [
          ...q.options.map((opt) {
            return RadioListTile<String>(
              value: opt.id,
              groupValue: current,
              title: Text(t(opt.labelKey)),
              onChanged: (v) => onChanged(v == null ? null : AnswerValue.single(v)),
            );
          }),
          if (!q.required)
            TextButton(
              onPressed: () => onChanged(null),
              child: Text(t('common.clear')),
            ),
        ],
      ),
    );
  }
}
