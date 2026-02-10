// lib/app/callable_error_mapping.dart
//
// Maps Cloud Functions (callable) errors to user-friendly messages.
// Used for invite accept, invite send, update member, suspend member.

import 'package:cloud_functions/cloud_functions.dart';

/// Returns a short user-facing message for callable errors (invite/membership).
String messageForCallableError(Object error, {String fallback = 'Something went wrong.'}) {
  if (error is FirebaseFunctionsException) {
    final code = error.code;
    final msg = (error.message ?? '').trim();
    switch (code) {
      case 'permission-denied':
        return msg.isNotEmpty ? msg : "You don't have access to do this.";
      case 'unauthenticated':
        return 'Please sign in.';
      case 'not-found':
        return msg.isNotEmpty ? msg : 'Invite or member not found.';
      case 'failed-precondition':
        return msg.isNotEmpty ? msg : 'Invite expired, already used, or you cannot change the last owner.';
      case 'invalid-argument':
        return msg.isNotEmpty ? msg : 'Invalid request.';
      case 'deadline-exceeded':
        return msg.isNotEmpty ? msg : 'Invite has expired.';
      default:
        return msg.isNotEmpty ? msg : fallback;
    }
  }
  final s = error.toString();
  if (s.isEmpty) return fallback;
  return s;
}
