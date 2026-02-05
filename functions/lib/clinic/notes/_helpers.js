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
exports.requireAuthAndClinicId = requireAuthAndClinicId;
exports.requireActiveMember = requireActiveMember;
exports.requirePerm = requirePerm;
exports.hasPerm = hasPerm;
exports.requireNotesWriteContext = requireNotesWriteContext;
exports.requireEpisodeExists = requireEpisodeExists;
exports.requireNoteExists = requireNoteExists;
// functions/src/clinic/notes/_helpers.ts
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
async function requireAuthAndClinicId(req) {
    var _a, _b;
    if (!req.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const clinicId = ((_b = (_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId) !== null && _b !== void 0 ? _b : "").trim();
    if (!clinicId)
        throw new https_1.HttpsError("invalid-argument", "clinicId required.");
    return { uid: req.auth.uid, clinicId };
}
async function requireActiveMember(db, clinicId, uid) {
    const memberRef = db
        .collection("clinics")
        .doc(clinicId)
        .collection("members")
        .doc(uid);
    const snap = await memberRef.get();
    if (!snap.exists)
        throw new https_1.HttpsError("permission-denied", "Not a clinic member.");
    const data = snap.data();
    if (data.active !== true)
        throw new https_1.HttpsError("permission-denied", "Membership inactive.");
    return data;
}
async function requirePerm(db, clinicId, uid, perm) {
    var _a;
    const member = await requireActiveMember(db, clinicId, uid);
    const perms = (_a = member.permissions) !== null && _a !== void 0 ? _a : {};
    if (perms[perm] !== true) {
        throw new https_1.HttpsError("permission-denied", `Missing permission: ${perm}`);
    }
    return member;
}
async function hasPerm(db, clinicId, uid, perm) {
    try {
        await requirePerm(db, clinicId, uid, perm);
        return true;
    }
    catch {
        return false;
    }
}
/**
 * Notes write context:
 * - everyone who writes notes must have notes.write.own
 * - manager override is notes.write.any
 */
async function requireNotesWriteContext(req) {
    var _a;
    const { uid, clinicId } = await requireAuthAndClinicId(req);
    const db = admin.firestore();
    // baseline write permission
    const member = await requirePerm(db, clinicId, uid, "notes.write.own");
    const perms = (_a = member.permissions) !== null && _a !== void 0 ? _a : {};
    // override permission
    const canWriteAny = perms["notes.write.any"] === true;
    return { db, clinicId, uid, member, perms, canWriteAny };
}
/**
 * Episode existence + reference
 */
async function requireEpisodeExists(params) {
    const { db, clinicId, patientId, episodeId } = params;
    const ref = db
        .collection("clinics")
        .doc(clinicId)
        .collection("patients")
        .doc(patientId)
        .collection("episodes")
        .doc(episodeId);
    const snap = await ref.get();
    if (!snap.exists)
        throw new https_1.HttpsError("not-found", "Episode not found.");
    return { episodeRef: ref, episode: snap.data() };
}
/**
 * Note existence + reference (Phase 5.3 canonical path: episodes/{episodeId}/notes/{noteId})
 */
async function requireNoteExists(params) {
    const { db, clinicId, patientId, episodeId, noteId } = params;
    const ref = db
        .collection("clinics")
        .doc(clinicId)
        .collection("patients")
        .doc(patientId)
        .collection("episodes")
        .doc(episodeId)
        .collection("notes")
        .doc(noteId);
    const snap = await ref.get();
    if (!snap.exists)
        throw new https_1.HttpsError("not-found", "Note not found.");
    return { noteRef: ref, note: snap.data() };
}
//# sourceMappingURL=_helpers.js.map