import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repositories/memberships_repository.dart';
import '../models/clinic_permissions.dart';
import '../models/membership.dart';
import 'clinic_context.dart';
import 'clinic_session.dart';

class ClinicSessionScope extends StatelessWidget {
  final Widget child;

  const ClinicSessionScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final clinicCtx = context.watch<ClinicContext>();

    if (user == null) return child;
    if (!clinicCtx.hasClinic) return child;

    final repo = context.read<MembershipsRepository>();

    return StreamProvider<Membership?>.value(
      value: repo.watchClinicMembership(
        clinicId: clinicCtx.clinicId,
        uid: user.uid,
      ),
      initialData: null,
      catchError: (_, __) => null,
      child: ProxyProvider<Membership?, ClinicSession?>(
        update: (_, membership, __) {
          if (membership == null) return null;

          final perms = ClinicPermissions(membership.permissions);

          return ClinicSession(
            clinicId: membership.clinicId,
            membership: membership,
            permissions: perms,
          );
        },
        child: child,
      ),
    );
  }
}
