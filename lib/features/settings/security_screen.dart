// lib/features/settings/security_screen.dart
//
// Account-level security: MFA enrollment (SMS second factor).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  String? _verificationId;
  String? _error;
  bool _loading = false;
  bool _enrolling = false;
  List<MultiFactorInfo>? _enrolledFactors;

  @override
  void initState() {
    super.initState();
    _loadEnrolledFactors();
  }

  Future<void> _loadEnrolledFactors() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final factors = await user.multiFactor.getEnrolledFactors();
    if (mounted) setState(() => _enrolledFactors = factors);
  }

  Future<void> _enrollPhone() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = 'Enter your phone number.');
      return;
    }

    setState(() {
      _error = null;
      _loading = true;
      _enrolling = true;
    });

    try {
      final session = await user.multiFactor.getSession();
      await FirebaseAuth.instance.verifyPhoneNumber(
        multiFactorSession: session,
        phoneNumber: phone,
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
              _loading = false;
            });
          }
        },
        codeAutoRetrievalTimeout: (_) {},
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _submitEnrollCode() async {
    final user = FirebaseAuth.instance.currentUser;
    final verificationId = _verificationId;
    final code = _codeController.text.trim();
    if (user == null || verificationId == null || code.isEmpty) {
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
      await user.multiFactor.enroll(
        PhoneMultiFactorGenerator.getAssertion(credential),
      );
      if (mounted) {
        await _loadEnrolledFactors();
        setState(() {
          _loading = false;
          _enrolling = false;
          _verificationId = null;
          _phoneController.clear();
          _codeController.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('MFA enabled. You will be asked for a code when signing in.')),
        );
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

  Future<void> _unenroll(MultiFactorInfo info) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disable MFA?'),
        content: const Text(
          'You will no longer be asked for a verification code when signing in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Disable'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _loading = true);
    try {
      await user.multiFactor.unenroll(multiFactorInfo: info);
      if (mounted) {
        await _loadEnrolledFactors();
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('MFA disabled.')),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? e.code)),
        );
      }
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final factors = _enrolledFactors ?? [];
    final hasPhone = factors.any((f) => f is PhoneMultiFactorInfo);

    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Two-step verification',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Add a second step when signing in (SMS code).',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),

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
                      _error!,
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

          if (_enrolling) ...[
            if (_verificationId == null) ...[
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  hintText: '+44 7xxx xxxxxx',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton(
                    onPressed: _loading ? null : _enrollPhone,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Send code'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _loading ? null : () => setState(() => _enrolling = false),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ] else ...[
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Verification code',
                  hintText: '000000',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton(
                    onPressed: _loading ? null : _submitEnrollCode,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Verify and enable'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _loading ? null : () => setState(() => _verificationId = null),
                    child: const Text('Back'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
          ] else ...[
            if (hasPhone)
              ListTile(
                leading: const Icon(Icons.sms_outlined),
                title: const Text('SMS'),
                subtitle: Text(
                  factors
                      .whereType<PhoneMultiFactorInfo>()
                      .map((e) => e.phoneNumber)
                      .where((s) => s.isNotEmpty)
                      .join(', '),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _loading ? null : () {
                    final phones = factors.whereType<PhoneMultiFactorInfo>();
                    if (phones.isNotEmpty) _unenroll(phones.first);
                  },
                ),
              )
            else
              FilledButton.icon(
                onPressed: () => setState(() => _enrolling = true),
                icon: const Icon(Icons.add),
                label: const Text('Enable MFA (SMS)'),
              ),
          ],
        ],
      ),
    );
  }
}
