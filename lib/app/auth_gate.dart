import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/repositories/user_repository.dart';
import '../features/auth/login_page.dart';
import 'clinic_onboarding_gate.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _userRepo = UserRepository();

  Future<void> _syncUser(User user) async {
    await _userRepo.ensureUserDoc(user);
  }

  Future<void> _ensureFreshToken(User user) async {
    // 🔑 Critical for Flutter Web + Gen2 callable auth
    // Forces token creation/refresh before we enter the clinic shell.
    try {
      await user.getIdToken(true);
    } catch (_) {
      // If this fails, callables may still work; we just want to avoid blocking login.
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        // ✅ The key fix: wait until the auth stream is ACTIVE (not just "not waiting")
        if (snap.connectionState != ConnectionState.active) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snap.data;
        if (user == null) return const LoginPage();

        // Once signed in, do:
        // 1) ensure token exists (web)
        // 2) sync user doc
        return FutureBuilder<void>(
          future: () async {
            await _ensureFreshToken(user);
            await _syncUser(user);
          }(),
          builder: (context, syncSnap) {
            if (syncSnap.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (syncSnap.hasError) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Failed to sync user profile: ${syncSnap.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }
// AuthGate build():
final user = snap.data;

// ✅ IMPORTANT: anonymous user should NOT enter clinician app
if (user == null || user.isAnonymous) {
  return const LoginPage();
}

            // ✅ Route into onboarding logic
            return const ClinicOnboardingGate();
          },
        );
      },
    );
  }
}

