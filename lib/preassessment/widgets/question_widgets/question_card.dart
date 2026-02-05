import 'package:flutter/material.dart';

class QuestionCard extends StatelessWidget {
  final Widget child;
  final String? title;
  final String? helper;
  final String? errorText;

  const QuestionCard({
    super.key,
    required this.child,
    this.title,
    this.helper,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(title!, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
            ],
            child,
            if (helper != null) ...[
              const SizedBox(height: 10),
              Text(helper!, style: Theme.of(context).textTheme.bodySmall),
            ],
            if (errorText != null) ...[
              const SizedBox(height: 10),
              Text(
                errorText!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
