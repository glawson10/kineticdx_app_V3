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
exports.upsertPractitionerBookingMeta = upsertPractitionerBookingMeta;
// functions/src/clinic/staff/upsertPractitionerBookingMeta.ts
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const logger_1 = require("firebase-functions/logger");
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
}
function isMemberActiveLike(data) {
    const status = safeStr(data.status);
    if (status === "suspended")
        return false;
    if (status === "invited")
        return false;
    const active = data.active;
    if (active === true)
        return true;
    if (active === false)
        return false;
    return true;
}
function getPermissionsMap(data) {
    const p = data.permissions;
    if (p && typeof p === "object" && !Array.isArray(p))
        return p;
    return {};
}
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
function sanitizeBookingMetaPatch(raw) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
        throw new https_1.HttpsError("invalid-argument", "patch must be an object.");
    }
    const out = {};
    if ("activeForBooking" in raw) {
        out.activeForBooking = raw.activeForBooking === true;
    }
    if ("showInPublicBooking" in raw) {
        out.showInPublicBooking = raw.showInPublicBooking === true;
    }
    if ("publicSortOrder" in raw) {
        const n = Number(raw.publicSortOrder);
        out.sortOrder = Number.isFinite(n) ? Math.max(0, Math.round(n)) : 0;
    }
    if ("allowedLocationIds" in raw) {
        if (Array.isArray(raw.allowedLocationIds)) {
            out.allowedLocationIds = raw.allowedLocationIds
                .map((x) => safeStr(x))
                .filter((x) => x.length > 0)
                .slice(0, 50);
        }
        else {
            out.allowedLocationIds = [];
        }
    }
    if ("serviceIdsAllowed" in raw) {
        if (Array.isArray(raw.serviceIdsAllowed)) {
            out.serviceIdsAllowed = raw.serviceIdsAllowed
                .map((x) => safeStr(x))
                .filter((x) => x.length > 0)
                .slice(0, 100);
        }
        else {
            out.serviceIdsAllowed = [];
        }
    }
    if ("displayName" in raw) {
        out.displayName = safeStr(raw.displayName).slice(0, 200);
    }
    return out;
}
async function upsertPractitionerBookingMeta(req) {
    var _a, _b, _c, _d, _e;
    if (!req.auth) {
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    }
    const clinicId = safeStr((_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId);
    const targetUid = safeStr((_b = req.data) === null || _b === void 0 ? void 0 : _b.uid);
    const actorUid = req.auth.uid;
    if (!clinicId || !targetUid) {
        throw new https_1.HttpsError("invalid-argument", "clinicId and uid are required.");
    }
    const actorMembership = await getMembershipWithFallback({
        clinicId,
        uid: actorUid,
    });
    if (!actorMembership || !isMemberActiveLike(actorMembership)) {
        throw new https_1.HttpsError("permission-denied", "Not permitted.");
    }
    const perms = getPermissionsMap(actorMembership);
    if (perms["members.manage"] !== true) {
        throw new https_1.HttpsError("permission-denied", "Only clinic managers can change booking metadata.");
    }
    const targetMembership = await getMembershipWithFallback({
        clinicId,
        uid: targetUid,
    });
    if (!targetMembership) {
        throw new https_1.HttpsError("not-found", "Target member not found in clinic.");
    }
    const patch = sanitizeBookingMetaPatch((_d = (_c = req.data) === null || _c === void 0 ? void 0 : _c.patch) !== null && _d !== void 0 ? _d : {});
    if (Object.keys(patch).length === 0) {
        return { ok: true, noop: true };
    }
    // Ensure displayName is populated if not in patch
    if (!("displayName" in patch)) {
        const existingPrac = await db
            .doc(`clinics/${clinicId}/practitioners/${targetUid}`)
            .get();
        if (!existingPrac.exists) {
            patch.displayName =
                safeStr(targetMembership.displayName) ||
                    safeStr(targetMembership.name) ||
                    safeStr(targetMembership.invitedEmail) ||
                    "Practitioner";
        }
    }
    // Sync active from membership
    patch.active = isMemberActiveLike(targetMembership);
    const ref = db.doc(`clinics/${clinicId}/practitioners/${targetUid}`);
    const now = admin.firestore.FieldValue.serverTimestamp();
    const snap = await ref.get();
    try {
        await ref.set({
            ...patch,
            updatedAt: now,
            updatedByUid: actorUid,
            ...(snap.exists ? {} : { createdAt: now, createdByUid: actorUid }),
        }, { merge: true });
    }
    catch (err) {
        const msg = (_e = err === null || err === void 0 ? void 0 : err.message) !== null && _e !== void 0 ? _e : String(err);
        logger_1.logger.error("upsertPractitionerBookingMeta: write failed", { clinicId, targetUid, err: msg });
        throw new https_1.HttpsError("internal", `Failed to update booking metadata: ${msg}`);
    }
    logger_1.logger.info("upsertPractitionerBookingMeta: success", {
        clinicId,
        targetUid,
        actorUid,
        patchKeys: Object.keys(patch),
    });
    return { ok: true };
}
//# sourceMappingURL=upsertPractitionerBookingMeta.js.map