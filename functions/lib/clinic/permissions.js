"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.requireClinicPermission = requireClinicPermission;
const https_1 = require("firebase-functions/v2/https");
function safeStr(v) {
    return typeof v === "string" ? v.trim() : "";
}
function readPerms(raw) {
    if (!raw || typeof raw !== "object")
        return {};
    const m = raw;
    const out = {};
    for (const k of Object.keys(m))
        out[k] = m[k] === true;
    return out;
}
async function loadMemberDoc(db, clinicId, uid) {
    // ✅ Primary path used by your Flutter self-check UI
    const ref = db.doc(`clinics/${clinicId}/members/${uid}`);
    const snap = await ref.get();
    if (snap.exists) {
        const d = snap.data();
        const roleId = typeof (d === null || d === void 0 ? void 0 : d.roleId) === "string" ? d.roleId.trim() : null;
        return {
            exists: true,
            active: (d === null || d === void 0 ? void 0 : d.active) === true,
            permissions: readPerms(d === null || d === void 0 ? void 0 : d.permissions),
            roleId,
        };
    }
    // Optional fallback (only if you had an older schema)
    const legacyRef = db.doc(`clinics/${clinicId}/memberships/${uid}`);
    const legacySnap = await legacyRef.get();
    if (legacySnap.exists) {
        const d = legacySnap.data();
        const roleId = typeof (d === null || d === void 0 ? void 0 : d.roleId) === "string" ? d.roleId.trim() : null;
        return {
            exists: true,
            active: (d === null || d === void 0 ? void 0 : d.active) === true,
            permissions: readPerms(d === null || d === void 0 ? void 0 : d.permissions),
            roleId,
        };
    }
    return { exists: false, active: false, permissions: {}, roleId: null };
}
/**
 * Enforce clinic permission based on member doc:
 * clinics/{clinicId}/members/{uid}.permissions[permKey] === true AND active === true
 */
async function requireClinicPermission(db, clinicId, uid, permKey) {
    const c = safeStr(clinicId);
    const u = safeStr(uid);
    const k = safeStr(permKey);
    if (!c || !u || !k) {
        throw new https_1.HttpsError("invalid-argument", "Invalid permission check args.");
    }
    const member = await loadMemberDoc(db, c, u);
    if (!member.exists) {
        throw new https_1.HttpsError("permission-denied", "No membership doc for uid in clinic.");
    }
    if (!member.active) {
        throw new https_1.HttpsError("permission-denied", "Membership inactive for this clinic.");
    }
    // Owners always pass (full access even if permissions map is incomplete or mis-typed)
    if (member.roleId === "owner") {
        return { active: member.active, permissions: member.permissions };
    }
    if (member.permissions[k] !== true) {
        throw new https_1.HttpsError("permission-denied", `Missing permission: ${k}`);
    }
    // Returning this is handy for callers like updateNote
    return { active: member.active, permissions: member.permissions };
}
//# sourceMappingURL=permissions.js.map