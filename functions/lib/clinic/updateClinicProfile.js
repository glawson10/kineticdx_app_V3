"use strict";
/**
 * Commit 4 + 5: settings.updateClinicProfile
 * - Auth → membership → settings.write → validate → write profile.* only.
 * - Root mirror: only name and timezone (minimal legacy compat).
 * - Public projection: not here; use event-driven onWrite/trigger for public mirror (see OPENING_HOURS_CONTRACT).
 * - Audit: settings.clinic.updated with changes (canonical keys profile.*).
 */
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
const audit_1 = require("./audit/audit");
const generalSettingsValidation_1 = require("./generalSettingsValidation");
const mirrorPublicBooking_1 = require("../public/mirrorPublicBooking");
const db = admin.firestore();
const FV = admin.firestore.FieldValue;
function isNonEmptyString(v) {
    return typeof v === "string" && v.trim().length > 0;
}
function trimStr(v, maxLen) {
    const s = v.trim();
    return s.length > maxLen ? s.slice(0, maxLen) : s;
}
/** Admin contact completeness: if any is set, all three must be valid (email valid, first+last non-empty). */
function validateAdminContact(patch) {
    const first = patch.adminContactFirstName;
    const last = patch.adminContactLastName;
    const email = patch.adminContactEmail;
    const hasFirst = typeof first === "string" && first.trim().length > 0;
    const hasLast = typeof last === "string" && last.trim().length > 0;
    const hasEmail = typeof email === "string" && email.trim().length > 0;
    if (!hasFirst && !hasLast && !hasEmail)
        return;
    if (!hasFirst || !hasLast) {
        throw new https_1.HttpsError("invalid-argument", "If any admin contact field is set, first name, last name and email are all required.");
    }
    if (!hasEmail || !(0, generalSettingsValidation_1.validateEmail)(email.trim().toLowerCase())) {
        throw new https_1.HttpsError("invalid-argument", "Admin contact email must be a valid email address when admin contact is provided.");
    }
    if (email.trim().length > 254) {
        throw new https_1.HttpsError("invalid-argument", "Admin contact email must be at most 254 characters.");
    }
}
/** Normalize and validate patch; returns only keys that were provided (undefined = not in patch). */
function cleanAndValidatePatch(input) {
    const raw = input && typeof input === "object" ? input : {};
    const patch = {};
    if (raw.hasOwnProperty("name")) {
        const v = raw.name;
        if (v === null)
            patch.name = null;
        else if (typeof v === "string") {
            const s = trimStr(v, 80);
            if (s.length < 2) {
                throw new https_1.HttpsError("invalid-argument", "Clinic name must be at least 2 characters.");
            }
            if (/^\s*$/.test(v)) {
                throw new https_1.HttpsError("invalid-argument", "Clinic name cannot be only whitespace.");
            }
            patch.name = s;
        }
    }
    if (raw.hasOwnProperty("adminContactFirstName")) {
        const v = raw.adminContactFirstName;
        if (v === null)
            patch.adminContactFirstName = null;
        else if (typeof v === "string")
            patch.adminContactFirstName = trimStr(v, 50);
    }
    if (raw.hasOwnProperty("adminContactLastName")) {
        const v = raw.adminContactLastName;
        if (v === null)
            patch.adminContactLastName = null;
        else if (typeof v === "string")
            patch.adminContactLastName = trimStr(v, 50);
    }
    if (raw.hasOwnProperty("adminContactEmail")) {
        const v = raw.adminContactEmail;
        if (v === null)
            patch.adminContactEmail = null;
        else if (typeof v === "string") {
            const s = v.trim().toLowerCase();
            if (s.length > 0 && !(0, generalSettingsValidation_1.validateEmail)(s)) {
                throw new https_1.HttpsError("invalid-argument", "Admin contact email must be a valid email address.");
            }
            patch.adminContactEmail = s.length > 254 ? s.slice(0, 254) : s;
        }
    }
    if (raw.hasOwnProperty("country")) {
        const v = raw.country;
        if (v === null)
            patch.country = null;
        else if (typeof v === "string") {
            const s = v.trim().toUpperCase();
            if (s.length > 0) {
                if (s.length !== 2 || !/^[A-Z]{2}$/.test(s)) {
                    throw new https_1.HttpsError("invalid-argument", "Country must be ISO 3166-1 alpha-2 (2 letters).");
                }
                patch.country = s;
            }
            else
                patch.country = null;
        }
    }
    if (raw.hasOwnProperty("timezone")) {
        const v = raw.timezone;
        if (v === null)
            patch.timezone = null;
        else if (typeof v === "string") {
            const s = v.trim();
            if (s.length > 0) {
                (0, generalSettingsValidation_1.validateTimezone)(s);
                patch.timezone = s.length > 64 ? s.slice(0, 64) : s;
            }
            else
                patch.timezone = null;
        }
    }
    if (raw.hasOwnProperty("currency")) {
        const v = raw.currency;
        if (v === null)
            patch.currency = null;
        else if (typeof v === "string") {
            const s = v.trim().toUpperCase();
            if (s.length > 0) {
                if (s.length !== 3 || !/^[A-Z]{3}$/.test(s)) {
                    throw new https_1.HttpsError("invalid-argument", "Currency must be ISO 4217 alpha-3 (3 letters).");
                }
                patch.currency = s;
            }
            else
                patch.currency = null;
        }
    }
    if (raw.hasOwnProperty("terminology")) {
        const v = raw.terminology;
        if (v === null)
            patch.terminology = null;
        else if (typeof v === "string") {
            const s = v.trim().toLowerCase();
            if (s.length > 0) {
                if (s !== "patient" && s !== "client") {
                    throw new https_1.HttpsError("invalid-argument", "Terminology must be 'patient' or 'client'.");
                }
                patch.terminology = s;
            }
            else
                patch.terminology = null;
        }
    }
    if (raw.hasOwnProperty("replyToEmail")) {
        const v = raw.replyToEmail;
        if (v === null)
            patch.replyToEmail = null;
        else if (typeof v === "string") {
            const s = v.trim().toLowerCase();
            if (s.length > 0) {
                if (!(0, generalSettingsValidation_1.validateEmail)(s) || s.length > 254) {
                    throw new https_1.HttpsError("invalid-argument", "Reply-to email must be a valid email (max 254 chars).");
                }
                patch.replyToEmail = s;
            }
            else
                patch.replyToEmail = null;
        }
    }
    if (raw.hasOwnProperty("sessionTimeoutMinutes")) {
        const v = raw.sessionTimeoutMinutes;
        if (v === null || v === undefined)
            patch.sessionTimeoutMinutes = null;
        else {
            const n = Number(v);
            if (!Number.isInteger(n) || n < 0) {
                throw new https_1.HttpsError("invalid-argument", "sessionTimeoutMinutes must be a non-negative integer.");
            }
            (0, generalSettingsValidation_1.validateSessionTimeoutMinutes)(n === 0 ? null : n);
            patch.sessionTimeoutMinutes = n === 0 ? null : n;
        }
    }
    if (raw.hasOwnProperty("require2FA")) {
        const v = raw.require2FA;
        if (v === null || v === undefined)
            patch.require2FA = null;
        else if (typeof v === "boolean")
            patch.require2FA = v;
        else
            throw new https_1.HttpsError("invalid-argument", "require2FA must be a boolean.");
    }
    // Branding and public contact (profile.*; logoUrl also mirrored to root for public mirror)
    if (raw.hasOwnProperty("logoUrl")) {
        const v = raw.logoUrl;
        if (v === null)
            patch.logoUrl = null;
        else if (typeof v === "string")
            patch.logoUrl = trimStr(v, 2048) || null;
    }
    if (raw.hasOwnProperty("address")) {
        const v = raw.address;
        if (v === null)
            patch.address = null;
        else if (typeof v === "string")
            patch.address = trimStr(v, 1024) || null;
    }
    if (raw.hasOwnProperty("phone")) {
        const v = raw.phone;
        if (v === null)
            patch.phone = null;
        else if (typeof v === "string")
            patch.phone = trimStr(v, 64) || null;
    }
    if (raw.hasOwnProperty("email")) {
        const v = raw.email;
        if (v === null)
            patch.email = null;
        else if (typeof v === "string") {
            const s = v.trim();
            if (s.length > 0) {
                if (!(0, generalSettingsValidation_1.validateEmail)(s.toLowerCase()) || s.length > 254) {
                    throw new https_1.HttpsError("invalid-argument", "Email must be a valid email address (max 254 chars).");
                }
                patch.email = s.toLowerCase();
            }
            else
                patch.email = null;
        }
    }
    if (raw.hasOwnProperty("landingUrl")) {
        const v = raw.landingUrl;
        if (v === null)
            patch.landingUrl = null;
        else if (typeof v === "string") {
            const s = trimStr(v, 2048);
            if (s.length > 0 && !(0, generalSettingsValidation_1.looksLikeUrl)(s)) {
                throw new https_1.HttpsError("invalid-argument", "Landing page URL must be a valid URL.");
            }
            patch.landingUrl = s || null;
        }
    }
    if (raw.hasOwnProperty("websiteUrl")) {
        const v = raw.websiteUrl;
        if (v === null)
            patch.websiteUrl = null;
        else if (typeof v === "string") {
            const s = trimStr(v, 2048);
            if (s.length > 0 && !(0, generalSettingsValidation_1.looksLikeUrl)(s)) {
                throw new https_1.HttpsError("invalid-argument", "Website URL must be a valid URL.");
            }
            patch.websiteUrl = s || null;
        }
    }
    if (raw.hasOwnProperty("whatsapp")) {
        const v = raw.whatsapp;
        if (v === null)
            patch.whatsapp = null;
        else if (typeof v === "string")
            patch.whatsapp = trimStr(v, 256) || null;
    }
    if (raw.hasOwnProperty("defaultLanguage")) {
        const v = raw.defaultLanguage;
        if (v === null)
            patch.defaultLanguage = null;
        else if (typeof v === "string")
            patch.defaultLanguage = trimStr(v, 16) || null;
    }
    if ((raw === null || raw === void 0 ? void 0 : raw._testAudit) === true)
        patch._testAudit = true;
    validateAdminContact(patch);
    return patch;
}
async function getAuthoritativeMembership(clinicId, uid) {
    var _a, _b;
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
    if (!("active" in data))
        return true;
    return data.active === true;
}
function hasSettingsWrite(data) {
    const perms = data.permissions;
    return !!(perms && typeof perms === "object" && perms["settings.write"] === true);
}
function anyMeaningfulKeys(patch) {
    return Object.entries(patch).some(([k, v]) => v !== undefined && k !== "_testAudit");
}
function isTestAuditOnly(patch) {
    return (patch._testAudit === true &&
        Object.entries(patch).every(([k, v]) => k === "_testAudit" || v === undefined));
}
/** Write profile.* only. Mirror to root only for legacy keys: name, timezone (minimal root mirroring). */
const ROOT_MIRROR_KEYS = new Set(["name", "timezone"]);
function applyProfileUpdate(updateData, profileKey, value) {
    if (value === undefined)
        return;
    const profileDot = `profile.${profileKey}`;
    if (value === null) {
        updateData[profileDot] = FV.delete();
        if (ROOT_MIRROR_KEYS.has(profileKey))
            updateData[profileKey] = FV.delete();
    }
    else {
        updateData[profileDot] = value;
        if (ROOT_MIRROR_KEYS.has(profileKey))
            updateData[profileKey] = value;
    }
}
/** Write profile.* only (no root mirror). Used for sessionTimeoutMinutes, require2FA. */
function applyProfileOnly(updateData, profileKey, value) {
    if (value === undefined)
        return;
    const profileDot = `profile.${profileKey}`;
    if (value === null) {
        updateData[profileDot] = FV.delete();
    }
    else {
        updateData[profileDot] = value;
    }
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
    let patch;
    try {
        patch = cleanAndValidatePatch((_c = request.data) === null || _c === void 0 ? void 0 : _c.patch);
    }
    catch (e) {
        if (e instanceof https_1.HttpsError)
            throw e;
        throw new https_1.HttpsError("invalid-argument", e instanceof Error ? e.message : "Invalid patch.");
    }
    const testAuditOnly = isTestAuditOnly(patch);
    if (!testAuditOnly && !anyMeaningfulKeys(patch)) {
        throw new https_1.HttpsError("invalid-argument", "No valid fields to update.");
    }
    const uid = request.auth.uid;
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
    if (testAuditOnly) {
        await (0, audit_1.writeSettingsAuditEvent)(db, clinicId, "settings.clinic.updated", uid, `clinics/${clinicId}`, clinicId, {});
        return { ok: true };
    }
    const updateData = {
        updatedAt: now,
        "profile.updatedAt": now,
        "profile.updatedBy": uid,
    };
    applyProfileUpdate(updateData, "name", patch.name);
    applyProfileUpdate(updateData, "adminContactFirstName", patch.adminContactFirstName);
    applyProfileUpdate(updateData, "adminContactLastName", patch.adminContactLastName);
    applyProfileUpdate(updateData, "adminContactEmail", patch.adminContactEmail);
    applyProfileUpdate(updateData, "country", patch.country);
    applyProfileUpdate(updateData, "timezone", patch.timezone);
    applyProfileUpdate(updateData, "currency", patch.currency);
    applyProfileUpdate(updateData, "terminology", patch.terminology);
    applyProfileUpdate(updateData, "replyToEmail", patch.replyToEmail);
    applyProfileUpdate(updateData, "logoUrl", patch.logoUrl);
    applyProfileUpdate(updateData, "address", patch.address);
    applyProfileUpdate(updateData, "phone", patch.phone);
    applyProfileUpdate(updateData, "email", patch.email);
    applyProfileUpdate(updateData, "landingUrl", patch.landingUrl);
    applyProfileUpdate(updateData, "websiteUrl", patch.websiteUrl);
    applyProfileUpdate(updateData, "whatsapp", patch.whatsapp);
    applyProfileUpdate(updateData, "defaultLanguage", patch.defaultLanguage);
    if (patch.sessionTimeoutMinutes !== undefined) {
        applyProfileOnly(updateData, "sessionTimeoutMinutes", patch.sessionTimeoutMinutes === null || patch.sessionTimeoutMinutes === 0 ? null : patch.sessionTimeoutMinutes);
    }
    if (patch.require2FA !== undefined) {
        applyProfileOnly(updateData, "require2FA", patch.require2FA === null ? null : patch.require2FA);
    }
    const changedFields = Object.entries(patch)
        .filter(([k, v]) => v !== undefined && k !== "_testAudit")
        .map(([k]) => k);
    const auditChanges = {};
    for (const key of changedFields) {
        const v = patch[key];
        const canonicalKey = `profile.${key}`;
        auditChanges[canonicalKey] = v === null ? null : v;
    }
    const auditRef = db.collection(`clinics/${clinicId}/audit`).doc();
    await db.runTransaction(async (tx) => {
        tx.update(clinicRef, updateData);
        tx.set(auditRef, {
            clinicId,
            eventType: "settings.clinic.updated",
            actorUserId: uid,
            entityPath: `clinics/${clinicId}`,
            entityId: clinicId,
            changes: auditChanges,
            createdAt: now,
        });
    });
    // Refresh public booking mirror so public portal shows updated contact and logo.
    await (0, mirrorPublicBooking_1.runPublicBookingMirrorForClinic)(clinicId);
    return { ok: true };
}
//# sourceMappingURL=updateClinicProfile.js.map