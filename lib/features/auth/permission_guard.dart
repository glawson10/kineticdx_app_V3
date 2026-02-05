// lib/features/auth/permission_guard.dart
//
// UI guard helper.
// Lightweight permission facade used for gating buttons/screens.
// Source of truth: ClinicPermissions (wraps the raw permission map).

import '../../models/clinic_permissions.dart';

class PermissionGuard {
  final ClinicPermissions perms;

  PermissionGuard(Map<String, dynamic>? permissions)
      : perms = ClinicPermissions(permissions ?? const {});

  /// Raw check for any permission key.
  bool has(String key) => perms.has(key);

  // ─────────────────────────────
  // Notes
  // ─────────────────────────────
  bool get canReadNotes => perms.notesRead;

  bool get canWriteOwnNotes => perms.notesWriteOwn;
  bool get canWriteAnyNotes => perms.notesWriteAny;

  bool get canCreateNotes => perms.canCreateNote();

  /// Amend rules:
  /// - clinician: can amend own if notes.write.own
  /// - manager: can amend any if notes.write.any
  /// Signed/draft differences are enforced server-side, but UI gating uses same logic.
  bool canAmendNote({
    required bool isAuthor,
    required bool isSigned,
  }) {
    // Signed notes: backend may restrict certain flows, but permission model is same:
    // own vs any.
    return perms.canAmendNote(isAuthor: isAuthor);
  }

  /// Sign rules:
  /// - author can sign with notes.write.own
  /// - manager can sign with notes.write.any
  bool canSignNote({required bool isAuthor}) =>
      perms.canSignNote(isAuthor: isAuthor);

  /// Locking/override actions should be manager-only
  /// (you asked: wire notes.write.any into signing/locking).
  bool get canSignOrLockNotes => perms.notesWriteAny;
}
