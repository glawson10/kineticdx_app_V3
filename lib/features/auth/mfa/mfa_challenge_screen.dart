// lib/features/auth/mfa/mfa_challenge_screen.dart
//
// Shown when sign-in requires a second factor (SMS). User enters code to complete sign-in.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class MfaChallengeScreen extends StatefulWidget {
  const MfaChallengeScreen({
    super.key,
    required this.resolver,
    this.onSuccess,
    this.onCancel,
  });

  final MultiFactorResolver resolver;
  final VoidCallback? onSuccess;
  final VoidCallback? onCancel;

  @override
  State<MfaChallengeScreen> createState() => _MfaChallengeScreenState();
}

class _MfaChallengeScreenState extends State<MfaChallengeScreen> {
  final _codeController = TextEditingController();
  String? _verificationId;
  String? _error;
  bool _loading = false;
  bool _codeSent = false;

  @override
  void initState() {
    super.initState();
    _sendSms();
  }

  Future<void> _sendSms() async {
    final hints = widget.resolver.hints;
    if (hints.isEmpty) {
      setState(() => _error = 'No second factor available.');
      return;
    }
    final firstHint = hints.first;
    if (firstHint is! PhoneMultiFactorInfo) {
      setState(() => _error = 'Phone verification is required.');
      return;
    }

    setState(() {
      _error = null;
      _loading = true;
    });

    await FirebaseAuth.instance.verifyPhoneNumber(
      multiFactorSession: widget.resolver.session,
      multiFactorInfo: firstHint,
      verificationCompleted: (_) {},
      verificationFailed: (e) {
        if (mounted) {
          setState(() {
            _error = e.message ?? e.code;
            _loading = false;
          });
        }
      },
      codeSent: (verificationId, resendToken) {
        if (mounted) {
          setState(() {
            _verificationId = verificationId;
            _codeSent = true;
            _loading = false;
          });
        }
      },
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  Future<void> _submitCode() async {
    final code = _codeController.text.trim();
    final verificationId = _verificationId;
    if (code.isEmpty || verificationId == null) {
      setState(() => _error = 'Enter the code from your phone.');
      return;
    }

    setState(() {
      _error = null;
      _loading = true;
    });

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: code,
      );
      final assertion = PhoneMultiFactorGenerator.getAssertion(credential);
      await widget.resolver.resolveSignIn(assertion);
      if (mounted) {
        widget.onSuccess?.call();
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message ?? e.code;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verification code'),
        leading: widget.onCancel != null
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _loading ? null : widget.onCancel,
              )
            : null,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.sms_outlined,
                    size: 48,
                    color: cs.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Two-step verification',
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'We sent a code to your phone. Enter it below.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: cs.onErrorContainer),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _error ?? '',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_codeSent) ...[
                    TextField(
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submitCode(),
                      decoration: InputDecoration(
                        labelText: 'Verification code',
                        hintText: '000000',
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _loading ? null : _submitCode,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Verify'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _loading ? null : _sendSms,
                      child: const Text('Resend code'),
                    ),
                  ] else if (_loading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
