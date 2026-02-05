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
exports.updateMemberProfile = updateMemberProfile;
// functions/src/clinic/updateMemberProfile.ts
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const logger_1 = require("firebase-functions/logger");
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
}
function readBoolOrUndefined(v) {
    if (v === true)
        return true;
    if (v === false)
        return false;
    return undefined;
}
function isMemberActiveLike(data) {
    const status = safeStr(data.status);
    if (status === "suspended")
        return false;
    if (status === "invited")
        return false;
    const active = readBoolOrUndefined(data.active);
    if (active !== undefined)
        return active;
    return true;
}
function getPermissionsMap(data) {
    const p = data.permissions;
    if (p && typeof p === "object" && !Array.isArray(p))
        return p;
    return {};
}
/**
 * ✅ Canonical-first membership lookup:
 *   1) clinics/{clinicId}/members/{uid}        (canonical)
 *   2) clinics/{clinicId}/memberships/{uid}    (legacy fallback)
 */
async function getMembershipWithFallback(params) {
    var _a, _b;
    const canonicalRef = db
        .collection("clinics")
        .doc(params.clinicId)
        .collection("members")
        .doc(params.uid);
    const canonicalSnap = await canonicalRef.get();
    if (canonicalSnap.exists)
        return ((_a = canonicalSnap.data()) !== null && _a !== void 0 ? _a : {});
    const legacyRef = db
        .collection("clinics")
        .doc(params.clinicId)
        .collection("memberships")
        .doc(params.uid);
    const legacySnap = await legacyRef.get();
    if (legacySnap.exists)
        return ((_b = legacySnap.data()) !== null && _b !== void 0 ? _b : {});
    return null;
}
function clampLen(s, max) {
    const t = safeStr(s);
    if (t.length <= max)
        return t;
    return t.substring(0, max);
}
async function updateMemberProfile(req) {
    var _a, _b, _c;
    if (!req.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const clinicId = safeStr((_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId);
    const memberUid = safeStr((_b = req.data) === null || _b === void 0 ? void 0 : _b.memberUid);
    const displayNameRaw = safeStr((_c = req.data) === null || _c === void 0 ? void 0 : _c.displayName);
    if (!clinicId)
        throw new https_1.HttpsError("invalid-argument", "clinicId required.");
    if (!memberUid)
        throw new https_1.HttpsError("invalid-argument", "memberUid required.");
    if (!displayNameRaw)
        throw new https_1.HttpsError("invalid-argument", "displayName required.");
    // Keep membership doc tidy / predictable
    const displayName = clampLen(displayNameRaw, 120);
    const actorUid = req.auth.uid;
    // ✅ authorize actor
    const actorMembership = await getMembershipWithFallback({ clinicId, uid: actorUid });
    if (!actorMembership)
        throw new https_1.HttpsError("permission-denied", "Not a clinic member.");
    if (!isMemberActiveLike(actorMembership)) {
        throw new https_1.HttpsError("permission-denied", "Membership not active.");
    }
    const perms = getPermissionsMap(actorMembership);
    if (perms["members.manage"] !== true) {
        throw new https_1.HttpsError("permission-denied", "Insufficient permissions.");
    }
    // ✅ target must exist in at least one place
    // canonical first
    const canonRef = db
        .collection("clinics")
        .doc(clinicId)
        .collection("members")
        .doc(memberUid);
    const legacyRef = db
        .collection("clinics")
        .doc(clinicId)
        .collection("memberships")
        .doc(memberUid);
    const [canonSnap, legacySnap] = await Promise.all([canonRef.get(), legacyRef.get()]);
    if (!canonSnap.exists && !legacySnap.exists) {
        throw new https_1.HttpsError("not-found", "Target member not found.");
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    const patch = {
        displayName,
        fullName: displayName, // legacy convenience
        updatedAt: now,
        updatedByUid: actorUid,
    };
    const batch = db.batch();
    if (canonSnap.exists)
        batch.set(canonRef, patch, { merge: true });
    if (legacySnap.exists)
        batch.set(legacyRef, patch, { merge: true });
    await batch.commit();
    logger_1.logger.info("updateMemberProfile: updated", {
        clinicId,
        actorUid,
        memberUid,
        displayName,
        wroteCanonical: canonSnap.exists,
        wroteLegacy: legacySnap.exists,
    });
    return { ok: true, memberUid, displayName };
}
//# sourceMappingURL=updateMemberProfile.js.map