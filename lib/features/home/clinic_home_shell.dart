// lib/features/home/clinic_home_shell.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/clinic_context.dart';
import '../../data/repositories/memberships_repository.dart';
import '../booking/ui/booking_calendar_screen.dart';
import '../shell/clinician_shell.dart';

/// Default post-clinic-selection shell.
/// HomePage pushes this after you pick a clinic.
///
/// ✅ Bootstraps ClinicContext.session from membership stream
/// ✅ Also sets ClinicContext.uid for permission/self-gating
class ClinicHomeShell extends StatelessWidget {
  const ClinicHomeShell({super.key});

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
    final repo = context.read<MembershipsRepository>();

    return StreamBuilder(
      stream: repo.watchClinicMembership(clinicId: clinicId, uid: user.uid),
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            body: Center(child: Text('Failed to load membership: ${snap.error}')),
          );
        }
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final membership = snap.data;
        if (membership == null) {
          return const Scaffold(
            body: Center(child: Text('No membership found for this clinic.')),
          );
        }

        // ✅ Push session into ClinicContext
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = context.read<ClinicContext>();

          final needsInit = !ctx.hasSession;
          final clinicChanged = ctx.sessionOrNull?.clinicId != clinicId;

          // If membership "active" flipped, permissions likely changed too.
          // (Optional: if your Membership model has updatedAt / permissions hash,
          // compare that as well.)
          final activeChanged =
              ctx.sessionOrNull?.membership.active != membership.active;

          // Also ensure uid is present / correct (for self-gating)
          final uidMissingOrChanged = !ctx.hasUid || (ctx.uidOrNull != user.uid);

          if (needsInit || clinicChanged || activeChanged || uidMissingOrChanged) {
            ctx.setSession(
              clinicId: clinicId,
              membership: membership,
              uid: user.uid, // ✅ NEW
            );
          }
        });

        return const ClinicianShell(
          selected: ClinicianTab.calendar,
          child: BookingCalendarScreen(),
        );
      },
    );
  }
}
