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
// ─────────────────────────────
// Helpers
// ─────────────────────────────
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
    if (p && typeof p === "object" && !Array.isArray(p))
        return p;
    return {};
}
/**
 * Canonical-first membership lookup:
 *   1) clinics/{clinicId}/members/{uid}
 *   2) clinics/{clinicId}/memberships/{uid} (legacy)
 */
async function getMembershipWithFallback(params) {
    var _a, _b;
    const canon = await db
        .collection("clinics")
        .doc(params.clinicId)
        .collection("members")
        .doc(params.uid)
        .get();
    if (canon.exists)
        return (_a = canon.data()) !== null && _a !== void 0 ? _a : {};
    const legacy = await db
        .collection("clinics")
        .doc(params.clinicId)
        .collection("memberships")
        .doc(params.uid)
        .get();
    if (legacy.exists)
        return (_b = legacy.data()) !== null && _b !== void 0 ? _b : {};
    return null;
}
function ensurePlainObject(v, label) {
    if (!v || typeof v !== "object" || Array.isArray(v)) {
        throw new https_1.HttpsError("invalid-argument", `${label} must be an object.`);
    }
    return v;
}
/**
 * Allowlist-only staff profile patch.
 * 🚫 Availability / hours are EXPLICITLY forbidden here.
 */
function sanitizeStaffProfilePatch(raw) {
    const patch = ensurePlainObject(raw, "patch");
    // 🚫 HARD BLOCK availability-related keys
    const forbiddenKeys = [
        "availability",
        "weekly",
        "openingHours",
        "hours",
        "workingHours",
    ];
    for (const k of forbiddenKeys) {
        if (k in patch) {
            throw new https_1.HttpsError("invalid-argument", `Field "${k}" is not allowed in staff profile updates. ` +
                `Use setStaffAvailabilityDefaultFn instead.`);
        }
    }
    const out = {};
    // schema version (optional)
    out.schemaVersion =
        Number.isFinite(Number(patch.schemaVersion))
            ? Number(patch.schemaVersion)
            : 1;
    if ("displayName" in patch)
        out.displayName = safeStr(patch.displayName).slice(0, 120);
    if ("firstName" in patch)
        out.firstName = safeStr(patch.firstName).slice(0, 80);
    if ("lastName" in patch)
        out.lastName = safeStr(patch.lastName).slice(0, 80);
    if ("title" in patch)
        out.title = safeStr(patch.title).slice(0, 120);
    if ("notes" in patch)
        out.notes = safeStr(patch.notes).slice(0, 8000);
    if ("photo" in patch && typeof patch.photo === "object") {
        out.photo = {
            storagePath: safeStr(patch.photo.storagePath).slice(0, 300),
            url: safeStr(patch.photo.url).slice(0, 500),
        };
    }
    if ("professional" in patch && typeof patch.professional === "object") {
        out.professional = patch.professional;
    }
    return out;
}
// ─────────────────────────────
// Callable
// ─────────────────────────────
async function upsertStaffProfile(req) {
    var _a, _b, _c, _d;
    if (!req.auth) {
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    }
    const clinicId = safeStr((_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId);
    const targetUid = safeStr((_b = req.data) === null || _b === void 0 ? void 0 : _b.uid);
    const actorUid = req.auth.uid;
    if (!clinicId || !targetUid) {
        throw new https_1.HttpsError("invalid-argument", "clinicId and uid are required.");
    }
    // ── Authorize actor
    const actorMembership = await getMembershipWithFallback({
        clinicId,
        uid: actorUid,
    });
    if (!actorMembership || !isMemberActiveLike(actorMembership)) {
        throw new https_1.HttpsError("permission-denied", "Not permitted.");
    }
    const perms = getPermissionsMap(actorMembership);
    if (perms["members.manage"] !== true) {
        throw new https_1.HttpsError("permission-denied", "Insufficient permissions.");
    }
    // ── Ensure target exists in clinic
    const targetMembership = await getMembershipWithFallback({
        clinicId,
        uid: targetUid,
    });
    if (!targetMembership) {
        throw new https_1.HttpsError("not-found", "Target staff member not in clinic.");
    }
    // ── Sanitize patch
    const patch = sanitizeStaffProfilePatch((_d = (_c = req.data) === null || _c === void 0 ? void 0 : _c.patch) !== null && _d !== void 0 ? _d : {});
    const ref = db
        .collection("clinics")
        .doc(clinicId)
        .collection("staffProfiles")
        .doc(targetUid);
    const snap = await ref.get();
    const now = admin.firestore.FieldValue.serverTimestamp();
    await ref.set({
        ...patch,
        updatedAt: now,
        updatedByUid: actorUid,
        ...(snap.exists
            ? {}
            : { createdAt: now, createdByUid: actorUid }),
    }, { merge: true } // ✅ SAFE: profile-only, never availability
    );
    logger_1.logger.info("upsertStaffProfile: ok", {
        clinicId,
        actorUid,
        targetUid,
        keys: Object.keys(patch),
    });
    return { ok: true, uid: targetUid };
}
//# sourceMappingURL=upsertStaffProfile.js.map