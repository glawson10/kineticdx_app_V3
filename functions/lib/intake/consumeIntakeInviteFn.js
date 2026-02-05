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
function tsNow() {
    return admin.firestore.FieldValue.serverTimestamp();
}
/**
 * ✅ Behavior (matches what you need to stop "Session does not exist"):
 * - Validate clinicId + token
 * - Find invite by tokenHash
 * - Enforce expiresAt BEFORE claiming (unless already claimed)
 * - If invite already has sessionId => RESUME that sessionId (idempotent)
 * - If not claimed => create intakeSessions/{sessionId} draft AND write invite.sessionId
 *
 * ✅ Also adds: appointmentId / patientId / patientEmailNorm mirroring if present on invite
 * ✅ Does NOT set usedAt here (Option B: mark used on submit)
 */
exports.consumeIntakeInviteFn = (0, https_1.onCall)({ region: "europe-west3", cors: true }, async (req) => {
    var _a, _b;
    const clinicId = safeStr((_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId);
    const token = safeStr((_b = req.data) === null || _b === void 0 ? void 0 : _b.token);
    if (!clinicId || !token) {
        throw new https_1.HttpsError("invalid-argument", "Missing clinicId or token.", {
            clinicId,
            hasToken: !!token,
        });
    }
    // Optional: verify clinic exists (helps debugging)
    const clinicSnap = await db.collection("clinics").doc(clinicId).get();
    if (!clinicSnap.exists) {
        throw new https_1.HttpsError("not-found", "Clinic does not exist.", { clinicId });
    }
    const tokenHash = sha256Base64Url(token);
    const invitesCol = db.collection(`clinics/${clinicId}/intakeInvites`);
    // Find invite by tokenHash (limit 1)
    const q = await invitesCol.where("tokenHash", "==", tokenHash).limit(1).get();
    if (q.empty) {
        throw new https_1.HttpsError("failed-precondition", "Invite not found (link may be invalid).");
    }
    const inviteRef = q.docs[0].ref;
    const result = await db.runTransaction(async (tx) => {
        var _a, _b, _c, _d, _e, _f, _g;
        const inviteSnap = await tx.get(inviteRef);
        if (!inviteSnap.exists) {
            throw new https_1.HttpsError("failed-precondition", "Invite not found (link may be invalid).");
        }
        const invite = (_a = inviteSnap.data()) !== null && _a !== void 0 ? _a : {};
        // If already claimed, resume SAME sessionId (idempotent)
        const existingSessionId = safeStr(invite.sessionId);
        if (existingSessionId) {
            // Ensure the session doc exists; if it was somehow deleted, recreate a minimal draft.
            const intakeRef = db
                .collection(`clinics/${clinicId}/intakeSessions`)
                .doc(existingSessionId);
            const intakeSnap = await tx.get(intakeRef);
            if (!intakeSnap.exists) {
                const now = tsNow();
                tx.set(intakeRef, {
                    schemaVersion: 1,
                    clinicId,
                    status: "draft",
                    createdAt: now,
                    updatedAt: now,
                    submittedAt: null,
                    lockedAt: null,
                    inviteId: inviteRef.id,
                    // helpful linkage (if present on invite)
                    appointmentId: (_b = invite.appointmentId) !== null && _b !== void 0 ? _b : null,
                    patientId: (_c = invite.patientId) !== null && _c !== void 0 ? _c : null,
                    patientEmailNorm: (_d = invite.patientEmailNorm) !== null && _d !== void 0 ? _d : null,
                    // draft payload
                    flow: null,
                    consent: null,
                    patientDetails: null,
                    regionSelection: null,
                    answers: {},
                    triage: null,
                    summary: null,
                }, { merge: false });
            }
            else {
                tx.set(intakeRef, { updatedAt: tsNow() }, { merge: true });
            }
            return { ok: true, sessionId: existingSessionId, resumed: true };
        }
        // If not yet claimed, enforce expiry
        const expiresAt = invite.expiresAt;
        const expiresMs = expiresAt && typeof expiresAt.toMillis === "function" ? expiresAt.toMillis() : null;
        if (expiresMs != null && expiresMs < Date.now()) {
            throw new https_1.HttpsError("failed-precondition", "This link has expired.");
        }
        // ✅ Create a new intake session draft (claim)
        const sessionRef = db
            .collection(`clinics/${clinicId}/intakeSessions`)
            .doc();
        const now = tsNow();
        tx.set(sessionRef, {
            schemaVersion: 1,
            clinicId,
            status: "draft",
            createdAt: now,
            updatedAt: now,
            submittedAt: null,
            lockedAt: null,
            inviteId: inviteRef.id,
            // helpful linkage (if present on invite)
            appointmentId: (_e = invite.appointmentId) !== null && _e !== void 0 ? _e : null,
            patientId: (_f = invite.patientId) !== null && _f !== void 0 ? _f : null,
            patientEmailNorm: (_g = invite.patientEmailNorm) !== null && _g !== void 0 ? _g : null,
            // draft payload (client fills these progressively)
            flow: null,
            consent: null,
            patientDetails: null,
            regionSelection: null,
            answers: {},
            triage: null,
            summary: null,
        }, { merge: false });
        tx.set(inviteRef, {
            sessionId: sessionRef.id,
            claimedAt: now,
            // NOTE: do NOT set usedAt here (Option B: set usedAt on submit)
        }, { merge: true });
        return { ok: true, sessionId: sessionRef.id, resumed: false };
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