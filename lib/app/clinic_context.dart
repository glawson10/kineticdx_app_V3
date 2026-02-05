// lib/app/clinic_context.dart
import 'package:flutter/foundation.dart';

import '../models/clinic_permissions.dart';
import '../app/clinic_session.dart';
import '../models/membership.dart';

class ClinicContext extends ChangeNotifier {
  String? _clinicId;
  ClinicSession? _session;

  // ✅ NEW: current signed-in Firebase Auth uid (for self-gating, audit, etc.)
  String? _uid;

  // ─────────────────────────────
  // Clinic selection
  // ─────────────────────────────

  bool get hasClinic => _clinicId != null;

  String get clinicId {
    final v = _clinicId;
    if (v == null) throw StateError('ClinicContext not initialised');
    return v;
  }

  void setClinic(String clinicId) {
    final v = clinicId.trim();
    if (v.isEmpty) throw ArgumentError('clinicId cannot be empty');

    // If switching clinic, drop session (it belongs to previous clinic)
    if (_clinicId != v) {
      _clinicId = v;
      _session = null;
      notifyListeners();
    }
  }

  // ─────────────────────────────
  // Identity (auth uid)
  // ─────────────────────────────

  bool get hasUid => (_uid ?? '').trim().isNotEmpty;

  /// Non-throwing access (useful during boot).
  String? get uidOrNull => _uid;

  /// Throwing access (keeps mistakes loud in dev).
  String get uid {
    final v = (_uid ?? '').trim();
    if (v.isEmpty) {
      throw StateError('ClinicContext.uid not initialised (pass uid into setSession)');
    }
    return v;
  }

  /// Optional setter in case you want to update uid separately during auth boot.
  /// Most of the time you should just pass uid into setSession().
  void setUid(String uid) {
    final v = uid.trim();
    if (v.isEmpty) throw ArgumentError('uid cannot be empty');

    if (_uid != v) {
      _uid = v;
      notifyListeners();
    }
  }

  // ─────────────────────────────
  // Session (membership + perms)
  // ─────────────────────────────

  bool get hasSession => _session != null;

  /// Non-throwing access for UI while bootstrapping.
  ClinicSession? get sessionOrNull => _session;

  /// Throwing access (keep this so you catch mistakes in dev).
  ClinicSession get session {
    final s = _session;
    if (s == null) {
      throw StateError('ClinicContext.session not initialised (call setSession)');
    }
    return s;
  }

  /// Convenience: direct permission map (raw) for guards.
  Map<String, dynamic> get permissions =>
      _session?.permissionsRaw ?? const <String, dynamic>{};

  /// ✅ Updated: include uid so screens can do "self" checks safely.
  void setSession({
    required String clinicId,
    required Membership membership,
    required String uid,
  }) {
    final c = clinicId.trim();
    if (c.isEmpty) throw ArgumentError('clinicId cannot be empty');

    final u = uid.trim();
    if (u.isEmpty) throw ArgumentError('uid cannot be empty');

    final perms = ClinicPermissions(membership.permissions);

    _clinicId = c;
    _uid = u;
    _session = ClinicSession(
      clinicId: c,
      membership: membership,
      permissions: perms,
    );

    notifyListeners();
  }

  void clear() {
    if (_clinicId == null && _session == null && _uid == null) return;
    _clinicId = null;
    _session = null;
    _uid = null;
    notifyListeners();
  }
}
