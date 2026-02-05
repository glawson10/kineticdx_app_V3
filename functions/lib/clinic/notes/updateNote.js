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
exports.updateNote = updateNote;
// functions/src/clinic/notes/updateNote.ts
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const utils_1 = require("../utils");
const permissions_1 = require("../../clinic/permissions");
async function updateNote(req) {
    const uid = (0, utils_1.requireAuth)(req.auth);
    const { clinicId, patientId, episodeId, noteId, soap, reason } = req.data;
    if (!clinicId || !patientId || !episodeId || !noteId || !soap) {
        throw new https_1.HttpsError("invalid-argument", "Missing required fields");
    }
    const db = admin.firestore();
    // ✅ Permission: keep it simple + consistent with your PermissionMap
    // If you later add notes.update.any / notes.update.own, we can tighten this.
    await (0, permissions_1.requireClinicPermission)(db, clinicId, uid, "notes.write");
    const noteRef = db
        .collection("clinics")
        .doc(clinicId)
        .collection("patients")
        .doc(patientId)
        .collection("episodes")
        .doc(episodeId)
        .collection("notes")
        .doc(noteId);
    const snap = await noteRef.get();
    if (!snap.exists) {
        throw new https_1.HttpsError("not-found", "Note not found");
    }
    const note = snap.data();
    const isAuthor = (note === null || note === void 0 ? void 0 : note.clinicianId) === uid;
    // ✅ Minimal safety: only author can amend (with notes.write).
    // If you want managers to amend any note, add a permission like notes.update.any
    // and we’ll expand the logic.
    if (!isAuthor) {
        throw new https_1.HttpsError("permission-denied", "Only the note author can amend this note");
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    const amendmentRef = noteRef.collection("amendments").doc();
    const batch = db.batch();
    batch.update(noteRef, {
        soap,
        amendmentCount: admin.firestore.FieldValue.increment(1),
        lastAmendedAt: now,
        lastAmendedByUid: uid,
        updatedAt: now,
    });
    batch.set(amendmentRef, {
        amendedAt: now,
        amendedByUid: uid,
        amendedByRole: "clinician",
        reason: reason !== null && reason !== void 0 ? reason : null,
    });
    await batch.commit();
    return { success: true };
}
//# sourceMappingURL=updateNote.js.map