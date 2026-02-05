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
exports.consumeIntakeInviteFn = void 0;
// functions/src/preassessment/consumeIntakeInviteFn.ts
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const logger_1 = require("firebase-functions/logger");
const crypto = __importStar(require("crypto"));
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
}
function sha256Base64Url(s) {
    return crypto.createHash("sha256").update(s).digest("base64url");
}
exports.consumeIntakeInviteFn = (0, https_1.onCall)({ region: "europe-west3" }, async (req) => {
    var _a, _b;
    const clinicId = safeStr((_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId);
    const token = safeStr((_b = req.data) === null || _b === void 0 ? void 0 : _b.token);
    if (!clinicId || !token) {
        throw new https_1.HttpsError("invalid-argument", "Missing clinicId or token.");
    }
    const tokenHash = sha256Base64Url(token);
    const invitesCol = db.collection(`clinics/${clinicId}/intakeInvites`);
    // Find invite by tokenHash (limit 1)
    const q = await invitesCol.where("tokenHash", "==", tokenHash).limit(1).get();
    if (q.empty) {
        throw new https_1.HttpsError("not-found", "Invite not found or invalid.");
    }
    const inviteRef = q.docs[0].ref;
    const result = await db.runTransaction(async (tx) => {
        var _a, _b, _c;
        const inviteSnap = await tx.get(inviteRef);
        const invite = (_a = inviteSnap.data()) !== null && _a !== void 0 ? _a : {};
        const nowMs = Date.now();
        // If already USED (submitted), block
        if (invite.usedAt) {
            throw new https_1.HttpsError("failed-precondition", "This link has already been submitted.");
        }
        // If already claimed, resume SAME sessionId (even if expired)
        const existingSessionId = safeStr(invite.sessionId);
        if (existingSessionId) {
            return { sessionId: existingSessionId, resumed: true };
        }
        // If not yet claimed, enforce expiry
        const expiresAt = (_c = (_b = invite.expiresAt) === null || _b === void 0 ? void 0 : _b.toDate) === null || _c === void 0 ? void 0 : _c.call(_b);
        if (expiresAt && expiresAt.getTime() < nowMs) {
            throw new https_1.HttpsError("failed-precondition", "This link has expired.");
        }
        // Create a new intake session draft (claim)
        const sessionRef = db
            .collection(`clinics/${clinicId}/intakeSessions`)
            .doc();
        const now = admin.firestore.FieldValue.serverTimestamp();
        tx.set(sessionRef, {
            schemaVersion: 1,
            clinicId,
            status: "draft",
            createdAt: now,
            submittedAt: null,
            lockedAt: null,
            inviteId: inviteRef.id,
            // keep minimal; client can store draft locally
            answers: {},
        }, { merge: false });
        tx.set(inviteRef, {
            sessionId: sessionRef.id,
            claimedAt: now,
        }, { merge: true });
        return { sessionId: sessionRef.id, resumed: false };
    });
    logger_1.logger.info("consumeIntakeInviteFn ok", {
        clinicId,
        inviteId: inviteRef.id,
        sessionId: result.sessionId,
        resumed: result.resumed,
    });
    return result;
});
//# sourceMappingURL=consumeIntakeInviteFn.js.map