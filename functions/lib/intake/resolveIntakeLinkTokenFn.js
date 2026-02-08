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
exports.resolveIntakeLinkTokenFn = void 0;
// functions/src/intake/resolveIntakeLinkTokenFn.ts
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const logger_1 = require("firebase-functions/logger");
const crypto = __importStar(require("crypto"));
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
const GENERAL_FLOW_ID = "generalVisit";
const GENERAL_FLOW_VERSION = 1;
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
}
function sha256Base64Url(s) {
    return crypto.createHash("sha256").update(s).digest("base64url");
}
function tsNow() {
    return admin.firestore.FieldValue.serverTimestamp();
}
function intakeDraftPayload(params) {
    return {
        schemaVersion: 1,
        clinicId: params.clinicId,
        status: "draft",
        createdAt: tsNow(),
        updatedAt: tsNow(),
        submittedAt: null,
        lockedAt: null,
        intakeLinkId: params.linkId,
        flow: { flowId: GENERAL_FLOW_ID, flowVersion: GENERAL_FLOW_VERSION },
        flowId: GENERAL_FLOW_ID,
        flowVersion: GENERAL_FLOW_VERSION,
        flowCategory: "general",
        consent: null,
        patientDetails: null,
        regionSelection: null,
        answers: {},
        triage: null,
        summary: null,
    };
}
/**
 * ✅ Resolve a tokenized general questionnaire link (public).
 * Input: { token }
 * Output: { clinicId, kind, intakeSessionId, flowId, flowVersion }
 */
exports.resolveIntakeLinkTokenFn = (0, https_1.onCall)({ region: "europe-west3", cors: true }, async (req) => {
    var _a;
    const token = safeStr((_a = req.data) === null || _a === void 0 ? void 0 : _a.token);
    if (!token) {
        throw new https_1.HttpsError("invalid-argument", "Missing token.");
    }
    const tokenHash = sha256Base64Url(token);
    let q;
    try {
        q = await db
            .collectionGroup("intakeLinks")
            .where("tokenHash", "==", tokenHash)
            .limit(1)
            .get();
    }
    catch (err) {
        logger_1.logger.error("resolveIntakeLinkTokenFn: intakeLinks query failed", {
            code: err === null || err === void 0 ? void 0 : err.code,
            message: err === null || err === void 0 ? void 0 : err.message,
            details: err === null || err === void 0 ? void 0 : err.details,
        });
        throw new https_1.HttpsError("internal", "Failed to look up questionnaire link.", err);
    }
    if (q.empty) {
        throw new https_1.HttpsError("not-found", "Link not found.");
    }
    const linkRef = q.docs[0].ref;
    const linkId = linkRef.id;
    const result = await db.runTransaction(async (tx) => {
        var _a, _b, _c, _d;
        const linkSnap = await tx.get(linkRef);
        if (!linkSnap.exists) {
            throw new https_1.HttpsError("not-found", "Link not found.");
        }
        const link = (_a = linkSnap.data()) !== null && _a !== void 0 ? _a : {};
        const clinicId = safeStr(link.clinicId) || ((_b = linkRef.parent.parent) === null || _b === void 0 ? void 0 : _b.id) || "";
        if (!clinicId) {
            throw new https_1.HttpsError("failed-precondition", "Link missing clinicId.");
        }
        const kind = safeStr(link.kind) || "preassessment";
        if (kind !== "general") {
            throw new https_1.HttpsError("failed-precondition", "This link is not for the general questionnaire.");
        }
        const existingSessionId = safeStr((_c = link.intakeSessionId) !== null && _c !== void 0 ? _c : link.sessionId);
        const status = safeStr(link.status) || "active";
        if (status === "expired") {
            throw new https_1.HttpsError("failed-precondition", "This link has expired.");
        }
        if (status === "used" && !existingSessionId) {
            throw new https_1.HttpsError("failed-precondition", "This link has already been used.");
        }
        const expiresAt = link.expiresAt;
        const expiresMs = expiresAt && typeof expiresAt.toMillis === "function"
            ? expiresAt.toMillis()
            : null;
        if (expiresMs != null && expiresMs < Date.now()) {
            tx.set(linkRef, { status: "expired", expiredAt: tsNow() }, { merge: true });
            throw new https_1.HttpsError("failed-precondition", "This link has expired.");
        }
        const sessionsCol = db
            .collection("clinics")
            .doc(clinicId)
            .collection("intakeSessions");
        let intakeSessionId = existingSessionId;
        let resumed = false;
        if (existingSessionId) {
            const intakeRef = sessionsCol.doc(existingSessionId);
            const intakeSnap = await tx.get(intakeRef);
            if (!intakeSnap.exists) {
                tx.set(intakeRef, intakeDraftPayload({ clinicId, linkId }), {
                    merge: false,
                });
            }
            else {
                const existing = (_d = intakeSnap.data()) !== null && _d !== void 0 ? _d : {};
                if (existing.submittedAt ||
                    existing.status === "submitted" ||
                    existing.lockedAt) {
                    throw new https_1.HttpsError("failed-precondition", "This link has already been submitted.");
                }
                tx.set(intakeRef, { updatedAt: tsNow() }, { merge: true });
            }
            resumed = true;
        }
        else {
            const newRef = sessionsCol.doc();
            intakeSessionId = newRef.id;
            tx.set(newRef, intakeDraftPayload({ clinicId, linkId }), {
                merge: false,
            });
        }
        if (status !== "used" || !existingSessionId) {
            tx.set(linkRef, {
                status: "used",
                usedAt: tsNow(),
                intakeSessionId,
            }, { merge: true });
        }
        return {
            clinicId,
            kind: "general",
            intakeSessionId,
            flowId: GENERAL_FLOW_ID,
            flowVersion: GENERAL_FLOW_VERSION,
            resumed,
        };
    });
    logger_1.logger.info("resolveIntakeLinkTokenFn ok", {
        clinicId: result.clinicId,
        intakeSessionId: result.intakeSessionId,
        resumed: result.resumed,
        linkId,
    });
    return result;
});
//# sourceMappingURL=resolveIntakeLinkTokenFn.js.map