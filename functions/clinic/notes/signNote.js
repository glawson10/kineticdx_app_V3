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
exports.signNote = signNote;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const audit_1 = require("../audit/audit");
const _helpers_1 = require("./_helpers");
async function signNote(req) {
    var _a, _b, _c, _d, _e, _f;
    const { db, clinicId, uid, canWriteAny } = await (0, _helpers_1.requireNotesWriteContext)(req);
    const patientId = ((_b = (_a = req.data) === null || _a === void 0 ? void 0 : _a.patientId) !== null && _b !== void 0 ? _b : "").trim();
    const episodeId = ((_d = (_c = req.data) === null || _c === void 0 ? void 0 : _c.episodeId) !== null && _d !== void 0 ? _d : "").trim();
    const noteId = ((_f = (_e = req.data) === null || _e === void 0 ? void 0 : _e.noteId) !== null && _f !== void 0 ? _f : "").trim();
    if (!patientId || !episodeId || !noteId) {
        throw new https_1.HttpsError("invalid-argument", "patientId, episodeId, noteId required.");
    }
    const { noteRef, note } = await (0, _helpers_1.requireNoteExists)({ db, clinicId, patientId, episodeId, noteId });
    if (note.status !== "draft") {
        throw new https_1.HttpsError("failed-precondition", "Note is not a draft.");
    }
    const isAuthor = note.authorUid === uid;
    // signing: author OR manager override
    if (!isAuthor && !canWriteAny) {
        throw new https_1.HttpsError("permission-denied", "Only author or manager can sign this note.");
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    await noteRef.update({
        status: "signed",
        signedAt: now,
        signedByUid: uid,
        updatedAt: now,
    });
    // touch episode activity
    const epRef = noteRef.parent.parent; // episodes/{episodeId}
    if (epRef) {
        await epRef.update({
            lastActivityAt: now,
            updatedAt: now,
        });
    }
    await (0, audit_1.writeAuditEvent)(db, clinicId, {
        type: "note.signed",
        actorUid: uid,
        patientId,
        episodeId,
        noteId,
        metadata: { signedBy: isAuthor ? "author" : "managerOverride" },
    });
    return { success: true };
}
//# sourceMappingURL=signNote.js.map