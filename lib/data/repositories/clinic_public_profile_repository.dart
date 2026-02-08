// lib/data/repositories/clinic_public_profile_repository.dart
//
// Fetches clinics/{clinicId}/public/profile (read-only, pre-auth branding).

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/clinic_public_profile.dart';

class ClinicPublicProfileRepository {
  ClinicPublicProfileRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const String _profileDocId = 'profile';

  /// One-shot read of clinic public profile. Returns fallback (KineticDx) if missing.
  Future<ClinicPublicProfile> getProfile(String clinicId) async {
    final c = clinicId.trim();
    if (c.isEmpty) {
      return const ClinicPublicProfile(displayName: 'KineticDx');
    }

    final ref = _db
        .collection('clinics')
        .doc(c)
        .collection('public')
        .doc(_profileDocId);

    final snap = await ref.get();
    if (!snap.exists) {
      return const ClinicPublicProfile(displayName: 'KineticDx');
    }
    return ClinicPublicProfile.fromMap(snap.data());
  }

  /// Stream of clinic public profile for reactive UI.
  Stream<ClinicPublicProfile> watchProfile(String clinicId) {
    final c = clinicId.trim();
    if (c.isEmpty) {
      return Stream.value(const ClinicPublicProfile(displayName: 'KineticDx'));
    }

    return _db
        .collection('clinics')
        .doc(c)
        .collection('public')
        .doc(_profileDocId)
        .snapshots()
        .map((snap) => ClinicPublicProfile.fromMap(snap.data()));
  }
}
