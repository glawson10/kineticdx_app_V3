// lib/preassessment/flows/thank_you/thank_you_screen.dart
//
// ✅ Updated in full
// - Works for web + mobile/desktop
// - Avoids closing tab unless it was opened as a popup (web safety)
// - Copies home link on non-web + snackbar
// - Adds optional "Copy reference" action
// - Adds clear next-steps copy
// - Keeps layout narrow + consistent with your other screens

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../util/web_actions.dart';

class ThankYouScreen extends StatelessWidget {
  final String? intakeSessionId;

  const ThankYouScreen({
    super.key,
    this.intakeSessionId,
  });

  static const String _homeUrl = 'https://fundamentalrecovery.net';

  Future<void> _goHome(BuildContext context) async {
    if (isWebRuntime) {
      openUrl(_homeUrl);
      return;
    }

    // Non-web: copy link + toast
    await Clipboard.setData(const ClipboardData(text: _homeUrl));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Home link copied to clipboard.')),
      );
    }
  }

  Future<void> _copyReference(BuildContext context) async {
    final id = (intakeSessionId ?? '').trim();
    if (id.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: id));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reference copied to clipboard.')),
      );
    }
  }

  void _selfBooking(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Self booking is coming soon.')),
    );
  }

  void _close(BuildContext context) {
    if (isWebRuntime) {
      // NOTE: browsers usually only allow window.close() for windows opened by script.
      closeWindow();
      return;
    }

    // Non-web fallback
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = (intakeSessionId ?? '').trim();

    // Only show close on web (still may no-op depending on browser rules)
    final showClose = isWebRuntime;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thank you'),
        automaticallyImplyLeading: !isWebRuntime,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 60,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Thanks — your pre-assessment has been submitted.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'We’ll review your answers before your appointment.\n'
                      'If anything changes significantly, please contact the clinic.',
                      textAlign: TextAlign.center,
                      style: TextStyle(height: 1.35),
                    ),
                    if (id.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Reference',
                              style: theme.textTheme.labelLarge,
                            ),
                            const SizedBox(height: 6),
                            SelectableText(
                              id,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => _copyReference(context),
                                icon: const Icon(Icons.copy_rounded),
                                label: const Text('Copy reference'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _goHome(context),
                        icon: const Icon(Icons.home_rounded),
                        label: const Text('Return to home page'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _selfBooking(context),
                        icon: const Icon(Icons.calendar_month_rounded),
                        label: const Text('Self booking'),
                      ),
                    ),
                    if (showClose) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: () => _close(context),
                          icon: const Icon(Icons.close_rounded),
                          label: const Text('Close'),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'If “Close” doesn’t work, you can safely close this tab.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
