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
exports.deletePatient = deletePatient;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const logger_1 = require("firebase-functions/logger");
const authz_1 = require("../authz");
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
}
async function requireOwnerOrManagerLike(db, clinicId, uid) {
    // Preferred: explicit perms
    try {
        await (0, authz_1.requireActiveMemberWithPerm)(db, clinicId, uid, "patients.manage");
        return;
    }
    catch (_) {
        // fallback: settings.write is typically owner/manager in your model
    }
    await (0, authz_1.requireActiveMemberWithPerm)(db, clinicId, uid, "settings.write");
}
async function deletePatient(req) {
    var _a, _b, _c, _d;
    try {
        if (!req.auth)
            throw new https_1.HttpsError("unauthenticated", "Sign in required.");
        const clinicId = safeStr((_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId);
        const patientId = safeStr((_b = req.data) === null || _b === void 0 ? void 0 : _b.patientId);
        if (!clinicId)
            throw new https_1.HttpsError("invalid-argument", "clinicId is required.");
        if (!patientId)
            throw new https_1.HttpsError("invalid-argument", "patientId is required.");
        const uid = req.auth.uid;
        const db = admin.firestore();
        await requireOwnerOrManagerLike(db, clinicId, uid);
        const patientRef = db.collection("clinics").doc(clinicId).collection("patients").doc(patientId);
        const snap = await patientRef.get();
        if (!snap.exists)
            throw new https_1.HttpsError("not-found", "Patient not found.");
        const now = admin.firestore.FieldValue.serverTimestamp();
        // Soft delete (safe + reversible)
        await patientRef.set({
            active: false,
            archived: true, // legacy
            status: {
                active: false,
                archived: true,
                archivedAt: now,
            },
            deletedAt: now,
            deletedByUid: uid,
            updatedAt: now,
            updatedByUid: uid,
        }, { merge: true });
        logger_1.logger.info("deletePatient ok", { clinicId, patientId, uid });
        return { ok: true };
    }
    catch (err) {
        logger_1.logger.error("deletePatient failed", {
            err: (_c = err === null || err === void 0 ? void 0 : err.message) !== null && _c !== void 0 ? _c : String(err),
            code: err === null || err === void 0 ? void 0 : err.code,
            details: err === null || err === void 0 ? void 0 : err.details,
            stack: err === null || err === void 0 ? void 0 : err.stack,
        });
        if (err instanceof https_1.HttpsError)
            throw err;
        throw new https_1.HttpsError("internal", "deletePatient crashed. Check logs.", {
            original: (_d = err === null || err === void 0 ? void 0 : err.message) !== null && _d !== void 0 ? _d : String(err),
        });
    }
}
//# sourceMappingURL=deletePatient.js.map