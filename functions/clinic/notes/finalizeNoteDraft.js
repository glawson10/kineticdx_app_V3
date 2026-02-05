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
exports.finalizeNoteDraft = finalizeNoteDraft;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const authz_1 = require("../authz");
const paths_1 = require("../paths");
async function finalizeNoteDraft(req) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l;
    if (!req.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const clinicId = ((_b = (_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId) !== null && _b !== void 0 ? _b : "").trim();
    const patientId = ((_d = (_c = req.data) === null || _c === void 0 ? void 0 : _c.patientId) !== null && _d !== void 0 ? _d : "").trim();
    const episodeId = ((_f = (_e = req.data) === null || _e === void 0 ? void 0 : _e.episodeId) !== null && _f !== void 0 ? _f : "").trim();
    const draftId = ((_h = (_g = req.data) === null || _g === void 0 ? void 0 : _g.draftId) !== null && _h !== void 0 ? _h : "").trim();
    const reason = ((_k = (_j = req.data) === null || _j === void 0 ? void 0 : _j.reason) !== null && _k !== void 0 ? _k : "").trim();
    if (!clinicId || !patientId || !episodeId || !draftId) {
        throw new https_1.HttpsError("invalid-argument", "clinicId, patientId, episodeId, draftId required.");
    }
    const db = admin.firestore();
    const uid = req.auth.uid;
    const canWriteOwn = await (0, authz_1.hasPerm)(db, clinicId, uid, "notes.write.own");
    const canWriteAny = await (0, authz_1.hasPerm)(db, clinicId, uid, "notes.write.any");
    if (!canWriteOwn && !canWriteAny) {
        throw new https_1.HttpsError("permission-denied", "Missing permission: notes.write.own or notes.write.any");
    }
    const epRef = (0, paths_1.episodeRef)(db, clinicId, patientId, episodeId);
    const drRef = (0, paths_1.noteDraftRef)(db, clinicId, patientId, episodeId, draftId);
    await db.runTransaction(async (tx) => {
        var _a, _b, _c, _d, _e, _f, _g, _h, _j;
        const epSnap = await tx.get(epRef);
        if (!epSnap.exists)
            throw new https_1.HttpsError("not-found", "Episode not found.");
        const drSnap = await tx.get(drRef);
        if (!drSnap.exists)
            throw new https_1.HttpsError("not-found", "Draft not found.");
        const draft = drSnap.data();
        if (draft.status !== "draft") {
            throw new https_1.HttpsError("failed-precondition", "Draft already finalized or not editable.");
        }
        const authorUid = ((_a = draft.authorUid) !== null && _a !== void 0 ? _a : "").toString();
        const isAuthor = authorUid === uid;
        // ✅ Correct override rule:
        // - author can finalize if notes.write.own OR notes.write.any
        // - non-author can finalize ONLY if notes.write.any
        if (!isAuthor && !canWriteAny) {
            throw new https_1.HttpsError("permission-denied", "You can only finalize your own draft.");
        }
        const now = admin.firestore.FieldValue.serverTimestamp();
        // If draft already linked to a note, finalize becomes an amendment.
        const existingNoteId = (_b = draft.noteId) !== null && _b !== void 0 ? _b : null;
        let canonicalNoteId;
        if (!existingNoteId) {
            const newNoteDoc = epRef.collection("notes").doc();
            canonicalNoteId = newNoteDoc.id;
            tx.set(newNoteDoc, {
                schemaVersion: 1,
                clinicId,
                patientId,
                episodeId,
                noteType: (_c = draft.noteType) !== null && _c !== void 0 ? _c : "custom",
                appointmentId: (_d = draft.appointmentId) !== null && _d !== void 0 ? _d : null,
                assessmentId: (_e = draft.assessmentId) !== null && _e !== void 0 ? _e : null,
                previousNoteId: (_f = draft.previousNoteId) !== null && _f !== void 0 ? _f : null,
                authorUid: authorUid,
                status: "final", // final | voided | archived
                version: 1,
                current: (_g = draft.current) !== null && _g !== void 0 ? _g : {},
                createdAt: now,
                updatedAt: now,
                lastAmendedAt: null,
                lastAmendedByUid: null,
                amendmentCount: 0,
            });
            tx.update(epRef, {
                lastNoteId: canonicalNoteId,
                lastNoteAt: now,
                noteCount: admin.firestore.FieldValue.increment(1),
            });
        }
        else {
            canonicalNoteId = existingNoteId;
            const nRef = (0, paths_1.noteRef)(db, clinicId, patientId, episodeId, canonicalNoteId);
            const nSnap = await tx.get(nRef);
            if (!nSnap.exists)
                throw new https_1.HttpsError("not-found", "Linked note not found.");
            const noteData = nSnap.data();
            const nextVersion = (typeof noteData.version === "number" ? noteData.version : 1) + 1;
            const amendRef = nRef.collection("amendments").doc();
            tx.set(amendRef, {
                schemaVersion: 1,
                noteId: canonicalNoteId,
                actorUid: uid,
                reason: reason || null,
                patch: (_h = draft.current) !== null && _h !== void 0 ? _h : {},
                createdAt: now,
                newVersion: nextVersion,
                source: "draftFinalize",
            });
            tx.update(nRef, {
                current: (_j = draft.current) !== null && _j !== void 0 ? _j : {},
                version: nextVersion,
                updatedAt: now,
                lastAmendedAt: now,
                lastAmendedByUid: uid,
                amendmentCount: admin.firestore.FieldValue.increment(1),
            });
        }
        tx.update(drRef, {
            status: "finalized",
            finalizedAt: now,
            finalizedByUid: uid,
            noteId: canonicalNoteId,
            updatedAt: now,
        });
    });
    const drSnap = await drRef.get();
    const noteId = (_l = drSnap.data()) === null || _l === void 0 ? void 0 : _l.noteId;
    return { success: true, draftId, noteId };
}
//# sourceMappingURL=finalizeNoteDraft.js.map