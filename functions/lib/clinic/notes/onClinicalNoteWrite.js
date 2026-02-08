"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.onClinicalNoteWrite = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const admin = __importStar(require("firebase-admin"));
const audit_1 = require("../audit/audit");
if (!admin.apps.length) {
    admin.initializeApp();
}
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
}
exports.onClinicalNoteWrite = (0, firestore_1.onDocumentWritten)({
    region: "europe-west3",
    document: "clinics/{clinicId}/clinicalNotes/{noteId}",
}, async (event) => {
    var _a, _b;
    const { clinicId, noteId } = event.params;
    const afterSnap = (_a = event.data) === null || _a === void 0 ? void 0 : _a.after;
    const beforeSnap = (_b = event.data) === null || _b === void 0 ? void 0 : _b.before;
    if (!(afterSnap === null || afterSnap === void 0 ? void 0 : afterSnap.exists))
        return;
    const isCreate = !(beforeSnap === null || beforeSnap === void 0 ? void 0 : beforeSnap.exists);
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
//# sourceMappingURL=onClinicalNoteWrite.js.map