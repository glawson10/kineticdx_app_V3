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
exports.createClinicalNote = createClinicalNote;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const audit_1 = require("../audit/audit");
const _helpers_1 = require("./_helpers");
async function createClinicalNote(req) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p;
    const { db, clinicId, uid } = await (0, _helpers_1.requireNotesWriteContext)(req);
    const patientId = ((_b = (_a = req.data) === null || _a === void 0 ? void 0 : _a.patientId) !== null && _b !== void 0 ? _b : "").trim();
    const episodeId = ((_d = (_c = req.data) === null || _c === void 0 ? void 0 : _c.episodeId) !== null && _d !== void 0 ? _d : "").trim();
    const soap = (_f = (_e = req.data) === null || _e === void 0 ? void 0 : _e.soap) !== null && _f !== void 0 ? _f : null;
    const encounterType = (_g = req.data) === null || _g === void 0 ? void 0 : _g.encounterType;
    const template = (_h = req.data) === null || _h === void 0 ? void 0 : _h.template;
    const appointmentId = ((_k = (_j = req.data) === null || _j === void 0 ? void 0 : _j.appointmentId) !== null && _k !== void 0 ? _k : "").trim() || null;
    const assessmentId = ((_m = (_l = req.data) === null || _l === void 0 ? void 0 : _l.assessmentId) !== null && _m !== void 0 ? _m : "").trim() || null;
    const previousNoteId = ((_p = (_o = req.data) === null || _o === void 0 ? void 0 : _o.previousNoteId) !== null && _p !== void 0 ? _p : "").trim() || null;
    if (!patientId || !episodeId) {
        throw new https_1.HttpsError("invalid-argument", "patientId, episodeId required.");
    }
    if (!soap || typeof soap !== "object" || Array.isArray(soap)) {
        throw new https_1.HttpsError("invalid-argument", "soap object is required.");
    }
    if (encounterType !== "initial" && encounterType !== "followup") {
        throw new https_1.HttpsError("invalid-argument", "encounterType must be initial|followup.");
    }
    if (template !== "standard" && template !== "custom") {
        throw new https_1.HttpsError("invalid-argument", "template must be standard|custom.");
    }
    if (encounterType === "followup" && !previousNoteId) {
        throw new https_1.HttpsError("failed-precondition", "Follow-up requires previousNoteId.");
    }
    // ensure episode exists
    const { episodeRef } = await (0, _helpers_1.requireEpisodeExists)({ db, clinicId, patientId, episodeId });
    const now = admin.firestore.FieldValue.serverTimestamp();
    const noteRef = episodeRef.collection("notes").doc();
    await db.runTransaction(async (tx) => {
        tx.set(noteRef, {
            schemaVersion: 1,
            clinicId,
            patientId,
            episodeId,
            authorUid: uid,
            status: "draft", // draft -> signed
            encounterType,
            template,
            appointmentId,
            assessmentId,
            previousNoteId,
            version: 1,
            current: soap,
            amendmentCount: 0,
            lastAmendedAt: null,
            lastAmendedByUid: null,
            signedAt: null,
            signedByUid: null,
            createdAt: now,
            updatedAt: now,
        });
        tx.set(episodeRef, {
            lastNoteId: noteRef.id,
            lastNoteAt: now,
            noteCount: admin.firestore.FieldValue.increment(1),
            lastActivityAt: now,
            updatedAt: now,
        }, { merge: true });
    });
    await (0, audit_1.writeAuditEvent)(db, clinicId, {
        type: "note.created",
        actorUid: uid,
        patientId,
        episodeId,
        noteId: noteRef.id,
        metadata: { encounterType, template, appointmentId, assessmentId, previousNoteId },
    });
    return { success: true, noteId: noteRef.id };
}
//# sourceMappingURL=createClinicalNote.js.map