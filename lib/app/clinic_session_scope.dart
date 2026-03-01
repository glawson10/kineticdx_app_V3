import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repositories/memberships_repository.dart';
import '../models/clinic_permissions.dart';
import '../models/membership.dart';
import 'clinic_context.dart';
import 'clinic_session.dart';

/// Single source of membership stream: one StreamBuilder here so the shell
/// does not create a second listener (which could cause stuck loading on tab switch).
class ClinicSessionScope extends StatelessWidget {
  const ClinicSessionScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final clinicCtx = context.watch<ClinicContext>();

    if (user == null) return child;
    if (!clinicCtx.hasClinic) return child;

    final repo = context.read<MembershipsRepository>();
    final stream = repo.watchClinicMembership(
      clinicId: clinicCtx.clinicId,
      uid: user.uid,
    );

    final clinicId = clinicCtx.clinicId;

    return StreamBuilder<Membership?>(
      stream: stream,
      builder: (context, snap) {
        // Set session as soon as we have membership so PermGate and shell see it
        // in the same frame (avoids stuck loading on Settings/Calendar tab).
        if (snap.hasData && snap.data != null) {
          final membership = snap.data!;
          final ctx = context.read<ClinicContext>();
          final needsSet = !ctx.hasSession ||
              ctx.sessionOrNull?.clinicId != clinicId ||
              ctx.sessionOrNull?.membership.active != membership.active ||
              !ctx.hasUid ||
              ctx.uidOrNull != user.uid;
          if (needsSet) {
            ctx.setSessionSilent(
              clinicId: clinicId,
              membership: membership,
              uid: user.uid,
            );
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                context.read<ClinicContext>().notifySessionListeners();
              }
            });
          }
        }
        return MultiProvider(
          providers: [
            Provider<AsyncSnapshot<Membership?>>.value(value: snap),
            Provider<Membership?>.value(value: snap.hasData ? snap.data : null),
            ProxyProvider<Membership?, ClinicSession?>(
              update: (_, membership, __) {
                if (membership == null) return null;
                final perms = ClinicPermissions(membership.permissions);
                return ClinicSession(
                  clinicId: membership.clinicId,
                  membership: membership,
                  permissions: perms,
                );
              },
            ),
          ],
          child: child,
        );
      },
    );
  }
}
