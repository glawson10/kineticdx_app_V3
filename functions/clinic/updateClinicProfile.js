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
exports.updateClinicProfile = updateClinicProfile;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const db = admin.firestore();
const FV = admin.firestore.FieldValue;
function isNonEmptyString(v) {
    return typeof v === "string" && v.trim().length > 0;
}
function asStringOrNull(v, maxLen) {
    // undefined => not provided
    if (v === undefined)
        return undefined;
    // null => explicit delete
    if (v === null)
        return null;
    if (typeof v !== "string")
        return undefined;
    const s = v.trim();
    if (!s)
        return null; // empty string => treat as delete
    return s.length > maxLen ? s.slice(0, maxLen) : s;
}
function normalizeUrlOrNull(v) {
    if (v == null)
        return null;
    const s = v.trim();
    if (!s)
        return null;
    const lower = s.toLowerCase();
    if (lower.startsWith("http://") || lower.startsWith("https://"))
        return s;
    // allow "example.com" style inputs
    if (lower.includes(".") && !lower.includes(" "))
        return `https://${s}`;
    return s;
}
function cleanPatch(input) {
    const patch = {};
    patch.name = asStringOrNull(input === null || input === void 0 ? void 0 : input.name, 80);
    patch.phone = asStringOrNull(input === null || input === void 0 ? void 0 : input.phone, 40);
    patch.email = asStringOrNull(input === null || input === void 0 ? void 0 : input.email, 120);
    patch.timezone = asStringOrNull(input === null || input === void 0 ? void 0 : input.timezone, 64);
    patch.address = asStringOrNull(input === null || input === void 0 ? void 0 : input.address, 200);
    patch.logoUrl = asStringOrNull(input === null || input === void 0 ? void 0 : input.logoUrl, 500);
    patch.defaultLanguage = asStringOrNull(input === null || input === void 0 ? void 0 : input.defaultLanguage, 10);
    patch.landingUrl = asStringOrNull(input === null || input === void 0 ? void 0 : input.landingUrl, 240);
    patch.websiteUrl = asStringOrNull(input === null || input === void 0 ? void 0 : input.websiteUrl, 240);
    patch.whatsapp = asStringOrNull(input === null || input === void 0 ? void 0 : input.whatsapp, 120);
    // Normalize URLs (only if defined)
    if (patch.landingUrl !== undefined)
        patch.landingUrl = normalizeUrlOrNull(patch.landingUrl);
    if (patch.websiteUrl !== undefined)
        patch.websiteUrl = normalizeUrlOrNull(patch.websiteUrl);
    return patch;
}
function validateTimezone(tz) {
    const ok = /^[A-Za-z_]+\/[A-Za-z_]+(?:\/[A-Za-z_]+)?$/.test(tz);
    if (!ok) {
        throw new https_1.HttpsError("invalid-argument", "Invalid timezone format.");
    }
}
async function getAuthoritativeMembership(clinicId, uid) {
    var _a, _b;
    // ✅ Match Firestore rules:
    // Canonical: clinics/{clinicId}/members/{uid}
    // Legacy:    clinics/{clinicId}/memberships/{uid}
    const canonical = db.doc(`clinics/${clinicId}/members/${uid}`);
    const legacy = db.doc(`clinics/${clinicId}/memberships/${uid}`);
    const c = await canonical.get();
    if (c.exists)
        return (_a = c.data()) !== null && _a !== void 0 ? _a : {};
    const l = await legacy.get();
    if (l.exists)
        return (_b = l.data()) !== null && _b !== void 0 ? _b : {};
    return null;
}
function isActiveMember(data) {
    // ✅ Match Firestore rules: missing "active" => active (back-compat)
    if (!("active" in data))
        return true;
    return data.active === true;
}
function hasSettingsWrite(data) {
    const perms = data.permissions;
    return !!(perms && typeof perms === "object" && perms["settings.write"] === true);
}
function anyMeaningfulKeys(patch) {
    // If every key is undefined, it means nothing was provided.
    // null counts (it means delete).
    return Object.values(patch).some((v) => v !== undefined);
}
function setOrDelete(updateData, key, value) {
    if (value === undefined)
        return; // no change
    if (value === null)
        updateData[key] = FV.delete();
    else
        updateData[key] = value;
}
async function updateClinicProfile(request) {
    var _a, _b, _c;
    if (!((_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid)) {
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    }
    const clinicId = isNonEmptyString((_b = request.data) === null || _b === void 0 ? void 0 : _b.clinicId)
        ? request.data.clinicId.trim().slice(0, 64)
        : "";
    if (!clinicId) {
        throw new https_1.HttpsError("invalid-argument", "clinicId is required.");
    }
    const patch = cleanPatch((_c = request.data) === null || _c === void 0 ? void 0 : _c.patch);
    if (!anyMeaningfulKeys(patch)) {
        throw new https_1.HttpsError("invalid-argument", "No valid fields to update.");
    }
    if (typeof patch.timezone === "string")
        validateTimezone(patch.timezone);
    const uid = request.auth.uid;
    // ✅ membership check (authoritative clinic scope only)
    const memberData = await getAuthoritativeMembership(clinicId, uid);
    if (!memberData) {
        throw new https_1.HttpsError("permission-denied", "Missing membership.");
    }
    if (!isActiveMember(memberData)) {
        throw new https_1.HttpsError("permission-denied", "Inactive membership.");
    }
    if (!hasSettingsWrite(memberData)) {
        throw new https_1.HttpsError("permission-denied", "Missing settings.write permission.");
    }
    const clinicRef = db.doc(`clinics/${clinicId}`);
    const clinicSnap = await clinicRef.get();
    if (!clinicSnap.exists) {
        throw new https_1.HttpsError("not-found", "Clinic not found.");
    }
    const now = FV.serverTimestamp();
    // Build update payload
    const updateData = {
        updatedAt: now,
        // keep profile audit trail
        "profile.updatedAt": now,
        "profile.updatedBy": uid,
    };
    // ✅ Write BOTH root keys and profile keys (so older clients still work)
    setOrDelete(updateData, "name", patch.name);
    setOrDelete(updateData, "phone", patch.phone);
    setOrDelete(updateData, "email", patch.email);
    setOrDelete(updateData, "timezone", patch.timezone);
    setOrDelete(updateData, "address", patch.address);
    setOrDelete(updateData, "logoUrl", patch.logoUrl);
    setOrDelete(updateData, "defaultLanguage", patch.defaultLanguage);
    setOrDelete(updateData, "landingUrl", patch.landingUrl);
    setOrDelete(updateData, "websiteUrl", patch.websiteUrl);
    setOrDelete(updateData, "whatsapp", patch.whatsapp);
    setOrDelete(updateData, "profile.name", patch.name);
    setOrDelete(updateData, "profile.phone", patch.phone);
    setOrDelete(updateData, "profile.email", patch.email);
    setOrDelete(updateData, "profile.timezone", patch.timezone);
    setOrDelete(updateData, "profile.address", patch.address);
    setOrDelete(updateData, "profile.logoUrl", patch.logoUrl);
    setOrDelete(updateData, "profile.defaultLanguage", patch.defaultLanguage);
    setOrDelete(updateData, "profile.landingUrl", patch.landingUrl);
    setOrDelete(updateData, "profile.websiteUrl", patch.websiteUrl);
    setOrDelete(updateData, "profile.whatsapp", patch.whatsapp);
    // Audit
    const auditRef = db.collection(`clinics/${clinicId}/audit`).doc();
    // ✅ Public config mirror doc (public readable)
    const publicConfigRef = db.doc(`clinics/${clinicId}/public/config/publicBooking/publicBooking`);
    // Compute “post-update” values for mirroring using existing clinic data + patch.
    const existing = clinicSnap.data() || {};
    const existingProfile = existing.profile && typeof existing.profile === "object" ? existing.profile : {};
    const currentVal = (key) => { var _a, _b; return (_b = (_a = existing[key]) !== null && _a !== void 0 ? _a : existingProfile[key]) !== null && _b !== void 0 ? _b : null; };
    const applyPatch = (key) => {
        const v = patch[key];
        if (v === undefined)
            return currentVal(key);
        return v; // string or null
    };
    const nextClinicName = applyPatch("name");
    const nextLogoUrl = applyPatch("logoUrl");
    const nextEmail = applyPatch("email");
    const nextPhone = applyPatch("phone");
    const nextLandingUrl = applyPatch("landingUrl");
    const nextWebsiteUrl = applyPatch("websiteUrl");
    const nextWhatsapp = applyPatch("whatsapp");
    const changedFields = Object.entries(patch)
        .filter(([, v]) => v !== undefined)
        .map(([k]) => k);
    await db.runTransaction(async (tx) => {
        tx.update(clinicRef, updateData);
        tx.set(publicConfigRef, {
            clinicId,
            clinicName: typeof nextClinicName === "string" ? nextClinicName : null,
            logoUrl: typeof nextLogoUrl === "string" ? nextLogoUrl : null,
            landingUrl: typeof nextLandingUrl === "string" ? nextLandingUrl : null,
            websiteUrl: typeof nextWebsiteUrl === "string" ? nextWebsiteUrl : null,
            whatsapp: typeof nextWhatsapp === "string" ? nextWhatsapp : null,
            email: typeof nextEmail === "string" ? nextEmail : null,
            phone: typeof nextPhone === "string" ? nextPhone : null,
        }, { merge: true });
        tx.set(auditRef, {
            schemaVersion: 2,
            type: "clinic.settings.profile_updated",
            clinicId,
            actor: { uid },
            at: now,
            fields: changedFields,
        });
    });
    return { ok: true };
}
//# sourceMappingURL=updateClinicProfile.js.map