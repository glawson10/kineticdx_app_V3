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
const DAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
function parseHHMM(s) {
    const t = safeStr(s);
    const m = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(t);
    if (!m) {
        throw new https_1.HttpsError("invalid-argument", `Invalid time: "${t}" (expected HH:mm).`);
    }
    const hh = Number(m[1]);
    const mm = Number(m[2]);
    return hh * 60 + mm;
}
function validateIntervals(day, arr) {
    if (!Array.isArray(arr)) {
        throw new https_1.HttpsError("invalid-argument", `weekly.${day} must be an array.`);
    }
    const out = [];
    for (let i = 0; i < arr.length; i++) {
        const it = arr[i];
        if (!it || typeof it !== "object" || Array.isArray(it)) {
            throw new https_1.HttpsError("invalid-argument", `weekly.${day}[${i}] must be an object {start,end}.`);
        }
        const start = safeStr(it.start);
        const end = safeStr(it.end);
        if (!start || !end) {
            throw new https_1.HttpsError("invalid-argument", `weekly.${day}[${i}] requires start and end.`);
        }
        const sMin = parseHHMM(start);
        const eMin = parseHHMM(end);
        if (eMin <= sMin) {
            throw new https_1.HttpsError("invalid-argument", `weekly.${day}[${i}] end must be after start.`);
        }
        out.push({ start, end });
    }
    // Optional: detect overlaps (simple)
    const mins = out
        .map((x) => ({ s: parseHHMM(x.start), e: parseHHMM(x.end), x }))
        .sort((a, b) => a.s - b.s);
    for (let i = 1; i < mins.length; i++) {
        if (mins[i].s < mins[i - 1].e) {
            throw new https_1.HttpsError("invalid-argument", `weekly.${day} has overlapping intervals.`);
        }
    }
    return out;
}
function sanitizeWeekly(rawWeekly) {
    var _a;
    const weeklyObj = ensurePlainObject(rawWeekly, "weekly");
    const out = {};
    for (const d of DAYS) {
        const v = (_a = weeklyObj[d]) !== null && _a !== void 0 ? _a : [];
        out[d] = validateIntervals(d, v);
    }
    // Ignore unexpected keys to keep schema stable
    return out;
}
async function setStaffAvailabilityDefault(req) {
    var _a, _b, _c, _d;
    if (!req.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const clinicId = safeStr((_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId);
    const targetUid = safeStr((_b = req.data) === null || _b === void 0 ? void 0 : _b.uid);
    const timezone = safeStr((_c = req.data) === null || _c === void 0 ? void 0 : _c.timezone);
    if (!clinicId)
        throw new https_1.HttpsError("invalid-argument", "clinicId required.");
    if (!targetUid)
        throw new https_1.HttpsError("invalid-argument", "uid required.");
    if (!timezone)
        throw new https_1.HttpsError("invalid-argument", "timezone required.");
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
    const weekly = sanitizeWeekly((_d = req.data) === null || _d === void 0 ? void 0 : _d.weekly);
    const availRef = db
        .collection("clinics")
        .doc(clinicId)
        .collection("staffProfiles")
        .doc(targetUid)
        .collection("availability")
        .doc("default");
    const snap = await availRef.get();
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
    await availRef.set({
        timezone,
        weekly,
        ...baseAudit,
        ...createAudit,
    }, { merge: true });
    logger_1.logger.info("setStaffAvailabilityDefault: ok", {
        clinicId,
        actorUid,
        targetUid,
        created: !snap.exists,
    });
    return { ok: true, uid: targetUid };
}
//# sourceMappingURL=setStaffAvailabilityDefault.js.map