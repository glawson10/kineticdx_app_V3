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
exports.amendClinicalNote = amendClinicalNote;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const authz_1 = require("../authz");
const paths_1 = require("../paths");
async function amendClinicalNote(req) {
    var _a;
    if (!req.auth) {
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    }
    const { clinicId, patientId, episodeId, noteId, soap, reason } = (_a = req.data) !== null && _a !== void 0 ? _a : {};
    if (!clinicId || !patientId || !episodeId || !noteId) {
        throw new https_1.HttpsError("invalid-argument", "Missing required identifiers.");
    }
    if (!soap || typeof soap !== "object" || Array.isArray(soap)) {
        throw new https_1.HttpsError("invalid-argument", "soap object is required.");
    }
    const db = admin.firestore();
    const uid = req.auth.uid;
    const ref = (0, paths_1.noteRef)(db, clinicId, patientId, episodeId, noteId);
    await db.runTransaction(async (tx) => {
        var _a, _b;
        const snap = await tx.get(ref);
        if (!snap.exists) {
            throw new https_1.HttpsError("not-found", "Note not found.");
        }
        const data = snap.data();
        const authorUid = (_a = data.authorUid) !== null && _a !== void 0 ? _a : data.clinicianId;
        const scope = await (0, authz_1.requireCanAmendNote)(db, clinicId, uid, authorUid);
        const now = admin.firestore.FieldValue.serverTimestamp();
        const nextVersion = ((_b = data.version) !== null && _b !== void 0 ? _b : 1) + 1;
        tx.set(ref.collection("amendments").doc(), {
            schemaVersion: 1,
            noteId,
            actorUid: uid,
            scope,
            reason: reason !== null && reason !== void 0 ? reason : null,
            patch: soap,
            createdAt: now,
            newVersion: nextVersion,
        });
        tx.update(ref, {
            current: soap,
            version: nextVersion,
            updatedAt: now,
            lastAmendedAt: now,
            lastAmendedByUid: uid,
            amendmentCount: admin.firestore.FieldValue.increment(1),
        });
    });
    return { success: true, noteId };
}
//# sourceMappingURL=amendClinicalNote.js.map