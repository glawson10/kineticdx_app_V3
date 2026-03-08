"use strict";
/**
 * Shared validators for settings callables (Commit 19+).
 * Used by upsertLocation, upsertPractitionerAvailability, upsertPractitionerOverride, deletePractitionerOverride.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.assertString = assertString;
exports.requireNonEmptyString = requireNonEmptyString;
exports.assertBoolean = assertBoolean;
exports.assertHexColor = assertHexColor;
exports.pickAllowedFields = pickAllowedFields;
exports.assertIntRange = assertIntRange;
const https_1 = require("firebase-functions/v2/https");
/**
 * Assert or coerce a string. Returns trimmed string or null if value is null/undefined/empty and not required.
 */
function assertString(val, field, opts = {}) {
    const { required = false, trim = false, minLength, maxLength } = opts;
    if (val === null || val === undefined) {
        if (required)
            throw new https_1.HttpsError("invalid-argument", `Missing required field: ${field}`);
        return null;
    }
    const s = typeof val === "string" ? val : String(val);
    const out = trim ? s.trim() : s;
    if (out.length === 0) {
        if (required)
            throw new https_1.HttpsError("invalid-argument", `Missing required field: ${field}`);
        return null;
    }
    if (minLength != null && out.length < minLength) {
        throw new https_1.HttpsError("invalid-argument", `${field} must be at least ${minLength} characters.`);
    }
    if (maxLength != null && out.length > maxLength) {
        throw new https_1.HttpsError("invalid-argument", `${field} must be at most ${maxLength} characters.`);
    }
    return out;
}
/**
 * Throws if val is not a non-empty string. Use for required IDs etc.
 */
function requireNonEmptyString(val, field) {
    const s = assertString(val, field, { required: true, trim: true });
    if (!s || s.length === 0)
        throw new https_1.HttpsError("invalid-argument", `Missing required field: ${field}`);
    return s;
}
/**
 * Assert boolean. Returns true/false or null if not provided.
 */
function assertBoolean(val, field) {
    if (val === null || val === undefined)
        return null;
    if (typeof val === "boolean")
        return val;
    if (val === "true" || val === 1)
        return true;
    if (val === "false" || val === 0)
        return false;
    throw new https_1.HttpsError("invalid-argument", `${field} must be a boolean.`);
}
const HEX_COLOR = /^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6})$/;
/**
 * Assert hex color (#RGB or #RRGGBB). Returns the string or null if not provided.
 */
function assertHexColor(val, field) {
    if (val === null || val === undefined)
        return null;
    const s = typeof val === "string" ? val.trim() : String(val).trim();
    if (s.length === 0)
        return null;
    if (!HEX_COLOR.test(s)) {
        throw new https_1.HttpsError("invalid-argument", `${field} must be a hex color (#RGB or #RRGGBB).`);
    }
    return s;
}
/**
 * Pick only allowed keys from patch. Used to enforce server whitelist.
 */
function pickAllowedFields(patch, allowedKeys) {
    if (patch == null || typeof patch !== "object")
        return {};
    const raw = patch;
    const out = {};
    for (const k of Object.keys(raw)) {
        if (allowedKeys.has(k))
            out[k] = raw[k];
    }
    return out;
}
/**
 * Assert integer in range. Returns the number or null if not provided and not required.
 */
function assertIntRange(val, field, opts) {
    const { min, max, required = false } = opts;
    if (val === null || val === undefined) {
        if (required)
            throw new https_1.HttpsError("invalid-argument", `Missing required field: ${field}`);
        return null;
    }
    const n = typeof val === "number" ? val : parseInt(String(val), 10);
    if (!Number.isFinite(n) || Math.floor(n) !== n) {
        throw new https_1.HttpsError("invalid-argument", `${field} must be an integer.`);
    }
    if (n < min || n > max) {
        throw new https_1.HttpsError("invalid-argument", `${field} must be between ${min} and ${max}.`);
    }
    return n;
}
//# sourceMappingURL=validators.js.map