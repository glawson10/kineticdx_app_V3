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
exports.setMembershipStatus = setMembershipStatus;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const authz_1 = require("./authz");
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
}
function normalizeStatus(v) {
    const s = safeStr(v).toLowerCase();
    if (s === "active" || s === "suspended")
        return s;
    throw new https_1.HttpsError("invalid-argument", "status must be active|suspended");
}
async function setMembershipStatus(req) {
    var _a, _b, _c;
    if (!req.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const clinicId = safeStr((_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId);
    const memberUid = safeStr((_b = req.data) === null || _b === void 0 ? void 0 : _b.memberUid);
    const status = normalizeStatus((_c = req.data) === null || _c === void 0 ? void 0 : _c.status);
    if (!clinicId || !memberUid) {
        throw new https_1.HttpsError("invalid-argument", "clinicId and memberUid are required.");
    }
    const db = admin.firestore();
    const actorUid = req.auth.uid;
    // ✅ Only staff managers can change membership status
    await (0, authz_1.requireActiveMemberWithPerm)(db, clinicId, actorUid, "members.manage");
    // Optional safety: do not allow self-suspension (avoid locking yourself out)
    if (actorUid === memberUid) {
        throw new https_1.HttpsError("failed-precondition", "You cannot change your own status.");
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    const canonRef = db.doc(`clinics/${clinicId}/memberships/${memberUid}`);
    const legacyRef = db.doc(`clinics/${clinicId}/members/${memberUid}`);
    const batch = db.batch();
    // canonical
    batch.set(canonRef, {
        status,
        active: status === "active",
        updatedAt: now,
        updatedByUid: actorUid,
    }, { merge: true });
    // legacy mirror (migration window)
    batch.set(legacyRef, {
        active: status === "active",
        updatedAt: now,
    }, { merge: true });
    await batch.commit();
    // Optional: audit event
    const auditRef = db.collection(`clinics/${clinicId}/audit`).doc();
    await auditRef.set({
        type: "membership.status_changed",
        clinicId,
        actor: { uid: actorUid },
        subject: { uid: memberUid },
        status,
        at: now,
        schemaVersion: 1,
    });
    return { ok: true };
}
//# sourceMappingURL=setMembershipStatus.js.map