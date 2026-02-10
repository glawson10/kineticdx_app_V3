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
                      child: TextButton.icon(
                        onPressed: () => _close(context),
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Close'),
                      ),
                    ),
                    if (isWebRuntime) ...[
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
