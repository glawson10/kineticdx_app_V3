import 'package:flutter/material.dart';

class PublicHeader extends StatelessWidget {
  const PublicHeader({
    super.key,
    this.clinicName,
    this.title,
    this.subtitle,
    this.logoUrl,
    this.onBack,
  });

  final String? clinicName;
  final String? title;
  final String? subtitle;
  final String? logoUrl;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final displayTitle = title ?? clinicName;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack),
          if (logoUrl != null && logoUrl!.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(logoUrl!, width: 40, height: 40, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.local_hospital, size: 40)),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (displayTitle != null)
                  Text(displayTitle, style: Theme.of(context).textTheme.titleMedium),
                if (subtitle != null)
                  Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
