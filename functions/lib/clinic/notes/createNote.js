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
exports.createNote = createNote;
// functions/src/clinic/notes/createNote.ts
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const utils_1 = require("../utils");
const permissions_1 = require("../../clinic/permissions");
async function createNote(req) {
    const uid = (0, utils_1.requireAuth)(req.auth);
    const { clinicId, patientId, episodeId, noteType, appointmentId, assessmentId, previousNoteId, } = req.data;
    if (!clinicId || !patientId || !episodeId || !noteType) {
        throw new https_1.HttpsError("invalid-argument", "Missing required fields");
    }
    const db = admin.firestore();
    // ✅ Permission: your permissions.ts defines notes.read / notes.write (NOT notes.create)
    await (0, permissions_1.requireClinicPermission)(db, clinicId, uid, "notes.write");
    const episodeRef = db
        .collection("clinics")
        .doc(clinicId)
        .collection("patients")
        .doc(patientId)
        .collection("episodes")
        .doc(episodeId);
    const episodeSnap = await episodeRef.get();
    if (!episodeSnap.exists) {
        throw new https_1.HttpsError("not-found", "Episode not found");
    }
    // Follow-up requires previous note
    if (noteType === "followup" && !previousNoteId) {
        throw new https_1.HttpsError("failed-precondition", "Follow-up notes require previousNoteId");
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    const noteRef = episodeRef.collection("notes").doc();
    const batch = db.batch();
    batch.set(noteRef, {
        schemaVersion: 1,
        noteType,
        patientId,
        episodeId,
        appointmentId: appointmentId !== null && appointmentId !== void 0 ? appointmentId : null,
        assessmentId: assessmentId !== null && assessmentId !== void 0 ? assessmentId : null,
        previousNoteId: previousNoteId !== null && previousNoteId !== void 0 ? previousNoteId : null,
        clinicianId: uid,
        soap: {},
        amendmentCount: 0,
        lastAmendedAt: null,
        lastAmendedByUid: null,
        createdAt: now,
        updatedAt: now,
    });
    batch.update(episodeRef, {
        lastNoteId: noteRef.id,
        lastNoteAt: now,
        noteCount: admin.firestore.FieldValue.increment(1),
    });
    await batch.commit();
    return { noteId: noteRef.id };
}
//# sourceMappingURL=createNote.js.map