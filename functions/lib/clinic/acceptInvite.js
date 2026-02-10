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
/**
 * Token format:
 * - Preferred: "<clinicId>.<rawToken>"
 * - Back-compat: "<rawToken>" (will fail unless you still do collectionGroup lookups; we intentionally do NOT)
 */
function parseCompositeToken(token) {
    const t = safeStr(token);
    const dot = t.indexOf(".");
    if (dot <= 0 || dot === t.length - 1) {
        throw new https_1.HttpsError("invalid-argument", "Invite token format invalid. Please use the latest invite link.");
    }
    const clinicId = t.substring(0, dot).trim();
    const rawToken = t.substring(dot + 1).trim();
    if (!clinicId || !rawToken) {
        throw new https_1.HttpsError("invalid-argument", "Invite token format invalid. Please use the latest invite link.");
    }
    return { clinicId, rawToken };
}
async function acceptInvite(req) {
    var _a, _b, _c, _d, _e, _f, _g, _h;
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
    // ✅ Parse token => clinicId + rawToken
    const { clinicId, rawToken } = parseCompositeToken(token);
    const tokenHash = (0, hash_1.hashToken)(rawToken);
    // ✅ Look up invite ONLY within that clinic (no collectionGroup)
    const invitesCol = db.collection("clinics").doc(clinicId).collection("invites");
    const inviteQuery = await invitesCol.where("tokenHash", "==", tokenHash).limit(1).get();
    if (inviteQuery.empty) {
        throw new https_1.HttpsError("not-found", "Invite not found or invalid.");
    }
    const inviteSnap = inviteQuery.docs[0];
    const invite = inviteSnap.data();
    logger_1.logger.info("[acceptInvite] invite located", {
        clinicId,
        inviteId: inviteSnap.id,
        status: safeStr(invite.status),
    });
    // Validate invite state (accept both "pending" and "active" for backwards compat)
    const inviteStatus = safeStr(invite.status);
    if (inviteStatus !== "pending" && inviteStatus !== "active") {
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
    // Permissions: invite.permissions override (from inviteUser) else role template
    const invitePerms = invite.permissions;
    let flattened;
    if (invitePerms && typeof invitePerms === "object" && Object.keys(invitePerms).length > 0) {
        flattened = (0, authz_1.flattenPermissions)(invitePerms);
    }
    else {
        const roleRef = db.collection("clinics").doc(clinicId).collection("roles").doc(roleId);
        const roleSnap = await roleRef.get();
        if (!roleSnap.exists) {
            throw new https_1.HttpsError("invalid-argument", "Role no longer exists.");
        }
        const rolePermissions = ((_c = (_b = roleSnap.data()) === null || _b === void 0 ? void 0 : _b.permissions) !== null && _c !== void 0 ? _c : {});
        flattened = (0, authz_1.flattenPermissions)(rolePermissions);
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    // ✅ CANONICAL membership path = /members
    const canonicalMembershipRef = db
        .collection("clinics")
        .doc(clinicId)
        .collection("members")
        .doc(uid);
    // ✅ Legacy mirror during migration window = /memberships
    const legacyMembershipRef = db
        .collection("clinics")
        .doc(clinicId)
        .collection("memberships")
        .doc(uid);
    // User index mirror (clinic picker)
    const userMembershipRef = db.collection("users").doc(uid).collection("memberships").doc(clinicId);
    // Idempotency: if membership exists in either place, treat as already accepted.
    const [canonExisting, legacyExisting] = await Promise.all([
        canonicalMembershipRef.get(),
        legacyMembershipRef.get(),
    ]);
    if (canonExisting.exists || legacyExisting.exists) {
        logger_1.logger.warn("[acceptInvite] membership already exists (idempotent accept)", {
            clinicId,
            uid,
            canonExists: canonExisting.exists,
            legacyExists: legacyExisting.exists,
        });
        // Mark invite consumed anyway so link can't be reused
        try {
            await inviteSnap.ref.update({
                status: "accepted",
                acceptedAt: now,
                acceptedByUid: uid,
            });
        }
        catch (e) {
            logger_1.logger.warn("[acceptInvite] failed to mark invite accepted during idempotent path", {
                clinicId,
                inviteId: inviteSnap.id,
                err: String(e),
            });
        }
        return { ok: true, success: true, clinicId, alreadyMember: true };
    }
    const clinicSnap = await db.collection("clinics").doc(clinicId).get();
    const clinicName = (_f = (_e = (_d = clinicSnap.data()) === null || _d === void 0 ? void 0 : _d.profile) === null || _e === void 0 ? void 0 : _e.name) !== null && _f !== void 0 ? _f : clinicId;
    const batch = db.batch();
    // Canonical membership (authoritative)
    batch.set(canonicalMembershipRef, {
        role: roleId,
        roleId: roleId, // back-compat
        displayName,
        fullName: displayName, // optional back-compat
        permissions: flattened,
        status: "active",
        active: true, // back-compat
        invitedEmail: inviteEmail,
        invitedByUid: (_g = invite.createdByUid) !== null && _g !== void 0 ? _g : null,
        invitedAt: (_h = invite.createdAt) !== null && _h !== void 0 ? _h : null,
        createdAt: now,
        updatedAt: now,
        createdByUid: uid,
        updatedByUid: uid,
    });
    // Legacy mirror (optional)
    batch.set(legacyMembershipRef, {
        role: roleId,
        roleId: roleId, // back-compat
        displayName,
        fullName: displayName,
        invitedEmail: inviteEmail,
        permissions: flattened,
        active: true,
        status: "active",
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
    // Mark invite consumed
    batch.update(inviteSnap.ref, {
        status: "accepted",
        acceptedAt: now,
        acceptedByUid: uid,
    });
    await batch.commit();
    logger_1.logger.info("[acceptInvite] invite accepted + membership created", {
        clinicId,
        uid,
        roleId,
        wroteCanonical: true,
        wroteLegacy: true,
    });
    return { ok: true, success: true, clinicId, alreadyMember: false };
}
//# sourceMappingURL=acceptInvite.js.map