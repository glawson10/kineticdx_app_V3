"use strict";
// functions/src/clinic/updateMember.ts
// membership.updateMember: update role and/or permissions for a member.
// Caller must have members.manage. Cannot demote the last active owner.
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
exports.updateMember = updateMember;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const authz_1 = require("./authz");
const roleTemplates_1 = require("./roleTemplates");
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
}
function isOwner(data) {
    const role = (safeStr(data.roleId) || safeStr(data.role)).toLowerCase();
    return role === "owner";
}
async function updateMember(req) {
    var _a, _b, _c;
    if (!req.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const clinicId = safeStr((_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId);
    const memberUid = safeStr((_b = req.data) === null || _b === void 0 ? void 0 : _b.memberUid);
    const patch = (_c = req.data) === null || _c === void 0 ? void 0 : _c.patch;
    if (!clinicId || !memberUid) {
        throw new https_1.HttpsError("invalid-argument", "clinicId and memberUid are required.");
    }
    if (!patch || typeof patch !== "object") {
        throw new https_1.HttpsError("invalid-argument", "patch (role and/or permissions) is required.");
    }
    const actorUid = req.auth.uid;
    await (0, authz_1.requireActiveMemberWithPerm)(db, clinicId, actorUid, "members.manage");
    const snap = await (0, authz_1.getClinicMembershipSnap)(db, clinicId, memberUid);
    if (!snap) {
        throw new https_1.HttpsError("not-found", "Member not found.");
    }
    const existing = (snap.data() || {});
    // Last-owner guard: cannot demote or remove permissions such that this member
    // would no longer be an owner if they are currently the last active owner.
    if (isOwner(existing) && (0, authz_1.isActiveMembership)(existing)) {
        const newRole = safeStr(patch.role).toLowerCase();
        const becomingNonOwner = newRole.length > 0 && newRole !== "owner";
        const permsOverride = patch.permissions;
        const losingOwnerPerms = permsOverride &&
            typeof permsOverride === "object" &&
            (permsOverride["members.manage"] === false || permsOverride["settings.write"] === false);
        if (becomingNonOwner || losingOwnerPerms) {
            const ownerCount = await (0, authz_1.countActiveOwners)(db, clinicId);
            if (ownerCount <= 1) {
                throw new https_1.HttpsError("failed-precondition", "Cannot demote or remove the last active owner. Assign another owner first.");
            }
        }
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    const updates = {
        updatedAt: now,
        updatedByUid: actorUid,
    };
    if (patch.role !== undefined) {
        const role = safeStr(patch.role);
        if (role.length > 0) {
            updates.role = role;
            updates.roleId = role;
            if (role.toLowerCase() === "owner" && !(patch.permissions && typeof patch.permissions === "object")) {
                updates.permissions = (0, roleTemplates_1.ownerRolePermissions)();
            }
        }
    }
    if (patch.permissions !== undefined && typeof patch.permissions === "object") {
        updates.permissions = (0, authz_1.flattenPermissions)(patch.permissions);
    }
    const canonRef = db.doc(`clinics/${clinicId}/members/${memberUid}`);
    const legacyRef = db.doc(`clinics/${clinicId}/memberships/${memberUid}`);
    const batch = db.batch();
    batch.set(canonRef, updates, { merge: true });
    batch.set(legacyRef, updates, { merge: true });
    await batch.commit();
    const auditRef = db.collection(`clinics/${clinicId}/audit`).doc();
    await auditRef.set({
        type: "membership.updated",
        clinicId,
        actor: { uid: actorUid },
        subject: { uid: memberUid },
        patch: { role: patch.role, permissionsKeys: patch.permissions ? Object.keys(patch.permissions) : [] },
        at: now,
        schemaVersion: 1,
    });
    return { ok: true };
}
//# sourceMappingURL=updateMember.js.map