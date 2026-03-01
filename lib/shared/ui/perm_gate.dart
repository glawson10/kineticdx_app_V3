// lib/shared/ui/perm_gate.dart
//
// UI guard: shows [child] only when membership is active and the user has
// the required permission (boolean flag). Otherwise shows loading or
// [PermissionDeniedEmptyState]. Use on every Settings screen.
// Rules: do not infer role; use boolean flags only. Missing/inactive membership
// blocks all gated screens.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/clinic_context.dart';
import '../../debug_session_log.dart';
import 'permission_denied_empty_state.dart';

/// Wraps [child] and shows it only when:
/// - [ClinicContext] has a session (membership loaded), and
/// - membership is active, and
/// - [requiredPerm] is true in the session's permission map.
///
/// Otherwise shows a loading spinner (no session yet) or
/// [PermissionDeniedEmptyState] (inactive or missing permission).
class PermGate extends StatelessWidget {
  const PermGate({
    super.key,
    required this.requiredPerm,
    required this.child,
    this.message,
  });

  /// Permission key (e.g. "settings.read", "manageClinic"). Must be true in membership flags.
  final String requiredPerm;

  /// Content to show when the user has the permission and membership is active.
  final Widget child;

  /// Optional message for the permission-denied state.
  final String? message;

  @override
  Widget build(BuildContext context) {
    final clinicCtx = context.watch<ClinicContext>();

    // #region agent log
    if (!clinicCtx.hasSession) {
      debugSessionLog(
        'perm_gate.dart:build',
        'PermGate no session',
        {'requiredPerm': requiredPerm},
        'H2',
      );
    } else {
      debugSessionLog(
        'perm_gate.dart:build',
        'PermGate has session',
        {'requiredPerm': requiredPerm},
        'H2',
      );
    }
    // #endregion
    if (!clinicCtx.hasSession) {
      return const Center(child: CircularProgressIndicator());
    }

    final session = clinicCtx.sessionOrNull!;
    if (!session.isActive) {
      return const PermissionDeniedEmptyState(
        title: 'Access denied',
        message: 'Your membership for this clinic is not active. '
            'Contact an admin to restore access.',
        icon: Icons.person_off_outlined,
      );
    }

    if (!session.can(requiredPerm)) {
      return PermissionDeniedEmptyState(
        title: 'Permission denied',
        message: message ??
            'You need the "$requiredPerm" permission to view this. '
                'Ask an admin to update your role.',
      );
    }

    return child;
  }
}
