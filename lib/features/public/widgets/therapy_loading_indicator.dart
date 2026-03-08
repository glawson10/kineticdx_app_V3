import 'package:flutter/material.dart';

class TherapyLoadingIndicator extends StatelessWidget {
  const TherapyLoadingIndicator({
    super.key,
    this.message,
    this.size = 48.0,
    this.color,
    this.iconAssetPaths,
  });

  final String? message;
  final double size;
  final Color? color;
  final List<String>? iconAssetPaths;

  static const List<String> therapyIconPaths = [];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              color: color ?? Theme.of(context).colorScheme.primary,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(message!, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
