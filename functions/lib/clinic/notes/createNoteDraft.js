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
exports.createNoteDraft = createNoteDraft;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const authz_1 = require("../authz");
const paths_1 = require("../paths");
function asObj(v) {
    if (!v || typeof v !== "object" || Array.isArray(v))
        return null;
    return v;
}
async function requireCanWriteAnyOrOwn(db, clinicId, uid) {
    const canOwn = await (0, authz_1.hasPerm)(db, clinicId, uid, "notes.write.own");
    const canAny = await (0, authz_1.hasPerm)(db, clinicId, uid, "notes.write.any");
    if (!canOwn && !canAny) {
        throw new https_1.HttpsError("permission-denied", "Missing permission: notes.write.own or notes.write.any");
    }
}
async function createNoteDraft(req) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q, _r, _s, _t;
    if (!req.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const clinicId = ((_b = (_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId) !== null && _b !== void 0 ? _b : "").trim();
    const patientId = ((_d = (_c = req.data) === null || _c === void 0 ? void 0 : _c.patientId) !== null && _d !== void 0 ? _d : "").trim();
    const episodeId = ((_f = (_e = req.data) === null || _e === void 0 ? void 0 : _e.episodeId) !== null && _f !== void 0 ? _f : "").trim();
    const noteType = (_g = req.data) === null || _g === void 0 ? void 0 : _g.noteType;
    const note = (_k = asObj((_j = (_h = req.data) === null || _h === void 0 ? void 0 : _h.note) !== null && _j !== void 0 ? _j : {})) !== null && _k !== void 0 ? _k : {};
    if (!clinicId || !patientId || !episodeId || !noteType) {
        throw new https_1.HttpsError("invalid-argument", "clinicId, patientId, episodeId, noteType are required.");
    }
    if (noteType !== "initial" && noteType !== "followup" && noteType !== "custom") {
        throw new https_1.HttpsError("invalid-argument", "Invalid noteType.");
    }
    const db = admin.firestore();
    const uid = req.auth.uid;
    await requireCanWriteAnyOrOwn(db, clinicId, uid);
    const ep = (0, paths_1.episodeRef)(db, clinicId, patientId, episodeId);
    const epSnap = await ep.get();
    if (!epSnap.exists)
        throw new https_1.HttpsError("not-found", "Episode not found.");
    // Followup requires previousNoteId (optional strictness)
    if (noteType === "followup" && !((_m = (_l = req.data) === null || _l === void 0 ? void 0 : _l.previousNoteId) !== null && _m !== void 0 ? _m : "").trim()) {
        throw new https_1.HttpsError("failed-precondition", "followup drafts require previousNoteId.");
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    const dr = (0, paths_1.noteDraftRef)(db, clinicId, patientId, episodeId, db.collection("_").doc().id);
    // noteDraftRef expects an id; we generated one above.
    const draftId = dr.id;
    await dr.set({
        schemaVersion: 1,
        clinicId,
        patientId,
        episodeId,
        noteType,
        appointmentId: ((_p = (_o = req.data) === null || _o === void 0 ? void 0 : _o.appointmentId) !== null && _p !== void 0 ? _p : null),
        assessmentId: ((_r = (_q = req.data) === null || _q === void 0 ? void 0 : _q.assessmentId) !== null && _r !== void 0 ? _r : null),
        previousNoteId: ((_t = (_s = req.data) === null || _s === void 0 ? void 0 : _s.previousNoteId) !== null && _t !== void 0 ? _t : null),
        authorUid: uid,
        status: "draft", // draft | finalized | abandoned
        version: 1,
        current: note,
        createdAt: now,
        updatedAt: now,
        finalizedAt: null,
        finalizedByUid: null,
        noteId: null, // filled on finalize
    });
    return { success: true, draftId };
}
//# sourceMappingURL=createNoteDraft.js.map