// lib/models/clinic_permissions.dart
//
// Canonical permissions wrapper used across the app.
// IMPORTANT: This wrapper expects a Map<String,bool> (or dynamic values that are == true).
// Keep permission keys aligned with backend authz checks + Firestore rules.

class ClinicPermissions {
  final Map<String, dynamic> _raw;

  ClinicPermissions(Map<String, dynamic>? raw) : _raw = raw ?? const {};

  /// ✅ Expose raw map for guards/widgets that want the full map.
  Map<String, dynamic> get raw => _raw;

  /// Low-level check (tolerates dynamic map values).
  bool has(String key) => _raw[key] == true;

  // ─────────────────────────────
  // Core perms
  // ─────────────────────────────
  bool get settingsRead => has('settings.read');
  bool get settingsWrite => has('settings.write');

  bool get membersRead => has('members.read');
  bool get membersManage => has('members.manage');

  bool get scheduleRead => has('schedule.read');
  bool get scheduleWrite => has('schedule.write');

  bool get patientsRead => has('patients.read');
  bool get patientsWrite => has('patients.write');

  bool get clinicalRead => has('clinical.read');
  bool get clinicalWrite => has('clinical.write');

  bool get notesRead => has('notes.read');
  bool get notesWriteOwn => has('notes.write.own');
  bool get notesWriteAny => has('notes.write.any');

  // ---------------------------------------------------------------------------
  // Phase 5 helper flags (explicit, no role inference)
  // ---------------------------------------------------------------------------
  bool get viewClinical => clinicalRead || notesRead;
  bool get editClinical => clinicalWrite || notesWriteOwn || notesWriteAny;
  bool get manageClinic => settingsWrite;

  bool get registriesManage => has('registries.manage');
  bool get auditRead => has('audit.read');

  // Optional (if you use templates/packs editing in UI)
  bool get templatesManage => has('templates.manage');

  // ─────────────────────────────
  // Note action helpers (UI logic)
  // ─────────────────────────────

  bool canCreateNote() => notesWriteOwn || notesWriteAny;

  bool canAmendNote({required bool isAuthor}) {
    if (notesWriteAny) return true;
    return isAuthor && notesWriteOwn;
  }

  bool canSignNote({required bool isAuthor}) {
    if (notesWriteAny) return true;
    return isAuthor && notesWriteOwn;
  }

  bool canLockNote() => notesWriteAny;

  bool get isManager => membersManage || notesWriteAny;
}
