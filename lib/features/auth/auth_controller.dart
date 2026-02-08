// lib/features/auth/auth_controller.dart
//
// Centralised clinician auth: email/password, reset, magic link.
// MFA: sign-in methods throw FirebaseAuthMultiFactorException when second factor required;
// caller shows MfaChallengeScreen and completes with resolver.resolveSignIn(assertion).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Result of a sign-in attempt that may require MFA.
sealed class SignInResult {
  const SignInResult();
}

class SignInSuccess extends SignInResult {
  const SignInSuccess();
}

class SignInFailure extends SignInResult {
  const SignInFailure(this.message);
  final String message;
}

class SignInRequiresMfa extends SignInResult {
  const SignInRequiresMfa(this.resolver);
  final MultiFactorResolver resolver;
}

/// Key for storing email when sending magic link (same device must complete sign-in).
const String _keyEmailForLink = 'auth_email_link_email';

class AuthController {
  AuthController({FirebaseAuth? auth})
      : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  // ---------------------------------------------------------------------------
  // Email / password
  // ---------------------------------------------------------------------------

  /// Returns [SignInRequiresMfa] when user has MFA enabled; show [MfaChallengeScreen].
  Future<SignInResult> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return const SignInSuccess();
    } on FirebaseAuthMultiFactorException catch (e) {
      return SignInRequiresMfa(e.resolver);
    } on FirebaseAuthException catch (e) {
      return SignInFailure(e.message ?? e.code);
    } catch (e) {
      return SignInFailure(e.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // Password reset
  // ---------------------------------------------------------------------------

  Future<void> sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  // ---------------------------------------------------------------------------
  // Magic link (email link sign-in)
  // ---------------------------------------------------------------------------

  static const String _defaultLinkDomain = 'https://kineticdx-app-v3.web.app';

  /// [linkDomain] must be in Firebase Auth authorized domains and open this app (e.g. web URL or app link).
  /// On web, pass null to use current origin (e.g. for local dev).
  Future<void> sendSignInLink({
    required String email,
    String? linkDomain,
  }) async {
    String domain = linkDomain?.trim() ?? _defaultLinkDomain;
    assert(domain.isNotEmpty);
    if (domain.isEmpty) {
      throw ArgumentError('linkDomain required for email link');
    }
    final actionCodeSettings = ActionCodeSettings(
      url: domain,
      handleCodeInApp: true,
      androidPackageName: null,
      iOSBundleId: null,
    );
    await _auth.sendSignInLinkToEmail(
      email: email.trim(),
      actionCodeSettings: actionCodeSettings,
    );
    await _storeEmailForLink(email.trim());
  }

  Future<void> _storeEmailForLink(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEmailForLink, email);
  }

  static Future<String?> getStoredEmailForLink() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyEmailForLink);
  }

  static Future<void> clearStoredEmailForLink() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyEmailForLink);
  }

  bool isSignInWithEmailLink(String link) {
    return _auth.isSignInWithEmailLink(link);
  }

  /// Complete sign-in from email link. Use [getStoredEmailForLink] if email unknown.
  Future<SignInResult> signInWithEmailLink({
    required String email,
    required String emailLink,
  }) async {
    try {
      await _auth.signInWithEmailLink(
        email: email.trim(),
        emailLink: emailLink.trim(),
      );
      await clearStoredEmailForLink();
      return const SignInSuccess();
    } on FirebaseAuthMultiFactorException catch (e) {
      return SignInRequiresMfa(e.resolver);
    } on FirebaseAuthException catch (e) {
      return SignInFailure(e.message ?? e.code);
    } catch (e) {
      return SignInFailure(e.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // Sign out
  // ---------------------------------------------------------------------------

  Future<void> signOut() async {
    await _auth.signOut();
  }
}
