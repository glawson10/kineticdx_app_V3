import 'package:flutter/material.dart';

import '../ui/design_tokens.dart';

class TeamSettingsPage extends StatelessWidget {
  const TeamSettingsPage({
    super.key,
    required this.title,
    required this.subtitle,
    this.actions = const [],
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: AppColors.settingsPageBg,
      width: double.infinity,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.maxContentWidth),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            children: [
              Wrap(
                spacing: AppSpacing.elementGap,
                runSpacing: AppSpacing.elementGap,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 480,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (actions.isNotEmpty)
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      alignment: WrapAlignment.end,
                      children: actions,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sectionGap),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class TeamSettingsSectionCard extends StatelessWidget {
  const TeamSettingsSectionCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.elementGap),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: AppColors.settingsCardBorder.withOpacity(0.6),
          width: 1,
        ),
        boxShadow: AppShadows.cardElevated,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ] else
              const SizedBox(height: AppSpacing.md),
            child,
          ],
        ),
      ),
    );
  }
}

enum TeamChipTone { neutral, success, warning, info }

class TeamMetadataChip extends StatelessWidget {
  const TeamMetadataChip({
    super.key,
    required this.label,
    this.icon,
    this.tone = TeamChipTone.neutral,
  });

  final String label;
  final IconData? icon;
  final TeamChipTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = switch (tone) {
      TeamChipTone.success => (
          bg: theme.colorScheme.primaryContainer,
          fg: theme.colorScheme.onPrimaryContainer,
        ),
      TeamChipTone.warning => (
          bg: theme.colorScheme.errorContainer,
          fg: theme.colorScheme.onErrorContainer,
        ),
      TeamChipTone.info => (
          bg: theme.colorScheme.secondaryContainer,
          fg: theme.colorScheme.onSecondaryContainer,
        ),
      TeamChipTone.neutral => (
          bg: theme.colorScheme.surfaceContainerHighest,
          fg: theme.colorScheme.onSurfaceVariant,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: colors.fg),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class TeamMetricCard extends StatelessWidget {
  const TeamMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.settingsCardBorder),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(
              icon,
              size: 18,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Wraps a child with a hover-triggered scale animation (desktop/web).
/// On touch devices hover does not fire, so the child stays at normal size.
class HoverScaleWrapper extends StatefulWidget {
  const HoverScaleWrapper({
    super.key,
    required this.child,
    this.scaleOnHover = 1.06,
    this.duration = const Duration(milliseconds: 180),
  });

  final Widget child;
  final double scaleOnHover;
  final Duration duration;

  @override
  State<HoverScaleWrapper> createState() => _HoverScaleWrapperState();
}

class _HoverScaleWrapperState extends State<HoverScaleWrapper> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedScale(
        scale: _hovering ? widget.scaleOnHover : 1.0,
        duration: widget.duration,
        curve: Curves.easeInOut,
        child: widget.child,
      ),
    );
  }
}

class TeamInitialAvatar extends StatelessWidget {
  const TeamInitialAvatar({
    super.key,
    required this.label,
    this.active = true,
    this.radius = 22,
    this.imageUrl,
    this.showBorder = false,
  });

  final String label;
  final bool active;
  final double radius;
  /// When set, show this image instead of initials (e.g. profile photo).
  final String? imageUrl;
  /// When true, draw a circular border in theme primary color (e.g. for overview card).
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initials = _initialsFromLabel(label);
    final hasImage = imageUrl != null && imageUrl!.trim().isNotEmpty;
    final Widget avatarContent = CircleAvatar(
      radius: showBorder ? radius - 2 : radius,
      backgroundColor: hasImage
          ? theme.colorScheme.surfaceContainerHighest
          : (active
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest),
      backgroundImage: hasImage ? NetworkImage(imageUrl!.trim()) : null,
      child: hasImage
          ? null
          : Text(
              initials,
              style: theme.textTheme.titleSmall?.copyWith(
                color: active
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
    if (showBorder) {
      return Container(
        width: radius * 2 + 4,
        height: radius * 2 + 4,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: theme.colorScheme.primary,
            width: 2,
          ),
        ),
        child: Center(
          child: avatarContent,
        ),
      );
    }
    return avatarContent;
  }

  static String _initialsFromLabel(String raw) {
    final parts = raw
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

class TeamEmptyStateCard extends StatelessWidget {
  const TeamEmptyStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TeamSettingsSectionCard(
      title: title,
      child: Column(
        children: [
          Icon(
            icon,
            size: 44,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: AppSpacing.md),
            action!,
          ],
        ],
      ),
    );
  }
}
