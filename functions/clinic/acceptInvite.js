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
exports.acceptInvite = acceptInvite;
// functions/src/clinic/acceptInvite.ts
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const logger_1 = require("firebase-functions/logger");
const hash_1 = require("./hash");
const authz_1 = require("./authz");
function normEmail(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim().toLowerCase();
}
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
}
function fallbackNameFromEmail(emailLower) {
    var _a;
    const local = ((_a = emailLower.split("@")[0]) !== null && _a !== void 0 ? _a : "").trim();
    if (!local)
        return "User";
    const pretty = local.replace(/[._-]+/g, " ").trim();
    return pretty || local;
}
async function resolveDisplayName(uid, emailLower, authToken) {
    // 1) Best: Firebase Auth profile
    try {
        const u = await admin.auth().getUser(uid);
        const dn = safeStr(u.displayName);
        if (dn)
            return dn;
    }
    catch (e) {
        logger_1.logger.warn("[acceptInvite] getUser() failed (continuing with fallback)", {
            uid,
            err: String(e),
        });
    }
    // 2) Token fallbacks (sometimes present)
    const candidates = [
        authToken === null || authToken === void 0 ? void 0 : authToken.name,
        authToken === null || authToken === void 0 ? void 0 : authToken.display_name,
        authToken === null || authToken === void 0 ? void 0 : authToken.displayName,
        authToken === null || authToken === void 0 ? void 0 : authToken["display_name"],
        authToken === null || authToken === void 0 ? void 0 : authToken["displayName"],
    ];
    for (const c of candidates) {
        const s = safeStr(c);
        if (s)
            return s;
    }
    // 3) Email-derived fallback
    return fallbackNameFromEmail(emailLower);
}
// Back-compat: missing active => active
function isActiveMemberDoc(d) {
    const status = safeStr(d === null || d === void 0 ? void 0 : d.status);
    if (status === "suspended")
        return false;
    if (status === "invited")
        return false;
    if ("active" in (d !== null && d !== void 0 ? d : {}))
        return d.active === true;
    return true;
}
// Canonical membership reader for inviter checks (not used here, but handy if needed later)
async function getMembershipDoc(db, clinicId, uid) {
    var _a, _b;
    const canonRef = db.collection("clinics").doc(clinicId).collection("memberships").doc(uid);
    const canonSnap = await canonRef.get();
    if (canonSnap.exists)
        return { path: canonRef.path, data: ((_a = canonSnap.data()) !== null && _a !== void 0 ? _a : {}) };
    const legacyRef = db.collection("clinics").doc(clinicId).collection("members").doc(uid);
    const legacySnap = await legacyRef.get();
    if (legacySnap.exists)
        return { path: legacyRef.path, data: ((_b = legacySnap.data()) !== null && _b !== void 0 ? _b : {}) };
    return null;
}
async function acceptInvite(req) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j;
    if (!req.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const token = safeStr((_a = req.data) === null || _a === void 0 ? void 0 : _a.token);
    if (!token)
        throw new https_1.HttpsError("invalid-argument", "Invite token required.");
    const db = admin.firestore();
    const uid = req.auth.uid;
    const userEmail = normEmail(req.auth.token.email);
    if (!userEmail) {
        throw new https_1.HttpsError("failed-precondition", "User email not available.");
    }
    const displayName = await resolveDisplayName(uid, userEmail, req.auth.token);
    logger_1.logger.info("[acceptInvite] resolved displayName", { uid, userEmail, displayName });
    const tokenHash = (0, hash_1.hashToken)(token);
    // Find invite by tokenHash (collectionGroup across clinics/*/invites)
    const inviteQuery = await db
        .collectionGroup("invites")
        .where("tokenHash", "==", tokenHash)
        .limit(1)
        .get();
    if (inviteQuery.empty) {
        throw new https_1.HttpsError("not-found", "Invite not found or invalid.");
    }
    const inviteSnap = inviteQuery.docs[0];
    const invite = inviteSnap.data();
    const clinicId = (_b = inviteSnap.ref.parent.parent) === null || _b === void 0 ? void 0 : _b.id;
    if (!clinicId)
        throw new https_1.HttpsError("internal", "Clinic reference missing.");
    // Validate invite state
    if (safeStr(invite.status) !== "pending") {
        throw new https_1.HttpsError("failed-precondition", "Invite already used or revoked.");
    }
    if (!invite.expiresAt || typeof invite.expiresAt.toMillis !== "function") {
        throw new https_1.HttpsError("failed-precondition", "Invite expiry missing.");
    }
    if (invite.expiresAt.toMillis() < Date.now()) {
        throw new https_1.HttpsError("deadline-exceeded", "Invite expired.");
    }
    const inviteEmail = normEmail(invite.email);
    if (inviteEmail !== userEmail) {
        throw new https_1.HttpsError("permission-denied", "Invite email does not match signed-in user.");
    }
    const roleId = safeStr(invite.roleId);
    if (!roleId)
        throw new https_1.HttpsError("invalid-argument", "Invite roleId missing.");
    // Load role permissions
    const roleRef = db.collection("clinics").doc(clinicId).collection("roles").doc(roleId);
    const roleSnap = await roleRef.get();
    if (!roleSnap.exists) {
        throw new https_1.HttpsError("invalid-argument", "Role no longer exists.");
    }
    const rolePermissions = ((_d = (_c = roleSnap.data()) === null || _c === void 0 ? void 0 : _c.permissions) !== null && _d !== void 0 ? _d : {});
    const flattened = (0, authz_1.flattenPermissions)(rolePermissions);
    const now = admin.firestore.FieldValue.serverTimestamp();
    const canonicalMembershipRef = db
        .collection("clinics")
        .doc(clinicId)
        .collection("memberships")
        .doc(uid);
    const legacyMemberRef = db.collection("clinics").doc(clinicId).collection("members").doc(uid);
    const userMembershipRef = db.collection("users").doc(uid).collection("memberships").doc(clinicId);
    // Idempotency: if membership exists, reject (keeps semantics strict)
    const existingCanon = await canonicalMembershipRef.get();
    if (existingCanon.exists) {
        throw new https_1.HttpsError("failed-precondition", "Membership already exists for this clinic.");
    }
    const clinicSnap = await db.collection("clinics").doc(clinicId).get();
    const clinicName = (_g = (_f = (_e = clinicSnap.data()) === null || _e === void 0 ? void 0 : _e.profile) === null || _f === void 0 ? void 0 : _f.name) !== null && _g !== void 0 ? _g : clinicId;
    const batch = db.batch();
    // Canonical membership (authoritative)
    batch.set(canonicalMembershipRef, {
        role: roleId,
        roleId: roleId, // back-compat
        // ✅ Name fields for UI
        displayName,
        fullName: displayName, // optional back-compat
        permissions: flattened,
        status: "active",
        active: true, // back-compat
        invitedEmail: inviteEmail,
        invitedByUid: (_h = invite.createdByUid) !== null && _h !== void 0 ? _h : null,
        invitedAt: (_j = invite.createdAt) !== null && _j !== void 0 ? _j : null,
        createdAt: now,
        updatedAt: now,
        createdByUid: uid,
        updatedByUid: uid,
    });
    // Legacy mirror (optional during migration window)
    batch.set(legacyMemberRef, {
        roleId: roleId,
        displayName,
        fullName: displayName,
        invitedEmail: inviteEmail,
        permissions: flattened,
        active: true,
        status: "active", // helps any legacy readers that look at status
        createdAt: now,
        updatedAt: now,
        createdByUid: uid,
        updatedByUid: uid,
    });
    // User index mirror (clinic picker)
    batch.set(userMembershipRef, {
        clinicNameCache: clinicName,
        role: roleId,
        roleId: roleId, // back-compat
        status: "active",
        active: true, // back-compat
        createdAt: now,
    });
    // Mark invite consumed (do NOT delete; keep audit trail)
    batch.update(inviteSnap.ref, {
        status: "accepted",
        acceptedAt: now,
        acceptedByUid: uid,
    });
    await batch.commit();
    return { success: true, clinicId };
}
//# sourceMappingURL=acceptInvite.js.map