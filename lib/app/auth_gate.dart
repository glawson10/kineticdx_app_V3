import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import '../data/repositories/user_repository.dart';
import '../data/repositories/memberships_repository.dart';
import '../features/auth/login_page.dart';
import 'clinic_onboarding_gate.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, this.clinicId});

  /// When set, this is a clinic-specific portal (/c/{clinicId}).
  /// After sign-in we enforce membership for this clinic; if not a member we sign out and show error.
  final String? clinicId;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _userRepo = UserRepository();

  /// Set when user signed in but is not a member of [AuthGate.clinicId]; we sign out and show this on LoginPage.
  String? _notAuthorisedError;

  Future<void> _syncUser(User user) async {
    await _userRepo.ensureUserDoc(user);
  }

  Future<void> _ensureFreshToken(User user) async {
    try {
      await user.getIdToken(true);
    } catch (_) {}
  }

  Future<_GateResult> _runAfterSignIn(User user) async {
    await _ensureFreshToken(user);
    await _syncUser(user);

    final clinicId = widget.clinicId?.trim();
    if (clinicId != null && clinicId.isNotEmpty) {
      final membershipsRepo = context.read<MembershipsRepository>();
      final membership = await membershipsRepo.getClinicMembership(
        clinicId: clinicId,
        uid: user.uid,
      );
      if (membership == null || membership.active != true) {
        return const _NotAuthorisedResult();
      }
      return _EnterClinicResult(initialClinicId: clinicId);
    }

    return const _EnterOnboardingResult();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.active) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snap.data;
        if (user == null || user.isAnonymous) {
          return LoginPage(
            clinicId: widget.clinicId,
            initialError: _notAuthorisedError,
          );
        }

        return FutureBuilder<_GateResult>(
          future: _runAfterSignIn(user),
          builder: (context, resultSnap) {
            if (resultSnap.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (resultSnap.hasError) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Failed to sync: ${resultSnap.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }

            final result = resultSnap.data;
            if (result == null) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (result is _NotAuthorisedResult) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _notAuthorisedError = 'Not authorised for this clinic.';
                  });
                  FirebaseAuth.instance.signOut();
                }
              });
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (result is _EnterClinicResult) {
              return ClinicOnboardingGate(initialClinicId: result.initialClinicId);
            }

            return const ClinicOnboardingGate();
          },
        );
      },
    );
  }
}

sealed class _GateResult {
  const _GateResult();
}

class _NotAuthorisedResult extends _GateResult {
  const _NotAuthorisedResult();
}

class _EnterOnboardingResult extends _GateResult {
  const _EnterOnboardingResult();
}

class _EnterClinicResult extends _GateResult {
  const _EnterClinicResult({required this.initialClinicId});
  final String initialClinicId;
}
