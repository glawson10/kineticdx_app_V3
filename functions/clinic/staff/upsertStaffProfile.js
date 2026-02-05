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
exports.upsertStaffProfile = upsertStaffProfile;
// functions/src/clinic/staff/upsertStaffProfile.ts
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
    if (p && typeof p === "object")
        return p;
    return {};
}
async function getMembershipWithFallback(params) {
    var _a, _b;
    const canonRef = db
        .collection("clinics")
        .doc(params.clinicId)
        .collection("memberships")
        .doc(params.uid);
    const canonSnap = await canonRef.get();
    if (canonSnap.exists)
        return ((_a = canonSnap.data()) !== null && _a !== void 0 ? _a : {});
    const legacyRef = db
        .collection("clinics")
        .doc(params.clinicId)
        .collection("members")
        .doc(params.uid);
    const legacySnap = await legacyRef.get();
    if (legacySnap.exists)
        return ((_b = legacySnap.data()) !== null && _b !== void 0 ? _b : {});
    return null;
}
function ensurePlainObject(v, label) {
    if (!v || typeof v !== "object" || Array.isArray(v)) {
        throw new https_1.HttpsError("invalid-argument", `${label} must be an object.`);
    }
    return v;
}
function clampLen(s, max) {
    const t = safeStr(s);
    if (t.length <= max)
        return t;
    return t.substring(0, max);
}
function sanitizeEmail(s) {
    const t = safeStr(s).toLowerCase();
    if (!t)
        return "";
    // basic check only
    if (!t.includes("@") || t.length < 5) {
        throw new https_1.HttpsError("invalid-argument", "contact.email is invalid.");
    }
    return clampLen(t, 254);
}
function sanitizePhone(s) {
    const t = safeStr(s);
    if (!t)
        return "";
    // allow +, digits, spaces, parentheses, hyphen
    const ok = /^[0-9+\-() ]{5,40}$/.test(t);
    if (!ok) {
        throw new https_1.HttpsError("invalid-argument", "contact.phone is invalid.");
    }
    return clampLen(t, 40);
}
/**
 * Allowlist only the fields we want staffProfiles to accept.
 * This prevents arbitrary writes / schema drift.
 */
function sanitizeStaffProfilePatch(raw) {
    const patch = ensurePlainObject(raw, "patch");
    const out = {};
    if ("schemaVersion" in patch) {
        const v = Number(patch.schemaVersion);
        out.schemaVersion = Number.isFinite(v) ? v : 1;
    }
    else {
        out.schemaVersion = 1;
    }
    if ("displayName" in patch)
        out.displayName = clampLen(patch.displayName, 120);
    if ("firstName" in patch)
        out.firstName = clampLen(patch.firstName, 80);
    if ("lastName" in patch)
        out.lastName = clampLen(patch.lastName, 80);
    if ("title" in patch)
        out.title = clampLen(patch.title, 120);
    if ("notes" in patch)
        out.notes = clampLen(patch.notes, 8000);
    if ("photo" in patch) {
        const photo = ensurePlainObject(patch.photo, "photo");
        const p = {};
        if ("storagePath" in photo)
            p.storagePath = clampLen(photo.storagePath, 300);
        if ("url" in photo)
            p.url = clampLen(photo.url, 500);
        out.photo = p;
    }
    if ("contact" in patch) {
        const contact = ensurePlainObject(patch.contact, "contact");
        const c = {};
        if ("email" in contact)
            c.email = sanitizeEmail(contact.email);
        if ("phone" in contact)
            c.phone = sanitizePhone(contact.phone);
        if ("address" in contact) {
            const address = ensurePlainObject(contact.address, "contact.address");
            c.address = {
                line1: clampLen(address.line1, 120),
                line2: clampLen(address.line2, 120),
                city: clampLen(address.city, 80),
                postcode: clampLen(address.postcode, 30),
                country: clampLen(address.country, 80),
            };
        }
        if ("emergencyContact" in contact) {
            const ec = ensurePlainObject(contact.emergencyContact, "contact.emergencyContact");
            c.emergencyContact = {
                name: clampLen(ec.name, 120),
                relationship: clampLen(ec.relationship, 80),
                phone: ec.phone ? sanitizePhone(ec.phone) : "",
            };
        }
        out.contact = c;
    }
    if ("professional" in patch) {
        // keep this permissive for now, but still require object
        const prof = ensurePlainObject(patch.professional, "professional");
        out.professional = prof;
    }
    // If nothing besides schemaVersion is present, still allow (creates doc shell)
    return out;
}
async function upsertStaffProfile(req) {
    var _a, _b, _c;
    if (!req.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const clinicId = safeStr((_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId);
    const targetUid = safeStr((_b = req.data) === null || _b === void 0 ? void 0 : _b.uid);
    if (!clinicId)
        throw new https_1.HttpsError("invalid-argument", "clinicId required.");
    if (!targetUid)
        throw new https_1.HttpsError("invalid-argument", "uid required.");
    const actorUid = req.auth.uid;
    // ✅ authorize actor
    const actorMembership = await getMembershipWithFallback({
        clinicId,
        uid: actorUid,
    });
    if (!actorMembership) {
        throw new https_1.HttpsError("permission-denied", "Not a clinic member.");
    }
    if (!isMemberActiveLike(actorMembership)) {
        throw new https_1.HttpsError("permission-denied", "Membership not active.");
    }
    const perms = getPermissionsMap(actorMembership);
    if (perms["members.manage"] !== true) {
        throw new https_1.HttpsError("permission-denied", "Insufficient permissions.");
    }
    // Optional: ensure target is at least known as a member (canonical or legacy)
    const targetMembership = await getMembershipWithFallback({
        clinicId,
        uid: targetUid,
    });
    if (!targetMembership) {
        throw new https_1.HttpsError("not-found", "Target staff member is not in this clinic.");
    }
    const patchRaw = ensurePlainObject((_c = req.data) === null || _c === void 0 ? void 0 : _c.patch, "patch");
    const patch = sanitizeStaffProfilePatch(patchRaw);
    const profileRef = db
        .collection("clinics")
        .doc(clinicId)
        .collection("staffProfiles")
        .doc(targetUid);
    const snap = await profileRef.get();
    const now = admin.firestore.FieldValue.serverTimestamp();
    const baseAudit = {
        updatedAt: now,
        updatedByUid: actorUid,
    };
    const createAudit = snap.exists
        ? {}
        : {
            createdAt: now,
            createdByUid: actorUid,
        };
    await profileRef.set({
        ...patch,
        ...baseAudit,
        ...createAudit,
    }, { merge: true });
    logger_1.logger.info("upsertStaffProfile: ok", {
        clinicId,
        actorUid,
        targetUid,
        created: !snap.exists,
        keys: Object.keys(patch),
    });
    return { ok: true, uid: targetUid };
}
//# sourceMappingURL=upsertStaffProfile.js.map