"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.isActiveMembership = isActiveMembership;
exports.flattenPermissions = flattenPermissions;
exports.requireActiveMember = requireActiveMember;
exports.requireActiveMemberWithPerm = requireActiveMemberWithPerm;
exports.hasPerm = hasPerm;
exports.requireCanAmendNote = requireCanAmendNote;
const https_1 = require("firebase-functions/v2/https");
function norm(s) {
    return (s !== null && s !== void 0 ? s : "").toString().trim();
}
/**
 * Canonical membership location:
 *   clinics/{clinicId}/memberships/{uid}
 *
 * Legacy fallback (migration):
 *   clinics/{clinicId}/members/{uid}
 *
 * NOTE: We do NOT use users/{uid}/memberships/{clinicId} for authz because it's an index mirror.
 */
async function getClinicMembershipSnap(db, clinicId, uid) {
    const canonRef = db.doc(`clinics/${clinicId}/memberships/${uid}`);
    const canonSnap = await canonRef.get();
    if (canonSnap.exists)
        return canonSnap;
    const legacyRef = db.doc(`clinics/${clinicId}/members/${uid}`);
    const legacySnap = await legacyRef.get();
    if (legacySnap.exists)
        return legacySnap;
    return null;
}
/**
 * Back-compat membership active rules:
 * - If status is present:
 *    - "active" => active
 *    - "suspended" => inactive
 *    - "invited" => inactive (they should only use accept flow)
 * - Else if active field exists => must be true
 * - Else (missing active) => treat as active (matches your Firestore rules)
 */
function isActiveMembership(data) {
    const status = norm(data.status).toLowerCase();
    if (status === "active")
        return true;
    if (status === "suspended")
        return false;
    if (status === "invited")
        return false;
    if ("active" in data)
        return data.active === true;
    return true; // missing active => active
}
function flattenPermissions(rolePermissions) {
    const flattened = {};
    for (const k of Object.keys(rolePermissions !== null && rolePermissions !== void 0 ? rolePermissions : {})) {
        flattened[k] = rolePermissions[k] === true;
    }
    return flattened;
}
async function requireActiveMember(db, clinicId, uid) {
    const snap = await getClinicMembershipSnap(db, clinicId, uid);
    if (!snap) {
        throw new https_1.HttpsError("permission-denied", "Not a clinic member.");
    }
    const data = (snap.data() || {});
    if (!isActiveMembership(data)) {
        throw new https_1.HttpsError("permission-denied", "Membership inactive.");
    }
    return data;
}
async function requireActiveMemberWithPerm(db, clinicId, uid, perm) {
    var _a;
    const member = await requireActiveMember(db, clinicId, uid);
    const perms = ((_a = member.permissions) !== null && _a !== void 0 ? _a : {});
    if (perms[perm] !== true) {
        throw new https_1.HttpsError("permission-denied", `Missing permission: ${perm}`);
    }
    return member;
}
async function hasPerm(db, clinicId, uid, perm) {
    try {
        await requireActiveMemberWithPerm(db, clinicId, uid, perm);
        return true;
    }
    catch {
        return false;
    }
}
/**
 * Notes policy:
 * - notes.write.own → can amend own notes
 * - notes.write.any → can amend any notes
 */
async function requireCanAmendNote(db, clinicId, actorUid, authorUid) {
    var _a;
    const member = await requireActiveMember(db, clinicId, actorUid);
    const perms = ((_a = member.permissions) !== null && _a !== void 0 ? _a : {});
    if (actorUid === authorUid && perms["notes.write.own"] === true) {
        return "own";
    }
    if (perms["notes.write.any"] === true) {
        return "any";
    }
    throw new https_1.HttpsError("permission-denied", "You are not allowed to amend this note.");
}
//# sourceMappingURL=authz.js.map