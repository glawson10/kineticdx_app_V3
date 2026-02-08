import 'package:flutter/material.dart';
import '../../domain/answer_value.dart';
import '../../domain/flow_definition.dart';
import 'question_card.dart';

class TextQuestion extends StatefulWidget {
  final QuestionDef q;
  final AnswerValue? value;
  final ValueChanged<AnswerValue?> onChanged;
  final String? errorText;
  final String Function(String key) t;

  const TextQuestion({
    super.key,
    required this.q,
    required this.value,
    required this.onChanged,
    required this.t,
    this.errorText,
  });

  @override
  State<TextQuestion> createState() => _TextQuestionState();
}

class _TextQuestionState extends State<TextQuestion> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.value?.asText ?? '');
  }

  @override
  void didUpdateWidget(covariant TextQuestion oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.value?.asText ?? '';
    if (_c.text != next) _c.text = next;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxLen = widget.q.text?.maxLength;

    return QuestionCard(
      title: widget.t(widget.q.promptKey),
      errorText: widget.errorText,
      child: TextField(
        controller: _c,
        maxLength: maxLen,
        minLines: 2,
        maxLines: 6,
        decoration: InputDecoration(
          hintText: widget.t('common.typeHere'),
          border: const OutlineInputBorder(),
        ),
        onChanged: (txt) {
          // Allow natural typing including spaces; only use trim to decide
          // whether the answer is "empty", not to mutate the live text.
          final trimmed = txt.trim();
          widget.onChanged(
            trimmed.isEmpty ? null : AnswerValue.text(txt),
          );
        },
      ),
    );
  }
}
