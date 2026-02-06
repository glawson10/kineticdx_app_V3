"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.onClinicalNoteWrite = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const audit_1 = require("../audit/audit");
if (!admin.apps.length) {
    admin.initializeApp();
}
function safeStr(v) {
    return (v ?? "").toString().trim();
}
exports.onClinicalNoteWrite = (0, firestore_1.onDocumentWritten)({
    region: "europe-west3",
    document: "clinics/{clinicId}/clinicalNotes/{noteId}",
}, async (event) => {
    const { clinicId, noteId } = event.params;
    const afterSnap = event.data?.after;
    const beforeSnap = event.data?.before;
    if (!afterSnap?.exists)
        return;
    const isCreate = !beforeSnap?.exists;
    const data = afterSnap.data() || {};
    const actorUid = safeStr(data["updatedByUid"]) || safeStr(data["createdByUid"]);
    if (!actorUid)
        return;
    const patientId = safeStr(data["patientId"]);
    const appointmentId = safeStr(data["appointmentId"]);
    const noteType = safeStr(data["type"]);
    const templateId = safeStr(data["templateId"]);
    await (0, audit_1.writeAuditEvent)(admin.firestore(), clinicId, {
        type: isCreate ? "clinicalNote.created" : "clinicalNote.updated",
        actorUid,
        patientId: patientId || undefined,
        noteId,
        appointmentId: appointmentId || undefined,
        metadata: {
            noteType: noteType || undefined,
            templateId: templateId || undefined,
        },
    });
});
