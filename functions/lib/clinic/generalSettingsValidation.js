"use strict";
/**
 * Validation helpers for clinic general settings (updateClinicProfile).
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.validateTimezone = validateTimezone;
exports.validateEmail = validateEmail;
exports.validateSessionTimeoutMinutes = validateSessionTimeoutMinutes;
exports.looksLikeUrl = looksLikeUrl;
const https_1 = require("firebase-functions/v2/https");
/**
 * Validate IANA-style timezone. Throws if invalid; otherwise no-op.
 * Accepts common forms (e.g. Europe/London, UTC, America/New_York).
 */
function validateTimezone(tz) {
    if (typeof tz !== "string" || tz.trim().length === 0) {
        throw new https_1.HttpsError("invalid-argument", "Timezone must be a non-empty string.");
    }
    if (tz.length > 64) {
        throw new https_1.HttpsError("invalid-argument", "Timezone must be at most 64 characters.");
    }
    // Basic sanity: allow letters, digits, /, _, +, -
    if (!/^[A-Za-z0-9/_+\-]+$/.test(tz.trim())) {
        throw new https_1.HttpsError("invalid-argument", "Timezone contains invalid characters.");
    }
}
/**
 * Simple email format check. Returns true if format looks valid.
 */
function validateEmail(email) {
    if (typeof email !== "string")
        return false;
    const s = email.trim();
    if (s.length === 0 || s.length > 254)
        return false;
    // RFC 5322 simplified
    const local = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return local.test(s);
}
/**
 * Validate session timeout minutes. Throws if invalid; null means use default/no limit.
 */
function validateSessionTimeoutMinutes(n) {
    if (n === null || n === undefined)
        return;
    if (typeof n !== "number" || !Number.isFinite(n)) {
        throw new https_1.HttpsError("invalid-argument", "Session timeout must be a number.");
    }
    if (n < 5 || n > 10080) {
        throw new https_1.HttpsError("invalid-argument", "Session timeout must be between 5 and 10080 minutes (1 week).");
    }
}
/**
 * Returns true if string looks like a valid URL (http/https or has a dot for domain).
 * Used for landingUrl, websiteUrl.
 */
function looksLikeUrl(s) {
    const t = s.trim();
    if (t.length === 0)
        return true;
    const lower = t.toLowerCase();
    if (lower.startsWith("http://") || lower.startsWith("https://"))
        return true;
    if (t.includes(" ") || t.length > 2048)
        return false;
    return t.includes(".");
}
//# sourceMappingURL=generalSettingsValidation.js.map