import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../app/pending_invite_store.dart';
import '/app/clinic_onboarding_gate.dart'; // adjust import if needed

class AcceptInviteScreen extends StatefulWidget {
  const AcceptInviteScreen({super.key});

  static const routeName = '/invite/accept';

  @override
  State<AcceptInviteScreen> createState() => _AcceptInviteScreenState();
}

class _AcceptInviteScreenState extends State<AcceptInviteScreen> {
  final _auth = FirebaseAuth.instance;
  final _fn = FirebaseFunctions.instanceFor(region: 'europe-west3');

  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _createAccount = false;
  bool _loading = true;
  bool _submitting = false;

  String? _token;
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  String _safe(String? v) => (v ?? '').trim();

  String _titleCaseWords(String input) {
    final parts =
        input.split(RegExp(r'\s+')).where((p) => p.trim().isNotEmpty).toList();
    if (parts.isEmpty) return input;
    return parts
        .map((w) => w.isEmpty ? w : (w[0].toUpperCase() + w.substring(1)))
        .join(' ');
  }

  String _nameFromEmail(String email) {
    final lower = email.trim().toLowerCase();
    final local = lower.contains('@') ? lower.split('@').first : lower;
    final pretty = local.replaceAll(RegExp(r'[._-]+'), ' ').trim();
    if (pretty.isEmpty) return 'User';
    return _titleCaseWords(pretty);
  }

  Future<void> _ensureAuthDisplayName(User user, String email) async {
    final current = _safe(user.displayName);
    if (current.isNotEmpty) return;

    final fallback = _nameFromEmail(email);
    try {
      await user.updateDisplayName(fallback);
      await user.reload();
    } catch (_) {
      // Non-fatal
    }
  }

  // Reads token from:
  // - normal query:   /invite/accept?token=...
  // - hash query:     /#/invite/accept?token=...
  String? _readTokenFromUri() {
    final base = Uri.base;

    // 1) Normal query
    final t1 = (base.queryParameters['token'] ?? '').trim();
    if (t1.isNotEmpty) return t1;

    // 2) Hash fragment query (Flutter web hash router)
    // base.fragment might be: "/invite/accept?token=XYZ"
    final frag = base.fragment;
    if (frag.isNotEmpty) {
      final qIndex = frag.indexOf('?');
      if (qIndex != -1 && qIndex < frag.length - 1) {
        final query = frag.substring(qIndex + 1);
        final fragUri = Uri.tryParse('https://local/?$query');
        final t2 = (fragUri?.queryParameters['token'] ?? '').trim();
        if (t2.isNotEmpty) return t2;
      }
    }

    return null;
  }

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 1) URL token
      final fromUrl = _readTokenFromUri();

      // 2) fallback: stored token (helps if user refreshes mid-flow)
      final fromStore = await PendingInviteStore.getToken();

      final t = (fromUrl ?? fromStore ?? '').trim();
      if (t.isEmpty) {
        setState(() {
          _token = null;
          _error = 'Invite token missing. Please open the invite link again.';
          _loading = false;
        });
        return;
      }

      _token = t;
      await PendingInviteStore.setToken(t);

      setState(() => _loading = false);

      // If already logged in, try to complete immediately
      if (_auth.currentUser != null) {
        await _maybeCompleteInvite();
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load invite: $e';
        _loading = false;
      });
    }
  }

  Future<void> _signInOrCreate() async {
    if (_submitting) return;

    final email = _emailCtrl.text.trim().toLowerCase();
    final pass = _passCtrl.text;

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email.');
      return;
    }
    if (pass.trim().length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      if (_createAccount) {
        final cred = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: pass,
        );

        // ✅ Set displayName immediately (so functions can read it later)
        if (cred.user != null) {
          await _ensureAuthDisplayName(cred.user!, email);
          await cred.user!.sendEmailVerification();
        }
      } else {
        final cred = await _auth.signInWithEmailAndPassword(
          email: email,
          password: pass,
        );

        // ✅ If existing user has no displayName, set a fallback
        if (cred.user != null) {
          await _ensureAuthDisplayName(cred.user!, email);
        }
      }

      if (!mounted) return;
      await _maybeCompleteInvite();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? e.code);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _resendVerification() async {
    try {
      await _auth.currentUser?.sendEmailVerification();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification email sent')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send verification: $e')),
      );
    }
  }

  Future<void> _maybeCompleteInvite() async {
    final token = (_token ?? '').trim();
    if (token.isEmpty) return;

    final user = _auth.currentUser;
    if (user == null) return;

    // Ensure we have latest verification state
    await user.reload();
    final refreshed = _auth.currentUser;

    if (refreshed != null && !refreshed.emailVerified) {
      // Don’t accept invites for unverified accounts (recommended)
      return;
    }

    await _completeInvite(token);
  }

  Future<void> _completeInvite(String token) async {
    if (_submitting) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final callable = _fn.httpsCallable('acceptInviteFn');
      final res = await callable.call(<String, dynamic>{
        'token': token,
      });

      final data = res.data;
      final ok = data is Map && (data['success'] == true || data['ok'] == true);

      if (!ok) {
        throw StateError('acceptInviteFn returned unexpected payload: $data');
      }

      // ✅ OPTIONAL: If you want staff list to show immediately even if Auth name was empty earlier
      // final clinicId = (data is Map ? (data['clinicId'] ?? '').toString() : '').trim();
      // if (clinicId.isNotEmpty) {
      //   await _fn.httpsCallable('syncMyDisplayNameFn').call({'clinicId': clinicId});
      // }

      await PendingInviteStore.clear();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ClinicOnboardingGate()),
        (route) => false,
      );
    } on FirebaseFunctionsException catch (e) {
      setState(
          () => _error = '${e.code}: ${e.message ?? e.details ?? ''}'.trim());
    } catch (e) {
      setState(() => _error = 'Failed to accept invite: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_token == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Accept invite')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error ?? 'Invite token missing.'),
          ),
        ),
      );
    }

    // Logged in but not verified → gate
    if (user != null && !user.emailVerified) {
      return Scaffold(
        appBar: AppBar(title: const Text('Verify your email')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.mark_email_unread_outlined, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'We sent a verification email to ${user.email}.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Verify your email, then come back and tap “I’ve verified”.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: _submitting ? null : _resendVerification,
                        child: const Text('Resend email'),
                      ),
                      OutlinedButton(
                        onPressed: _submitting
                            ? null
                            : () async {
                                final messenger = ScaffoldMessenger.of(context);
                                await _maybeCompleteInvite();
                                if (!mounted) return;
                                if (_auth.currentUser?.emailVerified != true) {
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text('Still not verified yet.'),
                                    ),
                                  );
                                }
                              },
                        child: const Text("I've verified"),
                      ),
                      TextButton(
                        onPressed: _submitting ? null : _signOut,
                        child: const Text('Use a different account'),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Not logged in → show login/signup inline
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Accept invite')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person_add_alt_1_outlined, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    _createAccount
                        ? 'Create an account to join the clinic'
                        : 'Sign in to accept the invite',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _signInOrCreate,
                      child: _submitting
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_createAccount ? 'Create account' : 'Sign in'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () =>
                            setState(() => _createAccount = !_createAccount),
                    child: Text(
                      _createAccount
                          ? 'Already have an account? Sign in'
                          : 'New here? Create an account',
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Logged in + verified → show “Accept invite”
    return Scaffold(
      appBar: AppBar(title: const Text('Accept invite')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified_outlined, size: 48),
                const SizedBox(height: 12),
                Text(
                  'Signed in as ${user.email}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed:
                        _submitting ? null : () => _completeInvite(_token!),
                    child: _submitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Accept invite'),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _submitting ? null : _signOut,
                  child: const Text('Use a different account'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
