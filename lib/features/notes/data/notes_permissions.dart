import '../../../models/clinic_permissions.dart';

bool canViewClinicalNotes(ClinicPermissions perms) {
  return perms.clinicalRead || perms.notesRead;
}

bool canEditClinicalNotes(ClinicPermissions perms) {
  return perms.clinicalWrite || perms.notesWriteOwn || perms.notesWriteAny;
}

bool canManageNotesSettings(ClinicPermissions perms) {
  return perms.settingsWrite;
}
