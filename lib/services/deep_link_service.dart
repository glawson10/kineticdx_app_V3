// lib/services/deep_link_service.dart
//
// Handles incoming app links (email sign-in link). Call [handleInitialLink] at startup.

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../features/auth/auth_controller.dart';

/// Result of handling an initial link.
sealed class InitialLinkResult {
  const InitialLinkResult();
}

class InitialLinkHandled extends InitialLinkResult {
  const InitialLinkHandled();
}

class InitialLinkNotSignInLink extends InitialLinkResult {
  const InitialLinkNotSignInLink();
}

class InitialLinkMissingEmail extends InitialLinkResult {
  const InitialLinkMissingEmail();
}

class InitialLinkError extends InitialLinkResult {
  const InitialLinkError(this.message);
  final String message;
}

class DeepLinkService {
  DeepLinkService({
    AppLinks? appLinks,
    AuthController? auth,
  })  : _appLinks = appLinks ?? AppLinks(),
        _auth = auth ?? AuthController();

  final AppLinks _appLinks;
  final AuthController _auth;

  /// Call once at app startup. If the app was opened via an email sign-in link,
  /// completes sign-in and returns [InitialLinkHandled]. Call before [runApp].
  Future<InitialLinkResult> handleInitialLink() async {
    Uri? uri = await _appLinks.getInitialLink();
    // On web, getInitialLink may be null; use current URL when it looks like an auth link.
    if (uri == null && kIsWeb) {
      final base = Uri.base;
      if (base.queryParameters.containsKey('oobCode') ||
          base.path.contains('auth/action')) {
        uri = base;
      }
    }
    if (uri == null) return const InitialLinkNotSignInLink();

    final link = uri.toString();
    if (!_auth.isSignInWithEmailLink(link)) {
      return const InitialLinkNotSignInLink();
    }

    final email = await AuthController.getStoredEmailForLink();
    if (email == null || email.trim().isEmpty) {
      return const InitialLinkMissingEmail();
    }

    final result = await _auth.signInWithEmailLink(
      email: email,
      emailLink: link,
    );

    switch (result) {
      case SignInSuccess():
        return const InitialLinkHandled();
      case SignInFailure(:final message):
        return InitialLinkError(message);
      case SignInRequiresMfa():
        return const InitialLinkError('MFA required; complete sign-in in app.');
    }
  }

  /// Listen for links when app is already running (e.g. from background).
  void listenForLinks(void Function(Uri uri) onLink) {
    _appLinks.uriLinkStream.listen(onLink);
  }
}
