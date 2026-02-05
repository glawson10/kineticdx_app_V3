import '../models/clinical_note.dart';
import '../models/clinic_permissions.dart';

bool canEditDraftNote({
  required ClinicalNote note,
  required String currentUid,
  required ClinicPermissions perms,
}) {
  return note.status == ClinicalNoteStatus.draft &&
      note.authorUid == currentUid &&
      perms.notesWriteOwn;
}

bool canSignNote({
  required ClinicalNote note,
  required String currentUid,
  required ClinicPermissions perms,
}) {
  // Draft: author can sign if they can write own
  if (note.status != ClinicalNoteStatus.draft) return false;
  final isAuthor = note.authorUid == currentUid;
  return perms.canSignNote(isAuthor: isAuthor);
}

bool canAmendSignedNote({
  required ClinicalNote note,
  required String currentUid,
  required ClinicPermissions perms,
}) {
  if (note.status == ClinicalNoteStatus.draft) return false;

  final isAuthor = note.authorUid == currentUid;
  return perms.canAmendNote(isAuthor: isAuthor);
}

bool isNoteReadOnly({
  required ClinicalNote note,
  required String currentUid,
  required ClinicPermissions perms,
}) {
  // Signed/locked: always read-only in editor
  if (note.status != ClinicalNoteStatus.draft) return true;

  final isAuthor = note.authorUid == currentUid;
  return !perms.canAmendNote(isAuthor: isAuthor);
}
