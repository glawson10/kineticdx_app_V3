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
exports.getMembershipDoc = getMembershipDoc;
exports.requireTemplatesManage = requireTemplatesManage;
exports.cleanString = cleanString;
exports.asStringArray = asStringArray;
// functions/src/clinic/helpers.ts
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
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
/**
 * Canonical membership reader:
 * - primary: clinics/{clinicId}/memberships/{uid}
 * - legacy fallback: clinics/{clinicId}/members/{uid}
 */
async function getMembershipDoc(db, clinicId, uid) {
    var _a, _b;
    const canonRef = db
        .collection("clinics")
        .doc(clinicId)
        .collection("memberships")
        .doc(uid);
    const canonSnap = await canonRef.get();
    if (canonSnap.exists) {
        return { path: canonRef.path, data: ((_a = canonSnap.data()) !== null && _a !== void 0 ? _a : {}) };
    }
    // legacy fallback (temporary during migration)
    const legacyRef = db
        .collection("clinics")
        .doc(clinicId)
        .collection("members")
        .doc(uid);
    const legacySnap = await legacyRef.get();
    if (legacySnap.exists) {
        return { path: legacyRef.path, data: ((_b = legacySnap.data()) !== null && _b !== void 0 ? _b : {}) };
    }
    return null;
}
/**
 * Require templates.manage permission on an active membership.
 */
async function requireTemplatesManage(req) {
    var _a;
    if (!req.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const clinicId = safeStr((_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId);
    if (!clinicId)
        throw new https_1.HttpsError("invalid-argument", "clinicId required.");
    const db = admin.firestore();
    const uid = req.auth.uid;
    const m = await getMembershipDoc(db, clinicId, uid);
    if (!m) {
        throw new https_1.HttpsError("permission-denied", "Not a clinic member.");
    }
    const data = m.data;
    if (!isActiveMemberDoc(data)) {
        throw new https_1.HttpsError("permission-denied", "Not an active clinic member.");
    }
    const perms = (data === null || data === void 0 ? void 0 : data.permissions) && typeof data.permissions === "object"
        ? data.permissions
        : {};
    if (perms["templates.manage"] !== true) {
        throw new https_1.HttpsError("permission-denied", "No templates.manage permission.");
    }
    return { db, clinicId, uid, perms };
}
function cleanString(v, max = 300) {
    const s = (v !== null && v !== void 0 ? v : "").toString().trim();
    if (!s)
        return "";
    return s.length > max ? s.substring(0, max) : s;
}
function asStringArray(v) {
    if (!Array.isArray(v))
        return [];
    return v
        .map((x) => (x !== null && x !== void 0 ? x : "").toString().trim())
        .filter((x) => x.length > 0);
}
//# sourceMappingURL=_helpers.js.map