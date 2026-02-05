import 'package:flutter/material.dart';
import '../../domain/answer_value.dart';
import '../../domain/flow_definition.dart';
import 'question_card.dart';

class SliderQuestion extends StatelessWidget {
  final QuestionDef q;
  final AnswerValue? value;
  final ValueChanged<AnswerValue?> onChanged;
  final String? errorText;
  final String Function(String key) t;

  const SliderQuestion({
    super.key,
    required this.q,
    required this.value,
    required this.onChanged,
    required this.t,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final min = (q.numeric?.min ?? 0).toDouble();
    final max = (q.numeric?.max ?? 10).toDouble();
    final step = (q.numeric?.step ?? 1).toDouble();

    final currentInt = value?.asInt;
    final current = (currentInt ?? min.toInt()).toDouble();

    return QuestionCard(
      title: t(q.promptKey),
      errorText: errorText,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${t('common.value')}: ${current.toInt()}'),
          Slider(
            value: current.clamp(min, max),
            min: min,
            max: max,
            divisions: ((max - min) / step).round(),
            label: current.toInt().toString(),
            onChanged: (v) => onChanged(AnswerValue.int(v.round())),
          ),
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
