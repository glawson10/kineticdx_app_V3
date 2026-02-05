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
exports.setStaffAvailabilityDefault = setStaffAvailabilityDefault;
// functions/src/clinic/staff/setStaffAvailabilityDefault.ts
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
    if (p && typeof p === "object" && !Array.isArray(p))
        return p;
    return {};
}
async function getMembershipWithFallback(params) {
    var _a, _b;
    const canonical = await db
        .doc(`clinics/${params.clinicId}/members/${params.uid}`)
        .get();
    if (canonical.exists)
        return (_a = canonical.data()) !== null && _a !== void 0 ? _a : {};
    const legacy = await db
        .doc(`clinics/${params.clinicId}/memberships/${params.uid}`)
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
const DAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
function parseHHMM(s) {
    const m = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(safeStr(s));
    if (!m) {
        throw new https_1.HttpsError("invalid-argument", `Invalid time "${s}" (HH:mm).`);
    }
    return Number(m[1]) * 60 + Number(m[2]);
}
function validateIntervals(day, arr) {
    if (!Array.isArray(arr)) {
        throw new https_1.HttpsError("invalid-argument", `weekly.${day} must be an array.`);
    }
    const out = [];
    for (let i = 0; i < arr.length; i++) {
        const it = arr[i];
        const start = safeStr(it === null || it === void 0 ? void 0 : it.start);
        const end = safeStr(it === null || it === void 0 ? void 0 : it.end);
        if (!start || !end) {
            throw new https_1.HttpsError("invalid-argument", `weekly.${day}[${i}] requires start and end`);
        }
        const s = parseHHMM(start);
        const e = parseHHMM(end);
        if (e <= s) {
            throw new https_1.HttpsError("invalid-argument", `weekly.${day}[${i}] end must be after start`);
        }
        out.push({ start, end });
    }
    // overlap check
    const mins = out
        .map((x) => ({ s: parseHHMM(x.start), e: parseHHMM(x.end) }))
        .sort((a, b) => a.s - b.s);
    for (let i = 1; i < mins.length; i++) {
        if (mins[i].s < mins[i - 1].e) {
            throw new https_1.HttpsError("invalid-argument", `weekly.${day} has overlapping intervals`);
        }
    }
    return out;
}
function sanitizeWeekly(raw) {
    var _a;
    const obj = ensurePlainObject(raw, "weekly");
    const out = {};
    for (const d of DAYS) {
        out[d] = validateIntervals(d, (_a = obj[d]) !== null && _a !== void 0 ? _a : []);
    }
    return out;
}
async function setStaffAvailabilityDefault(req) {
    var _a, _b, _c, _d;
    if (!req.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const clinicId = safeStr((_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId);
    const targetUid = safeStr((_b = req.data) === null || _b === void 0 ? void 0 : _b.uid);
    const timezone = safeStr((_c = req.data) === null || _c === void 0 ? void 0 : _c.timezone);
    if (!clinicId || !targetUid || !timezone) {
        throw new https_1.HttpsError("invalid-argument", "Missing required fields.");
    }
    const actorUid = req.auth.uid;
    const actorMembership = await getMembershipWithFallback({
        clinicId,
        uid: actorUid,
    });
    if (!actorMembership || !isMemberActiveLike(actorMembership)) {
        throw new https_1.HttpsError("permission-denied", "Not allowed.");
    }
    const perms = getPermissionsMap(actorMembership);
    if (perms["members.manage"] !== true) {
        throw new https_1.HttpsError("permission-denied", "Insufficient permissions.");
    }
    const targetMembership = await getMembershipWithFallback({
        clinicId,
        uid: targetUid,
    });
    if (!targetMembership) {
        throw new https_1.HttpsError("not-found", "Target staff not in clinic.");
    }
    const weekly = sanitizeWeekly((_d = req.data) === null || _d === void 0 ? void 0 : _d.weekly);
    const ref = db.doc(`clinics/${clinicId}/staffProfiles/${targetUid}/availability/default`);
    const snap = await ref.get();
    const now = admin.firestore.FieldValue.serverTimestamp();
    await ref.set({
        timezone,
        weekly,
        updatedAt: now,
        updatedByUid: actorUid,
        ...(snap.exists
            ? {}
            : { createdAt: now, createdByUid: actorUid }),
    }, { merge: false } // ✅ AUTHORITATIVE REPLACE
    );
    logger_1.logger.info("setStaffAvailabilityDefault: ok", {
        clinicId,
        actorUid,
        targetUid,
        created: !snap.exists,
    });
    return { ok: true, uid: targetUid };
}
//# sourceMappingURL=setStaffAvailabilityDefault.js.map