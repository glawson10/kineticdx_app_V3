// lib/config/permission_keys.dart
//
// Single source of truth for permission keys and role template ids.
// Align with Firestore rules (hasPerm(clinicId, key)) and Cloud Functions authz.
//
// Spec mapping (instruction pack):
//   manageMembers  -> members.manage
//   manageClinic   -> settings.write (or settings.read for read)
//   manageServices -> services.manage
//   managePatients -> patients.read + patients.write
//   manageAppointments -> schedule.read + schedule.write
//   viewClinical   -> clinical.read | notes.read
//   editClinical   -> clinical.write | notes.write.own | notes.write.any
//   manageBilling  -> (add if needed; not in current rules)
//
// Rules use these exact keys; do not change without updating rules + functions.

/// Canonical permission keys stored in membership docs and checked by rules.
abstract final class PermissionKeys {
  PermissionKeys._();

  // ─── Spec-aligned names (logical) ─────────────────────────────────────
  static const String manageClinic = 'settings.write';
  static const String manageMembers = 'members.manage';
  static const String manageServices = 'services.manage';
  static const String managePatientsRead = 'patients.read';
  static const String managePatientsWrite = 'patients.write';
  static const String manageAppointmentsRead = 'schedule.read';
  static const String manageAppointmentsWrite = 'schedule.write';
  static const String viewClinical = 'clinical.read'; // or notes.read
  static const String editClinical = 'clinical.write'; // or notes.write.own/any
  static const String manageBilling = 'billing.manage'; // optional; add to rules if used

  // ─── Raw keys (what Firestore rules use) ───────────────────────────────
  static const String settingsRead = 'settings.read';
  static const String settingsWrite = 'settings.write';
  static const String membersRead = 'members.read';
  static const String membersManage = 'members.manage';
  static const String scheduleRead = 'schedule.read';
  static const String scheduleWrite = 'schedule.write';
  static const String patientsRead = 'patients.read';
  static const String patientsWrite = 'patients.write';
  static const String clinicalRead = 'clinical.read';
  static const String clinicalWrite = 'clinical.write';
  static const String notesRead = 'notes.read';
  static const String notesWriteOwn = 'notes.write.own';
  static const String notesWriteAny = 'notes.write.any';
  static const String servicesManage = 'services.manage';
  static const String resourcesManage = 'resources.manage';
  static const String registriesManage = 'registries.manage';
  static const String auditRead = 'audit.read';

  /// All keys that may appear in membership.permissions (for UI/validation).
  static const List<String> all = [
    settingsRead,
    settingsWrite,
    membersRead,
    membersManage,
    scheduleRead,
    scheduleWrite,
    patientsRead,
    patientsWrite,
    clinicalRead,
    clinicalWrite,
    notesRead,
    notesWriteOwn,
    notesWriteAny,
    servicesManage,
    resourcesManage,
    registriesManage,
    auditRead,
  ];
}

/// Role template ids (NOT authoritative; permissions in membership doc are).
/// Used for invite dropdown and display only.
abstract final class RoleTemplateIds {
  RoleTemplateIds._();

  static const String owner = 'owner';
  static const String manager = 'manager';
  static const String practitioner = 'clinician'; // backend uses clinician
  static const String receptionist = 'reception';
  static const String billing = 'billing';
  static const String viewer = 'readOnly';

  static const List<String> all = [
    owner,
    manager,
    practitioner,
    receptionist,
    billing,
    viewer,
  ];

  static String displayName(String roleId) {
    switch (roleId) {
      case owner:
        return 'Owner';
      case manager:
        return 'Manager';
      case practitioner:
        return 'Practitioner';
      case receptionist:
        return 'Receptionist';
      case billing:
        return 'Billing';
      case viewer:
        return 'Viewer';
      default:
        return roleId.isEmpty ? 'Staff' : roleId;
    }
  }
}
