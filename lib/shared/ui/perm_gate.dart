// lib/shared/ui/perm_gate.dart
//
// UI guard: shows [child] only when membership is active and the user has
// the required permission (boolean flag). Otherwise shows loading or
// [PermissionDeniedEmptyState]. Use on every Settings screen.
// Rules: do not infer role; use boolean flags only. Missing/inactive membership
// blocks all gated screens.
//
// Stability: after [loadingTimeout], shows "Retry" so the user is never stuck on
// an infinite loading spinner (e.g. if session never loads due to stream error).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/clinic_context.dart';
import '../../data/repositories/memberships_repository.dart';
import 'permission_denied_empty_state.dart';

/// Duration after which to show "Retry" when session has not loaded.
const Duration _loadingTimeout = Duration(seconds: 15);

/// Wraps [child] and shows it only when:
/// - [ClinicContext] has a session (membership loaded), and
/// - membership is active, and
/// - [requiredPerm] is true in the session's permission map.
///
/// Otherwise shows a loading spinner (no session yet), a timeout retry state,
/// or [PermissionDeniedEmptyState] (inactive or missing permission).
class PermGate extends StatefulWidget {
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
  State<PermGate> createState() => _PermGateState();
}

class _PermGateState extends State<PermGate> {
  Timer? _timeoutTimer;
  bool _showRetry = false;

  void _startTimeoutTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(_loadingTimeout, () {
      if (mounted) setState(() => _showRetry = true);
      _timeoutTimer = null;
    });
  }

  void _cancelTimeoutTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    if (_showRetry && mounted) setState(() => _showRetry = false);
  }

  void _retry() {
    _cancelTimeoutTimer();
    try {
      context.read<MembershipsRepository>().clearMembershipStreamCache();
      context.read<ClinicContext>().notifySessionListeners();
    } catch (_) {
      // If repos not available (e.g. wrong route), at least hide retry and let loading show again
      if (mounted) setState(() => _showRetry = false);
    }
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clinicCtx = context.watch<ClinicContext>();

    if (clinicCtx.hasSession) {
      _cancelTimeoutTimer();
      final session = clinicCtx.sessionOrNull!;
      if (!session.isActive) {
        return const PermissionDeniedEmptyState(
          title: 'Access denied',
          message: 'Your membership for this clinic is not active. '
              'Contact an admin to restore access.',
          icon: Icons.person_off_outlined,
        );
      }
      if (!session.can(widget.requiredPerm)) {
        return PermissionDeniedEmptyState(
          title: 'Permission denied',
          message: widget.message ??
              'You need the "${widget.requiredPerm}" permission to view this. '
                  'Ask an admin to update your role.',
        );
      }
      return widget.child;
    }

    // No session yet: show loading, or after timeout show retry
    if (clinicCtx.hasClinic) {
      if (!_showRetry) {
        _startTimeoutTimer();
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                'Loading is taking longer than expected',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Check your connection and try again. If it keeps happening, sign out and back in.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    _cancelTimeoutTimer();
    return const Center(child: CircularProgressIndicator());
  }
}
