import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../app/clinic_context.dart';
import '../app/last_clinic_store.dart';
import '../data/repositories/memberships_repository.dart';
import '../data/repositories/staff_profile_repository.dart';
import '../models/membership_index.dart';

import '../features/clinic/settings/create_clinic_page.dart';
import '../features/home/home_page.dart';
import '../features/home/clinic_home_shell.dart';
import '../features/staff/ui/staff_profile_onboarding_screen.dart';

class ClinicOnboardingGate extends StatefulWidget {
  const ClinicOnboardingGate({
    super.key,
    this.initialClinicId,
    this.initialSettingsSection,
  });

  /// When set (e.g. from /c/{clinicId} portal), enter this clinic directly if user is a member.
  final String? initialClinicId;

  /// When set (e.g. from /c/{clinicId}/settings[/section] deep link), after entering open Settings tab with this section.
  final String? initialSettingsSection;

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

  /// Check if staff profile is incomplete (missing displayName)
  Future<bool> _isProfileIncomplete(String clinicId, String uid) async {
    if (!mounted) return true;
    try {
      final profileRepo = context.read<StaffProfileRepository>();

      // Use a one-time read via stream with timeout
      DocumentSnapshot<Map<String, dynamic>>? snap;
      try {
        snap = await profileRepo
            .watchStaffProfile(clinicId, uid)
            .timeout(const Duration(seconds: 3))
            .first;
      } on TimeoutException {
        if (kDebugMode) {
          debugPrint(
              '[ClinicOnboardingGate] Profile check timed out, assuming incomplete');
        }
        return true;
      }

      if (!mounted) return true;

      if (!snap.exists) {
        if (kDebugMode) {
          debugPrint('[ClinicOnboardingGate] Profile does not exist');
        }
        return true;
      }

      final data = snap.data();
      if (data == null) {
        if (kDebugMode) {
          debugPrint('[ClinicOnboardingGate] Profile data is null');
        }
        return true;
      }

      final displayName = (data['displayName'] ?? '').toString().trim();
      if (displayName.isEmpty) {
        if (kDebugMode) {
          debugPrint('[ClinicOnboardingGate] Profile missing displayName');
        }
        return true;
      }

      if (kDebugMode) {
        debugPrint(
            '[ClinicOnboardingGate] Profile is complete: displayName=$displayName');
      }
      return false;
    } catch (e) {
      // On error, assume incomplete to be safe
      if (kDebugMode) {
        debugPrint('[ClinicOnboardingGate] Error checking profile: $e');
      }
      return true;
    }
  }

  Future<void> _enterClinic({
    required String uid,
    required String clinicId,
    String? initialSettingsSection,
  }) async {
    final c = clinicId.trim();
    if (c.isEmpty) return;

    // Set clinic in memory
    context.read<ClinicContext>().setClinic(c);

    // ✅ Ensure membership doc has displayName (updates /memberships + /members)
    await _syncMyDisplayName(c);

    // Check if staff profile needs completion
    final needsOnboarding = await _isProfileIncomplete(c, uid);

    if (!mounted) return;

    if (needsOnboarding) {
      // Show onboarding screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => StaffProfileOnboardingScreen(clinicId: c),
        ),
      );
      return;
    }

    // Remember last clinic
    await LastClinicStore.setLastClinic(uid, c);

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ClinicHomeShell(
          initialSettingsSection: initialSettingsSection,
        ),
      ),
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
      stream: membershipsRepo.membershipsForUser(user.uid).timeout(
        const Duration(seconds: 10),
        onTimeout: (sink) {
          if (kDebugMode) {
            debugPrint(
                '[ClinicOnboardingGate] Stream timeout after 10 seconds');
          }
          sink.add(const <MembershipIndex>[]); // Emit empty list on timeout
          sink.close();
        },
      ),
      builder: (context, snap) {
        // Debug logging
        if (kDebugMode) {
          debugPrint(
              '[ClinicOnboardingGate] Stream state: ${snap.connectionState}, hasData: ${snap.hasData}, hasError: ${snap.hasError}');
          if (snap.hasData) {
            debugPrint(
                '[ClinicOnboardingGate] Memberships count: ${snap.data?.length ?? 0}');
            if ((snap.data?.length ?? 0) > 0) {
              for (final m in snap.data!) {
                debugPrint('  - ${m.clinicId}: active=${m.active}');
              }
            }
          }
          if (snap.hasError) {
            debugPrint('[ClinicOnboardingGate] Stream error: ${snap.error}');
          }
        }

        if (snap.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Loading memberships...',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (kDebugMode) ...[
                    const SizedBox(height: 8),
                    Text(
                      'UID: ${user.uid}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Error')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load memberships',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snap.error}',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    if (kDebugMode) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Check Firestore: users/${user.uid}/memberships/',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }

        final memberships = (snap.data ?? const <MembershipIndex>[])
            .where((m) => m.active == true)
            .toList();

        if (kDebugMode) {
          debugPrint(
              '[ClinicOnboardingGate] Active memberships: ${memberships.length}');
        }

        // 0 clinics -> create clinic
        if (memberships.isEmpty) {
          if (kDebugMode) {
            debugPrint(
                '[ClinicOnboardingGate] No active memberships found. Showing CreateClinicPage.');
          }
          return Scaffold(
            appBar: AppBar(title: const Text('Welcome')),
            body: const CreateClinicPage(),
          );
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
            await _enterClinic(
              uid: uid,
              clinicId: last,
              initialSettingsSection: widget.initialSettingsSection,
            );
            return;
          }

          // 2) if exactly one clinic, enter it
          if (memberships.length == 1) {
            await _enterClinic(
              uid: uid,
              clinicId: memberships.first.clinicId,
              initialSettingsSection: widget.initialSettingsSection,
            );
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
