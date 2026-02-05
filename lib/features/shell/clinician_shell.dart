// lib/features/shell/clinician_shell.dart
//
// ✅ Updated in full (Option A):
// - Prevents tab flicker (e.g., "Invoices" briefly appearing) by NOT rendering
//   the navigation shell until ClinicContext.session/perms are ready.
// - When clinic selected but session not yet loaded, shows a simple loading scaffold.
// - Everything else unchanged.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/clinic_context.dart';
import '../../app/clinic_session.dart';

import '../public/ui/intro_screen.dart';

// Screens
import '/features/booking/ui/booking_calendar_screen.dart';
import '/features/patients/patient_finder_screen.dart';
import '/features/payments/ui/payment_qr_screen.dart';

// Clinic settings
import '/features/clinic_settings/clinic_profile_screen.dart';

// Preassessment list
import 'package:kineticdx_app_v3/preassessment/clinician/preassessments_list_screen.dart';

enum ClinicianTab {
  calendar,
  patients,
  preassess,
  exercises,
  invoices,
  paymentQr,
  settings,

  // ✅ Always last
  publicPortal,
}

class ClinicianShell extends StatelessWidget {
  final ClinicianTab selected;
  final Widget child;
  final String? title;

  const ClinicianShell({
    super.key,
    required this.selected,
    required this.child,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final clinicCtx = context.watch<ClinicContext>();

    // If clinic context isn't ready, just show the child (no shell).
    if (!clinicCtx.hasClinic) {
      return Scaffold(body: child);
    }

    // ✅ KEY FIX:
    // Once a clinic is selected, we wait for session/perms to load before
    // building NavigationRail/NavigationBar. This prevents "null perms" causing
    // tabs like Invoices to flash then disappear.
    if (!clinicCtx.hasSession) {
      return Scaffold(
        appBar: AppBar(title: const Text('Loading clinic…')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final isWide = c.maxWidth >= 1000;

        return PopScope<Object?>(
          canPop: false,
          onPopInvokedWithResult: (_, __) {
            if (selected != ClinicianTab.calendar) {
              _go(context, ClinicianTab.calendar);
            }
          },
          child: isWide
              ? _WideScaffold(selected: selected, title: title, child: child)
              : _NarrowScaffold(selected: selected, title: title, child: child),
        );
      },
    );
  }
}

class _WideScaffold extends StatelessWidget {
  final ClinicianTab selected;
  final Widget child;
  final String? title;

  const _WideScaffold({
    required this.selected,
    required this.child,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final tabs = _visibleTabs(context);
    final selectedIndex = _selectedIndex(tabs, selected);

    return Scaffold(
      appBar: AppBar(
        title: Text(title ?? _labelFor(selected)),
        actions: _appBarActions(context),
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selectedIndex,
            labelType: NavigationRailLabelType.all,
            destinations: tabs
                .map(
                  (t) => NavigationRailDestination(
                    icon: Icon(_iconFor(t)),
                    label: Text(_labelFor(t)),
                  ),
                )
                .toList(),
            onDestinationSelected: (i) {
              final next = tabs[i];
              if (next != selected) _go(context, next);
            },
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _NarrowScaffold extends StatelessWidget {
  final ClinicianTab selected;
  final Widget child;
  final String? title;

  const _NarrowScaffold({
    required this.selected,
    required this.child,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final tabs = _visibleTabs(context);
    final selectedIndex = _selectedIndex(tabs, selected);

    return Scaffold(
      appBar: AppBar(
        title: Text(title ?? _labelFor(selected)),
        actions: _appBarActions(context),
      ),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (i) {
          final next = tabs[i];
          if (next != selected) _go(context, next);
        },
        destinations: tabs
            .map(
              (t) => NavigationDestination(
                icon: Icon(_iconFor(t)),
                label: _labelFor(t),
              ),
            )
            .toList(),
      ),
    );
  }
}

List<ClinicianTab> _visibleTabs(BuildContext context) {
  final session = context.watch<ClinicSession?>();
  final perms = session?.permissions;

  bool has(String key) => perms?.has(key) == true;

  final tabs = <ClinicianTab>[];

  // Note: with the session gate in ClinicianShell, perms should not be null here
  // during normal operation. But leaving the checks defensive is fine.
  if (perms == null || has('schedule.read')) tabs.add(ClinicianTab.calendar);
  if (perms == null || has('patients.read')) tabs.add(ClinicianTab.patients);
  if (perms == null || has('clinical.read') || has('notes.read')) {
    tabs.add(ClinicianTab.preassess);
  }

  tabs.add(ClinicianTab.exercises);
  if (perms == null || has('billing.read')) tabs.add(ClinicianTab.invoices);
  tabs.add(ClinicianTab.paymentQr);
  if (perms == null || has('settings.read')) tabs.add(ClinicianTab.settings);

  // ✅ Always last
  tabs.add(ClinicianTab.publicPortal);

  return tabs;
}

int _selectedIndex(List<ClinicianTab> tabs, ClinicianTab selected) {
  final i = tabs.indexOf(selected);
  return i >= 0 ? i : 0;
}

List<Widget> _appBarActions(BuildContext context) {
  return [
    IconButton(
      tooltip: 'Logout',
      icon: const Icon(Icons.logout),
      onPressed: () async {
        await FirebaseAuth.instance.signOut();
        if (!context.mounted) return;
        context.read<ClinicContext>().clear();
      },
    ),
  ];
}

String _labelFor(ClinicianTab t) {
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
      return 'Public Portal';
  }
}

IconData _iconFor(ClinicianTab t) {
  switch (t) {
    case ClinicianTab.calendar:
      return Icons.calendar_today;
    case ClinicianTab.patients:
      return Icons.people;
    case ClinicianTab.preassess:
      return Icons.assignment;
    case ClinicianTab.exercises:
      return Icons.fitness_center;
    case ClinicianTab.invoices:
      return Icons.request_quote;
    case ClinicianTab.paymentQr:
      return Icons.qr_code_2;
    case ClinicianTab.settings:
      return Icons.settings;
    case ClinicianTab.publicPortal:
      return Icons.public;
  }
}

void _go(BuildContext context, ClinicianTab t) {
  if (t == ClinicianTab.publicPortal) {
    final clinicCtx = context.read<ClinicContext>();

    // ✅ Leave clinician shell and open PUBLIC intro
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => IntroScreen(clinicId: clinicCtx.clinicId),
      ),
    );
    return;
  }

  Widget page;
  String? title;

  switch (t) {
    case ClinicianTab.calendar:
      title = 'Booking Calendar';
      page = const BookingCalendarScreen();
      break;
    case ClinicianTab.patients:
      title = 'Patients';
      page = const PatientFinderScreen();
      break;
    case ClinicianTab.preassess:
      title = 'Pre-Assessments';
      page = const PreAssessmentsListScreen();
      break;
    case ClinicianTab.paymentQr:
      title = 'Payment QR';
      page = const PaymentQrScreen();
      break;
    case ClinicianTab.exercises:
      title = 'Exercises';
      page = const Center(child: Text('Exercises (next)'));
      break;
    case ClinicianTab.invoices:
      title = 'Invoices';
      page = const Center(child: Text('Invoices (next)'));
      break;
    case ClinicianTab.settings:
      title = 'Clinic Settings';
      page = const ClinicProfileScreen();
      break;
    case ClinicianTab.publicPortal:
      page = const SizedBox.shrink();
      break;
  }

  Navigator.of(context).pushReplacement(
    MaterialPageRoute(
      builder: (_) => ClinicianShell(
        selected: t,
        title: title,
        child: page,
      ),
    ),
  );
}
