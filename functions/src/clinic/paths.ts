import { Firestore } from "firebase-admin/firestore";

export function clinicRef(db: Firestore, clinicId: string) {
  return db.collection("clinics").doc(clinicId);
}

export function patientRef(db: Firestore, clinicId: string, patientId: string) {
  return clinicRef(db, clinicId).collection("patients").doc(patientId);
}
export function assessmentPackRef(db: Firestore, clinicId: string, packId: string) {
  return db.collection("clinics").doc(clinicId).collection("assessmentPacks").doc(packId);
}
export const paths = {
  settingsPublicBooking: (clinicId: string) =>
    `clinics/${clinicId}/settings/publicBooking`,
  publicBookingMirror: (clinicId: string) =>
    `clinics/${clinicId}/public/config/publicBooking/publicBooking`,
};

export function assessmentRef(db: Firestore, clinicId: string, assessmentId: string) {
  return db.collection("clinics").doc(clinicId).collection("assessments").doc(assessmentId);
}
export function episodeRef(
  db: Firestore,
  clinicId: string,
  patientId: string,
  episodeId: string
) {
  return patientRef(db, clinicId, patientId).collection("episodes").doc(episodeId);
}

export function noteRef(
  db: Firestore,
  clinicId: string,
  patientId: string,
  episodeId: string,
  noteId: string
) {
  return episodeRef(db, clinicId, patientId, episodeId).collection("notes").doc(noteId);
}

export function noteDraftRef(
  db: Firestore,
  clinicId: string,
  patientId: string,
  episodeId: string,
  draftId: string
) {
  return episodeRef(db, clinicId, patientId, episodeId).collection("noteDrafts").doc(draftId);
}
