// lib/features/booking/data/public_booking_config_resolver.dart
//
// Commit 17: Resolves public booking config for the availability engine.
// Reads only from the mirror (public/config/publicBooking/config). Never falls back to private settings.

import 'dart:developer' as dev;

import '../../../data/repositories/public_booking_mirror_repository.dart';
import '../../../models/public_booking_config_v1.dart';

/// Resolves config for public booking / availability. Uses mirror only; returns defaults if missing.
class PublicBookingConfigResolver {
  PublicBookingConfigResolver(this._mirrorRepo);

  final PublicBookingMirrorRepository _mirrorRepo;

  /// Returns config from mirror, or defaults and logs a warning. Does NOT read private settings.
  Future<PublicBookingConfigV1> resolve(String clinicId) async {
    final c = clinicId.trim();
    if (c.isEmpty) {
      dev.log('public booking config resolve: empty clinicId; using defaults');
      return PublicBookingConfigV1.defaults;
    }

    final config = await _mirrorRepo.getConfig(c);
    if (config == null) {
      dev.log(
        'public booking config missing; using defaults',
        name: 'PublicBookingConfigResolver',
      );
      return PublicBookingConfigV1.defaults;
    }
    return config;
  }
}
