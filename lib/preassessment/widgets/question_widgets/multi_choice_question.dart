import 'package:flutter/material.dart';
import '../../domain/answer_value.dart';
import '../../domain/flow_definition.dart';
import 'question_card.dart';

class MultiChoiceQuestion extends StatelessWidget {
  final QuestionDef q;
  final AnswerValue? value;
  final ValueChanged<AnswerValue?> onChanged;
  final String? errorText;
  final String Function(String key) t;

  const MultiChoiceQuestion({
    super.key,
    required this.q,
    required this.value,
    required this.onChanged,
    required this.t,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final current = (value?.asMulti ?? const <String>[]).toSet();

    return QuestionCard(
      title: t(q.promptKey),
      errorText: errorText,
      child: Column(
        children: [
          ...q.options.map((opt) {
            final checked = current.contains(opt.id);
            return CheckboxListTile(
              value: checked,
              title: Text(t(opt.labelKey)),
              onChanged: (v) {
                final next = {...current};
                if (v == true) {
                  next.add(opt.id);
                } else {
                  next.remove(opt.id);
                }
                onChanged(next.isEmpty ? null : AnswerValue.multi(next.toList()));
              },
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
