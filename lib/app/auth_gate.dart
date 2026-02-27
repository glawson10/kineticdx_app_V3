import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import '../data/repositories/user_repository.dart';
import '../data/repositories/memberships_repository.dart';
import '../models/membership.dart';
import '../features/auth/login_page.dart';
import 'clinic_onboarding_gate.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, this.clinicId, this.initialSettingsSection});

  /// When set, this is a clinic-specific portal (/c/{clinicId}).
  /// After sign-in we enforce membership for this clinic; if not a member we sign out and show error.
  final String? clinicId;

  /// When set (e.g. from /c/{clinicId}/settings or /c/{clinicId}/settings/{section}),
  /// after entering the clinic we open Settings tab with this section ('' = default section).
  final String? initialSettingsSection;

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

  Future<_GateResult> _runAfterSignIn(User user, MembershipsRepository membershipsRepo) async {
    await _ensureFreshToken(user);
    await _syncUser(user);

    final clinicId = widget.clinicId?.trim();
    if (clinicId != null && clinicId.isNotEmpty) {
      if (kDebugMode) {
        debugPrint('[AuthGate] Checking membership for clinic portal');
        debugPrint('  clinicId: $clinicId');
        debugPrint('  uid: ${user.uid}');
        debugPrint('  email: ${user.email}');
      }

      Membership? membership;

      try {
        membership = await membershipsRepo.getClinicMembership(
          clinicId: clinicId,
          uid: user.uid,
        );
      } on FirebaseException catch (e, st) {
        if (kDebugMode) {
          debugPrint('[AuthGate] ❌ Firestore error while checking membership');
          debugPrint('  code: ${e.code}');
          debugPrint('  message: ${e.message}');
          debugPrint('  stack: $st');
        }
        // If it's a permission error, show that in the error
        if (e.code == 'permission-denied') {
          if (kDebugMode) {
            debugPrint(
                '[AuthGate] ⚠️ PERMISSION DENIED - Firestore rules are blocking read');
            debugPrint('  Paths checked:');
            debugPrint('    - clinics/$clinicId/memberships/${user.uid}');
            debugPrint('    - clinics/$clinicId/members/${user.uid}');
            debugPrint(
                '  Check Firestore rules allow: isSignedIn() && uid() == memberUid');
          }
        }
        // Re-throw to be caught by error handler below
        rethrow;
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint(
              '[AuthGate] ❌ Unexpected error while checking membership: $e');
          debugPrint('  stack: $st');
        }
        rethrow;
      }

      if (kDebugMode) {
        if (membership == null) {
          debugPrint(
              '[AuthGate] ❌ Membership check FAILED: membership is null');
          debugPrint('  Checked paths:');
          debugPrint('    - clinics/$clinicId/memberships/${user.uid}');
          debugPrint('    - clinics/$clinicId/members/${user.uid}');
        } else {
          debugPrint('[AuthGate] ✅ Membership found');
          debugPrint('  active: ${membership.active}');
          debugPrint('  status: ${membership.status ?? "(null)"}');
          debugPrint('  roleId: ${membership.roleId}');
          if (membership.active != true) {
            debugPrint('[AuthGate] ❌ Membership check FAILED: active != true');
          }
        }
      }

      if (membership == null || membership.active != true) {
        return const _NotAuthorisedResult();
      }
      return _EnterClinicResult(
        initialClinicId: clinicId,
        initialSettingsSection: widget.initialSettingsSection,
      );
    }

    if (kDebugMode) {
      debugPrint(
          '[AuthGate] No clinicId provided, proceeding to onboarding gate');
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
          future: _runAfterSignIn(user, context.read<MembershipsRepository>()),
          builder: (context, resultSnap) {
            if (resultSnap.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (resultSnap.hasError) {
              final error = resultSnap.error;
              if (kDebugMode) {
                debugPrint('[AuthGate] ❌ Error in _runAfterSignIn: $error');
                if (error is FirebaseException) {
                  debugPrint('  FirebaseException code: ${error.code}');
                  debugPrint('  FirebaseException message: ${error.message}');
                }
              }
              return Scaffold(
                appBar: AppBar(title: const Text('Error')),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(
                          'Failed to check membership',
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          error.toString(),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (error is FirebaseException &&
                            error.code == 'permission-denied') ...[
                          const SizedBox(height: 16),
                          Text(
                            'Firestore permission denied.\n\n'
                            'Check that Firestore rules allow reading:\n'
                            '• clinics/{clinicId}/memberships/{uid}\n'
                            '• clinics/{clinicId}/members/{uid}\n\n'
                            'Rule should allow: isSignedIn() && uid() == memberUid',
                            textAlign: TextAlign.center,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.orange.shade700,
                                    ),
                          ),
                        ],
                      ],
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
              return ClinicOnboardingGate(
                initialClinicId: result.initialClinicId,
                initialSettingsSection: result.initialSettingsSection,
              );
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
  const _EnterClinicResult({
    required this.initialClinicId,
    this.initialSettingsSection,
  });
  final String initialClinicId;
  final String? initialSettingsSection;
}
