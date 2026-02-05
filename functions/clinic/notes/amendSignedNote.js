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
exports.amendSignedNote = amendSignedNote;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const audit_1 = require("../audit/audit");
const _helpers_1 = require("./_helpers");
async function amendSignedNote(req) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o;
    const { db, clinicId, uid, canWriteAny } = await (0, _helpers_1.requireNotesWriteContext)(req);
    const patientId = ((_b = (_a = req.data) === null || _a === void 0 ? void 0 : _a.patientId) !== null && _b !== void 0 ? _b : "").trim();
    const episodeId = ((_d = (_c = req.data) === null || _c === void 0 ? void 0 : _c.episodeId) !== null && _d !== void 0 ? _d : "").trim();
    const noteId = ((_f = (_e = req.data) === null || _e === void 0 ? void 0 : _e.noteId) !== null && _f !== void 0 ? _f : "").trim();
    const soap = (_h = (_g = req.data) === null || _g === void 0 ? void 0 : _g.soap) !== null && _h !== void 0 ? _h : null;
    const reason = ((_k = (_j = req.data) === null || _j === void 0 ? void 0 : _j.reason) !== null && _k !== void 0 ? _k : "").trim();
    const summary = (_m = (_l = req.data) === null || _l === void 0 ? void 0 : _l.summary) !== null && _m !== void 0 ? _m : null;
    const fieldPaths = Array.isArray((_o = req.data) === null || _o === void 0 ? void 0 : _o.fieldPaths) ? req.data.fieldPaths : [];
    if (!patientId || !episodeId || !noteId) {
        throw new https_1.HttpsError("invalid-argument", "patientId, episodeId, noteId required.");
    }
    if (!soap || typeof soap !== "object" || Array.isArray(soap)) {
        throw new https_1.HttpsError("invalid-argument", "soap object is required.");
    }
    if (!reason) {
        throw new https_1.HttpsError("invalid-argument", "reason is required.");
    }
    const { noteRef, note } = await (0, _helpers_1.requireNoteExists)({ db, clinicId, patientId, episodeId, noteId });
    if (note.status !== "signed") {
        throw new https_1.HttpsError("failed-precondition", "Only signed notes can be amended.");
    }
    const isAuthor = note.authorUid === uid;
    if (!isAuthor && !canWriteAny) {
        throw new https_1.HttpsError("permission-denied", "Only the author or a manager can amend this note.");
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    await db.runTransaction(async (tx) => {
        const fresh = await tx.get(noteRef);
        if (!fresh.exists)
            throw new https_1.HttpsError("not-found", "Note not found.");
        const data = fresh.data();
        const nextVersion = (typeof data.version === "number" ? data.version : 1) + 1;
        // Append-only amendment record
        const amendRef = noteRef.collection("amendments").doc();
        tx.set(amendRef, {
            schemaVersion: 1,
            noteId,
            actorUid: uid,
            actorRole: canWriteAny && !isAuthor ? "manager" : "clinician",
            reason,
            summary,
            fieldPaths,
            patch: soap,
            createdAt: now,
            newVersion: nextVersion,
        });
        // Update current snapshot
        tx.update(noteRef, {
            current: soap,
            version: nextVersion,
            lastAmendedAt: now,
            lastAmendedByUid: uid,
            amendmentCount: admin.firestore.FieldValue.increment(1),
            updatedAt: now,
        });
        // touch episode activity
        const epRef = noteRef.parent.parent;
        if (epRef) {
            tx.set(epRef, { lastActivityAt: now, updatedAt: now }, { merge: true });
        }
    });
    await (0, audit_1.writeAuditEvent)(db, clinicId, {
        type: "note.amended",
        actorUid: uid,
        patientId,
        episodeId,
        noteId,
        metadata: {
            amendedBy: isAuthor ? "author" : "managerOverride",
            summary,
            fieldPaths,
        },
    });
    return { success: true };
}
//# sourceMappingURL=amendSignedNote.js.map