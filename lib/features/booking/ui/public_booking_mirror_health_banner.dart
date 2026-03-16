// lib/features/booking/ui/public_booking_mirror_health_banner.dart
//
// Commit 17: Shows banner when public config doc is missing. Admin can trigger rebuild.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/clinic_context.dart';
import '../../../data/repositories/public_booking_mirror_repository.dart';

/// Wraps [child]. If mirror config is missing, shows a banner (admin: message + rebuild button; public: generic message).
class PublicBookingMirrorHealthBanner extends StatelessWidget {
  const PublicBookingMirrorHealthBanner({
    super.key,
    required this.clinicId,
    required this.child,
  });

  final String clinicId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<PublicBookingMirrorRepository>();
    return StreamBuilder<dynamic>(
      stream: repo.streamConfig(clinicId.trim()),
      builder: (context, snap) {
        final config = snap.data;
        if (config != null) return child;

        final canManage = _canRebuild(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: canManage
                  ? Theme.of(context).colorScheme.errorContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          canManage
                              ? 'Public booking config has not been published yet. '
                                'Open Settings → Public booking and save once, or run rebuild below.'
                              : 'Booking is not available at the moment.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      if (canManage) ...[
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: () => _rebuildProjection(context, clinicId),
                          child: const Text('Rebuild'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: child),
          ],
        );
      },
    );
  }

  bool _canRebuild(BuildContext context) {
    try {
      final clinicCtx = context.read<ClinicContext>();
      if (!clinicCtx.hasSession) return false;
      return clinicCtx.session.permissions.has('settings.write');
    } catch (_) {
      return false;
    }
  }

  Future<void> _rebuildProjection(BuildContext context, String clinicId) async {
    final c = clinicId.trim();
    if (c.isEmpty) return;
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'europe-west3');
      // Rebuild full mirror (practitioners, locations, appointment types) so public booking sees clinicians.
      await fn.httpsCallable('rebuildPublicBookingMirrorFn').call({'clinicId': c});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rebuild started. Practitioners and availability may update in a few seconds.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rebuild failed: $e')),
        );
      }
    }
  }
}
