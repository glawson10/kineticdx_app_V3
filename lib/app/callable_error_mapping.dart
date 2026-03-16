// lib/app/callable_error_mapping.dart
//
// Maps Cloud Functions (callable) errors to user-friendly messages.
// Used for invite accept, invite send, update member, suspend member.

import 'package:cloud_functions/cloud_functions.dart';

/// Returns a short user-facing message for callable errors (invite/membership).
/// [logHint] Optional Cloud Function name to check in logs (e.g. 'settingsSetAppointmentTypeActive').
String messageForCallableError(Object error,
    {String fallback = 'Something went wrong.', String? logHint}) {
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
        return msg.isNotEmpty
            ? msg
            : 'Invite expired, already used, or you cannot change the last owner.';
      case 'invalid-argument':
        return msg.isNotEmpty ? msg : 'Invalid request.';
      case 'deadline-exceeded':
        return msg.isNotEmpty ? msg : 'Invite has expired.';
      case 'internal':
      case 'unknown':
        if (msg.isNotEmpty && msg != 'internal') return msg;
        final base =
            'A server error occurred. Please try again. If it keeps happening, check Cloud Functions logs or redeploy.';
        if (logHint != null && logHint.isNotEmpty) {
          return '$base Check logs for: $logHint';
        }
        return base;
      default:
        return msg.isNotEmpty ? msg : fallback;
    }
  }
  final s = error.toString();
  if (s.isEmpty) return fallback;
  return s;
}
