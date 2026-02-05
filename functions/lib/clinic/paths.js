"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.paths = void 0;
exports.clinicRef = clinicRef;
exports.patientRef = patientRef;
exports.assessmentPackRef = assessmentPackRef;
exports.assessmentRef = assessmentRef;
exports.episodeRef = episodeRef;
exports.noteRef = noteRef;
exports.noteDraftRef = noteDraftRef;
function clinicRef(db, clinicId) {
    return db.collection("clinics").doc(clinicId);
}
function patientRef(db, clinicId, patientId) {
    return clinicRef(db, clinicId).collection("patients").doc(patientId);
}
function assessmentPackRef(db, clinicId, packId) {
    return db.collection("clinics").doc(clinicId).collection("assessmentPacks").doc(packId);
}
exports.paths = {
    settingsPublicBooking: (clinicId) => `clinics/${clinicId}/settings/publicBooking`,
    publicBookingMirror: (clinicId) => `clinics/${clinicId}/public/config/publicBooking/publicBooking`,
};
function assessmentRef(db, clinicId, assessmentId) {
    return db.collection("clinics").doc(clinicId).collection("assessments").doc(assessmentId);
}
function episodeRef(db, clinicId, patientId, episodeId) {
    return patientRef(db, clinicId, patientId).collection("episodes").doc(episodeId);
}
function noteRef(db, clinicId, patientId, episodeId, noteId) {
    return episodeRef(db, clinicId, patientId, episodeId).collection("notes").doc(noteId);
}
function noteDraftRef(db, clinicId, patientId, episodeId, draftId) {
    return episodeRef(db, clinicId, patientId, episodeId).collection("noteDrafts").doc(draftId);
}
//# sourceMappingURL=paths.js.map