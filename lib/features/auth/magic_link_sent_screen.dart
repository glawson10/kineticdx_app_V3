// lib/features/auth/magic_link_sent_screen.dart

import 'package:flutter/material.dart';

class MagicLinkSentScreen extends StatelessWidget {
  const MagicLinkSentScreen({
    super.key,
    required this.email,
    this.onBack,
  });

  final String email;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: onBack,
              )
            : null,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.mark_email_read_outlined,
                  size: 64,
                  color: cs.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Check your email',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'We sent a sign-in link to',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Open the link in this device or browser to sign in. The link is valid for a limited time.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (onBack != null) ...[
                  const SizedBox(height: 32),
                  TextButton.icon(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back to sign in'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
