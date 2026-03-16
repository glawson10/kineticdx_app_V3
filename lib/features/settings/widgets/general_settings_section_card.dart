// Reusable section card for General clinic settings (premium layout).
// Border radius 12, subtle border, 24px padding; optional title, description, footer.

import 'package:flutter/material.dart';

import '../../../../ui/design_tokens.dart';

class GeneralSettingsSectionCard extends StatelessWidget {
  const GeneralSettingsSectionCard({
    super.key,
    required this.title,
    this.description,
    required this.child,
    this.footer,
    this.dense = false,
  });

  final String title;
  final String? description;
  final Widget child;
  final Widget? footer;
  final bool dense;

  /// Section title → description gap
  static const double titleToDescription = 6;
  /// Description → first field gap
  static const double descriptionToField = 16;
  /// Field block to next field block
  static const double fieldGap = 20;
  /// Label to input (handled by InputDecoration)
  static const double labelToInput = 6;
  /// Input to helper/error
  static const double inputToHelper = 4;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontSize: 17,
      fontWeight: FontWeight.w600,
    );
    final descriptionStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: 12,
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.4,
    );

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.settingsCardBorder, width: 1),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: dense ? AppSpacing.md : AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: titleStyle),
          if (description != null && description!.isNotEmpty) ...[
            SizedBox(height: titleToDescription),
            Text(description!, style: descriptionStyle),
          ],
          SizedBox(height: descriptionToField),
          child,
          if (footer != null) ...[
            SizedBox(height: fieldGap),
            footer!,
          ],
        ],
      ),
    );
  }
}
