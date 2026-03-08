"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.onSoapNoteWrite = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
/** Stub: SOAP note write trigger. Replace with real implementation. */
exports.onSoapNoteWrite = (0, firestore_1.onDocumentWritten)({
    document: "clinics/{clinicId}/patients/{patientId}/episodes/{episodeId}/soapNotes/{noteId}",
    region: "europe-west3",
}, async () => { });
//# sourceMappingURL=onSoapNoteWrite.js.map