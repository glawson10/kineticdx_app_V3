import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../data/repositories/clinic_public_profile_repository.dart';
import '../../models/clinic_public_profile.dart';
import 'auth_controller.dart';
import 'magic_link_sent_screen.dart';
import 'mfa/mfa_challenge_screen.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.clinicId, this.initialError});

  /// When set, shows clinic-branded login (fetches clinics/{clinicId}/public/profile).
  final String? clinicId;

  /// Shown once on load (e.g. "Not authorised for this clinic." after forced sign-out).
  final String? initialError;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _auth = AuthController();
  final _formKey = GlobalKey<FormState>();
  final _profileRepo = ClinicPublicProfileRepository();

  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _loading = false;
  bool _obscure = true;
  String? _error;
  ClinicPublicProfile? _profile;

  @override
  void initState() {
    super.initState();
    final initialErr = widget.initialError?.trim();
    if (initialErr != null && initialErr.isNotEmpty) {
      _error = initialErr;
    }
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final clinicId = widget.clinicId?.trim();
    if (clinicId == null || clinicId.isEmpty) {
      if (mounted) setState(() => _profile = const ClinicPublicProfile(displayName: 'KineticDx'));
      return;
    }
    final profile = await _profileRepo.getProfile(clinicId);
    if (mounted) setState(() => _profile = profile);
  }

  Widget _buildHeader(ThemeData theme, ColorScheme cs) {
    final profile = _profile ?? const ClinicPublicProfile(displayName: 'KineticDx');
    final logoUrl = profile.logoUrl;
    final hasLogo = logoUrl != null && logoUrl.isNotEmpty;

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: hasLogo
              ? Image.network(
                  logoUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.health_and_safety_outlined,
                    color: cs.onPrimaryContainer,
                  ),
                )
              : Icon(
                  Icons.health_and_safety_outlined,
                  color: cs.onPrimaryContainer,
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(profile.displayName, style: theme.textTheme.titleLarge),
              const SizedBox(height: 2),
              Text(
                'Sign in to your clinic workspace',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _runBrevoAuthTest() async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'testBrevoConnection',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 10)),
      );

      final res = await callable.call();
      final data = res.data;

      final ok = (data is Map && data['ok'] == true);
      final status = (data is Map) ? data['status'] : null;

      if (!mounted) return;

      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Brevo auth test passed')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Brevo auth test failed (status: $status)')),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '❌ Brevo test error: ${e.code}${e.message != null ? " - ${e.message}" : ""}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Brevo test unexpected error: $e')),
      );
    }
  }

  Future<void> _login() async {
    // Basic client-side validation (rules still enforce real security)
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await _auth.signInWithEmail(
      email: _email.text.trim(),
      password: _password.text,
    );

    if (!mounted) return;

    switch (result) {
      case SignInSuccess():
        await _runBrevoAuthTest();
        break;
      case SignInFailure(:final message):
        setState(() => _error = message);
        break;
      case SignInRequiresMfa(:final resolver):
        setState(() => _loading = false);
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => MfaChallengeScreen(
              resolver: resolver,
              onSuccess: () {
                Navigator.of(context).pop();
                _runBrevoAuthTest();
              },
              onCancel: () => Navigator.of(context).pop(),
            ),
          ),
        );
        return;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _sendMagicLink() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email to receive the sign-in link.');
      return;
    }
    if (!email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _auth.sendSignInLink(email: email);
      if (!mounted) return;
      setState(() => _loading = false);
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => MagicLinkSentScreen(
            email: email,
            onBack: () => Navigator.of(context).pop(),
          ),
        ),
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

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email first, then tap “Forgot password?”.');
      return;
    }

    setState(() => _error = null);
    try {
      await _auth.sendPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset email sent.')),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? e.code);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: Stack(
            children: [
              // Background (subtle)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      cs.surface,
                      cs.surfaceContainerHighest.withValues(alpha: 0.6),
                    ],
                  ),
                ),
              ),

              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 900;

                        final loginCard = ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: cs.outlineVariant),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // Header / branding (clinic profile or fallback)
                                    _buildHeader(theme, cs),

                                    const SizedBox(height: 20),

                                    if (_error != null) ...[
                                      Builder(
                                        builder: (context) {
                                          final err = _error ?? '';
                                          return Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: cs.errorContainer,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Icon(Icons.error_outline, color: cs.onErrorContainer),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    err,
                                                    style: theme.textTheme.bodyMedium?.copyWith(
                                                      color: cs.onErrorContainer,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 12),
                                    ],

                                    TextFormField(
                                      controller: _email,
                                      keyboardType: TextInputType.emailAddress,
                                      textInputAction: TextInputAction.next,
                                      autofillHints: const [AutofillHints.username, AutofillHints.email],
                                      decoration: InputDecoration(
                                        labelText: 'Email',
                                        hintText: 'name@clinic.com',
                                        prefixIcon: const Icon(Icons.mail_outline),
                                        filled: true,
                                        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                                      ),
                                      validator: (v) {
                                        final s = (v ?? '').trim();
                                        if (s.isEmpty) return 'Email is required';
                                        if (!s.contains('@')) return 'Enter a valid email';
                                        return null;
                                      },
                                    ),

                                    const SizedBox(height: 12),

                                    TextFormField(
                                      controller: _password,
                                      obscureText: _obscure,
                                      textInputAction: TextInputAction.done,
                                      autofillHints: const [AutofillHints.password],
                                      onFieldSubmitted: (_) => _loading ? null : _login(),
                                      decoration: InputDecoration(
                                        labelText: 'Password',
                                        prefixIcon: const Icon(Icons.lock_outline),
                                        filled: true,
                                        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                                        suffixIcon: IconButton(
                                          onPressed: () => setState(() => _obscure = !_obscure),
                                          icon: Icon(
                                            _obscure
                                                ? Icons.visibility_outlined
                                                : Icons.visibility_off_outlined,
                                          ),
                                          tooltip: _obscure ? 'Show password' : 'Hide password',
                                        ),
                                      ),
                                      validator: (v) {
                                        if ((v ?? '').isEmpty) return 'Password is required';
                                        return null;
                                      },
                                    ),

                                    const SizedBox(height: 8),

                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed: _loading ? null : _forgotPassword,
                                        child: const Text('Forgot password?'),
                                      ),
                                    ),

                                    const SizedBox(height: 8),

                                    FilledButton(
                                      onPressed: _loading ? null : _login,
                                      style: FilledButton.styleFrom(
                                        minimumSize: const Size.fromHeight(52),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: _loading
                                          ? const SizedBox(
                                              height: 18,
                                              width: 18,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : const Text('Sign in'),
                                    ),

                                    const SizedBox(height: 12),

                                    TextButton.icon(
                                      onPressed: _loading ? null : _sendMagicLink,
                                      icon: const Icon(Icons.link, size: 18),
                                      label: const Text('Email me a sign-in link'),
                                    ),

                                    const SizedBox(height: 12),

                                    Text(
                                      'By continuing you confirm you are authorised to access this clinic.',
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );

                        if (!isWide) {
                          return Center(child: loginCard);
                        }

                        return Row(
                          children: [
                            Expanded(child: _LeftPanel(theme)),
                            const SizedBox(width: 24),
                            loginCard,
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),

              if (_loading)
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: true,
                    child: Container(color: Colors.black.withValues(alpha: 0.04)),
                  ),
                ),

              // Environment badge (dev/staging only; hidden in release)
              if (kDebugMode)
                Positioned(
                  top: 8,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Text(
                      'DEV',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _LeftPanel(ThemeData theme) {
  final cs = theme.colorScheme;
  return Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Welcome back', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 10),
        Text(
          'Secure clinic access for scheduling, notes, and patient workflows.',
          style: theme.textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
        _Bullet(theme, Icons.verified_user_outlined, 'Role-based access'),
        const SizedBox(height: 10),
        _Bullet(theme, Icons.folder_outlined, 'Clinic-scoped data model'),
        const SizedBox(height: 10),
        _Bullet(theme, Icons.shield_outlined, 'MFA-ready security'),
      ],
    ),
  );
}

Widget _Bullet(ThemeData theme, IconData icon, String text) {
  final cs = theme.colorScheme;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: cs.onSurfaceVariant),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      ),
    ],
  );
}
