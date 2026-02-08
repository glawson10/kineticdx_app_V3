import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:provider/provider.dart';

import '../app/clinic_context.dart';
import '../app/last_clinic_store.dart';
import '../data/repositories/memberships_repository.dart';
import '../models/membership_index.dart';

import '../features/clinic/settings/create_clinic_page.dart';
import '../features/home/home_page.dart';
import '../features/home/clinic_home_shell.dart';

class ClinicOnboardingGate extends StatefulWidget {
  const ClinicOnboardingGate({super.key, this.initialClinicId});

  /// When set (e.g. from /c/{clinicId} portal), enter this clinic directly if user is a member.
  final String? initialClinicId;

  @override
  State<ClinicOnboardingGate> createState() => _ClinicOnboardingGateState();
}

class _ClinicOnboardingGateState extends State<ClinicOnboardingGate> {
  bool _decisionScheduled = false;
  bool _showPicker = false;

  void _scheduleDecisionOnce(Future<void> Function() fn) {
    if (_decisionScheduled) return;
    _decisionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      fn();
    });
  }

  Future<void> _syncMyDisplayName(String clinicId) async {
    final c = clinicId.trim();
    if (c.isEmpty) return;

    try {
      final fn = FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('syncMyDisplayNameFn');

      final res = await fn.call(<String, dynamic>{
        'clinicId': c,
      });

      if (kDebugMode) {
        debugPrint('[syncMyDisplayNameFn] ok res=${res.data}');
      }
    } catch (e) {
      // Non-fatal: UI can still fall back to invitedEmail/uid.
      if (kDebugMode) {
        debugPrint('❌ [syncMyDisplayNameFn] failed: $e');
      }
    }
  }

  Future<void> _enterClinic({
    required String uid,
    required String clinicId,
  }) async {
    final c = clinicId.trim();
    if (c.isEmpty) return;

    // Set clinic in memory
    context.read<ClinicContext>().setClinic(c);

    // ✅ Ensure membership doc has displayName (updates /memberships + /members)
    await _syncMyDisplayName(c);

    // Remember last clinic
    await LastClinicStore.setLastClinic(uid, c);

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ClinicHomeShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    final membershipsRepo = context.read<MembershipsRepository>();

    return StreamBuilder<List<MembershipIndex>>(
      stream: membershipsRepo.membershipsForUser(user.uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Failed to load memberships: ${snap.error}'),
              ),
            ),
          );
        }

        final memberships = (snap.data ?? const <MembershipIndex>[])
            .where((m) => m.active == true)
            .toList();

        // 0 clinics -> create clinic
        if (memberships.isEmpty) {
          return const CreateClinicPage();
        }

        // If we already decided to show picker, show it and stop.
        if (_showPicker) {
          return HomePage(
            memberships: memberships,
            onPick: (clinicId) =>
                _enterClinic(uid: user.uid, clinicId: clinicId),
          );
        }

        // Otherwise, decide once: portal clinic / last clinic / single clinic / else show picker.
        _scheduleDecisionOnce(() async {
          final uid = user.uid;
          final initialId = widget.initialClinicId?.trim();

          // 0) portal: if we came from /c/{clinicId}, enter that clinic if member
          if (initialId != null &&
              initialId.isNotEmpty &&
              memberships.any((m) => m.clinicId == initialId)) {
            await _enterClinic(uid: uid, clinicId: initialId);
            return;
          }

          // 1) prefer last clinic if still valid
          final last = await LastClinicStore.getLastClinic(uid);
          final lastValid =
              last != null && memberships.any((m) => m.clinicId == last);

          if (lastValid) {
            await _enterClinic(uid: uid, clinicId: last);
            return;
          }

          // 2) if exactly one clinic, enter it
          if (memberships.length == 1) {
            await _enterClinic(uid: uid, clinicId: memberships.first.clinicId);
            return;
          }

          // 3) else show picker
          if (!mounted) return;
          setState(() {
            _showPicker = true;
          });
        });

        // While decision is pending (or navigation about to happen), show loading.
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}
