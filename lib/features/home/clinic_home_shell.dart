// lib/features/home/clinic_home_shell.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/clinic_context.dart';
import '../../debug_session_log.dart';
import '../../data/repositories/clinic_repository.dart';
import '../../data/repositories/memberships_repository.dart';
import '../../models/membership.dart';
import '../billing/ui/invoices_list_screen.dart';
import '../booking/ui/booking_calendar_screen.dart';
import '../patients/patient_finder_screen.dart';
import '../payments/ui/payment_qr_screen.dart';
import '../settings/home/settings_home_screen.dart';
import '../shell/clinician_shell.dart';
import 'package:kineticdx_app_v3/preassessment/clinician/preassessments_list_screen.dart';

/// Default post-clinic-selection shell.
/// HomePage pushes this after you pick a clinic.
///
/// ✅ Bootstraps ClinicContext.session from membership stream
/// ✅ Holds tab state in-place so switching tabs does NOT replace the route
///    (avoids Firestore stream cancel/relisten and shell vanishing).
class ClinicHomeShell extends StatefulWidget {
  const ClinicHomeShell({
    super.key,
    this.initialTab,
    this.initialSettingsSection,
  });

  /// Tab to show initially. When null, defaults to calendar unless [initialSettingsSection] is set (deep link).
  final ClinicianTab? initialTab;

  /// When set (e.g. from /c/{clinicId}/settings deep link), open with Settings tab and this section.
  final String? initialSettingsSection;

  @override
  State<ClinicHomeShell> createState() => _ClinicHomeShellState();
}

class _ClinicHomeShellState extends State<ClinicHomeShell> {
  late ClinicianTab _selectedTab;

  /// When membership load is stuck, show timed-out UI after this duration.
  static const Duration _loadingTimeoutDuration = Duration(seconds: 15);

  Timer? _loadingTimeoutTimer;
  bool _loadingTimedOut = false;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab ??
        (widget.initialSettingsSection != null
            ? ClinicianTab.settings
            : ClinicianTab.calendar);
  }

  @override
  void dispose() {
    _loadingTimeoutTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ClinicHomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab ||
        oldWidget.initialSettingsSection != widget.initialSettingsSection) {
      _selectedTab = widget.initialTab ??
          (widget.initialSettingsSection != null
              ? ClinicianTab.settings
              : ClinicianTab.calendar);
    }
  }

  void _cancelLoadingTimeout() {
    _loadingTimeoutTimer?.cancel();
    _loadingTimeoutTimer = null;
  }

  void _startLoadingTimeout() {
    if (_loadingTimeoutTimer != null) return;
    _loadingTimeoutTimer = Timer(_loadingTimeoutDuration, () {
      if (mounted) setState(() => _loadingTimedOut = true);
      _loadingTimeoutTimer = null;
    });
  }

  void _retryMembershipLoad() {
    _cancelLoadingTimeout();
    setState(() => _loadingTimedOut = false);
    context.read<MembershipsRepository>().clearMembershipStreamCache();
    context.read<ClinicContext>().notifySessionListeners();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    final clinicCtx = context.watch<ClinicContext>();
    if (!clinicCtx.hasClinic) {
      return const Scaffold(body: Center(child: Text('No clinic selected')));
    }

    final clinicId = clinicCtx.clinicId;
    final snap = context.watch<AsyncSnapshot<Membership?>>();

    // #region agent log
    if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
      debugSessionLog(
        'clinic_home_shell.dart:build',
        'Shell membership waiting',
        {'connectionState': snap.connectionState.toString(), 'selectedTab': _selectedTab.name},
        'H1',
      );
    }
    if (snap.hasData) {
      debugSessionLog(
        'clinic_home_shell.dart:build',
        'Shell membership hasData',
        {'selectedTab': _selectedTab.name},
        'H1',
      );
    }
    // #endregion
    if (snap.hasError) {
      if (FirebaseAuth.instance.currentUser == null) {
        return const Scaffold(body: Center(child: Text('Not signed in')));
      }
      return Scaffold(
        body: Center(child: Text('Failed to load membership: ${snap.error}')),
      );
    }

    // When stream is still waiting: if we already have a session for this clinic,
    // build the shell immediately so tab switches never show loading.
    final Membership? membership;
    if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
      final ctx = context.read<ClinicContext>();
      if (ctx.hasSession && ctx.sessionOrNull?.clinicId == clinicId) {
        _cancelLoadingTimeout();
        membership = ctx.sessionOrNull!.membership;
      } else {
        if (!_loadingTimedOut) {
          _startLoadingTimeout();
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return Scaffold(
          body: Center(
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
                    onPressed: _retryMembershipLoad,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    } else {
      _cancelLoadingTimeout();
      membership = snap.data;
    }

    if (membership == null) {
      return const Scaffold(
        body: Center(child: Text('No membership found for this clinic.')),
      );
    }

    // Session is set by ClinicSessionScope when membership data is available.

    final settingsSection = (_selectedTab == ClinicianTab.settings &&
            widget.initialSettingsSection != null)
        ? (widget.initialSettingsSection!.trim().isEmpty
            ? null
            : widget.initialSettingsSection!.trim())
        : null;

    final title = _titleForTab(_selectedTab);
    final child = _childForTab(_selectedTab, clinicId, settingsSection);

    return _SessionTimeoutWrapper(
      clinicId: clinicId,
      child: ClinicianShell(
        selected: _selectedTab,
        title: title,
        child: child,
        onTabChanged: (t) => setState(() => _selectedTab = t),
      ),
    );
  }
}

String? _titleForTab(ClinicianTab t) {
  switch (t) {
    case ClinicianTab.calendar:
      return 'Booking Calendar';
    case ClinicianTab.patients:
      return 'Patients';
    case ClinicianTab.preassess:
      return 'Pre-Assessments';
    case ClinicianTab.exercises:
      return 'Exercises';
    case ClinicianTab.invoices:
      return 'Invoices';
    case ClinicianTab.paymentQr:
      return 'Payment QR';
    case ClinicianTab.settings:
      return 'Clinic Settings';
    case ClinicianTab.publicPortal:
      return null;
  }
}

Widget _childForTab(ClinicianTab t, String clinicId, String? settingsSection) {
  switch (t) {
    case ClinicianTab.calendar:
      return const BookingCalendarScreen();
    case ClinicianTab.patients:
      return const PatientFinderScreen();
    case ClinicianTab.preassess:
      return const PreAssessmentsListScreen();
    case ClinicianTab.exercises:
      return const Center(child: Text('Exercises (next)'));
    case ClinicianTab.invoices:
      return const InvoicesListScreen();
    case ClinicianTab.paymentQr:
      return const PaymentQrScreen();
    case ClinicianTab.settings:
      return SettingsHomeScreen(clinicId: clinicId, initialSection: settingsSection);
    case ClinicianTab.publicPortal:
      return const SizedBox.shrink();
  }
}

/// Default session timeout in minutes when not set in clinic settings.
const int _defaultSessionTimeoutMinutes = 120;

const List<int> _allowedSessionTimeoutMinutes = [30, 60, 120, 180, 240];

/// Wraps the clinician shell and signs out after [sessionTimeoutMinutes] of inactivity.
class _SessionTimeoutWrapper extends StatefulWidget {
  const _SessionTimeoutWrapper({
    required this.clinicId,
    required this.child,
  });

  final String clinicId;
  final Widget child;

  @override
  State<_SessionTimeoutWrapper> createState() => _SessionTimeoutWrapperState();
}

/// Seconds the user has to confirm before being logged out after the inactivity warning.
const int _logoutWarningSeconds = 30;

class _SessionTimeoutWrapperState extends State<_SessionTimeoutWrapper> {
  Timer? _timer;
  Timer? _logoutWarningTimer;
  int _timeoutMinutes = _defaultSessionTimeoutMinutes;
  bool _timerInitialized = false;

  void _resetTimer() {
    _timer?.cancel();
    _logoutWarningTimer?.cancel();
    _logoutWarningTimer = null;
    _timer = Timer(
      Duration(minutes: _timeoutMinutes),
      () {
        if (!mounted) return;
        _showTimeoutWarning();
      },
    );
  }

  void _cancelLogoutWarning() {
    _logoutWarningTimer?.cancel();
    _logoutWarningTimer = null;
  }

  void _showTimeoutWarning() {
    _logoutWarningTimer?.cancel();
    _logoutWarningTimer = Timer(Duration(seconds: _logoutWarningSeconds), () {
      if (!mounted) return;
      _logoutWarningTimer = null;
      Navigator.of(context).pop(true);
      context.read<ClinicContext>().clear();
      FirebaseAuth.instance.signOut();
    });

    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Session timeout'),
        content: Text(
          'You have been inactive. You will be logged out in $_logoutWarningSeconds seconds '
          'if you do not confirm to continue.',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(false);
              _cancelLogoutWarning();
              _resetTimer();
            },
            child: const Text('Stay signed in'),
          ),
        ],
      ),
    ).then((_) => _cancelLogoutWarning());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _logoutWarningTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: context.read<ClinicRepository>().watchClinic(widget.clinicId),
      builder: (context, snap) {
        if (snap.hasData) {
          final data = snap.data!.data() ?? <String, dynamic>{};
          final settings = (data['settings'] is Map)
              ? data['settings'] as Map<dynamic, dynamic>
              : <dynamic, dynamic>{};
          final raw = settings['sessionTimeoutMinutes'];
          final minutes = raw is int && _allowedSessionTimeoutMinutes.contains(raw)
              ? raw
              : _defaultSessionTimeoutMinutes;
          final timeoutChanged = minutes != _timeoutMinutes;
          if (timeoutChanged) _timeoutMinutes = minutes;
          if (!_timerInitialized || timeoutChanged) {
            _timerInitialized = true;
            WidgetsBinding.instance.addPostFrameCallback((_) => _resetTimer());
          }
        }
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _resetTimer(),
          child: widget.child,
        );
      },
    );
  }
}
