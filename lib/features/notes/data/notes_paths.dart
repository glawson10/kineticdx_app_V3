import 'package:cloud_firestore/cloud_firestore.dart';

CollectionReference<Map<String, dynamic>> clinicClinicalNotesCollection(
  FirebaseFirestore db,
  String clinicId,
) {
  return db.collection('clinics').doc(clinicId).collection('clinicalNotes');
}

DocumentReference<Map<String, dynamic>> clinicClinicalNoteDoc(
  FirebaseFirestore db,
  String clinicId,
  String noteId,
) {
  return clinicClinicalNotesCollection(db, clinicId).doc(noteId);
}

DocumentReference<Map<String, dynamic>> clinicNotesSettingsDoc(
  FirebaseFirestore db,
  String clinicId,
) {
  return db.collection('clinics').doc(clinicId).collection('settings').doc('notes');
}
