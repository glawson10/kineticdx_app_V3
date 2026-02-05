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
exports.updateClinicWeeklyHoursFn = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const logger_1 = require("firebase-functions/logger");
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
const DAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
function safeStr(v) {
    return typeof v === "string" ? v.trim() : "";
}
function hmToMinutes(hm) {
    const m = /^(\d{2}):(\d{2})$/.exec(hm.trim());
    if (!m)
        return NaN;
    const hh = Number(m[1]);
    const mm = Number(m[2]);
    if (!Number.isFinite(hh) || !Number.isFinite(mm))
        return NaN;
    if (hh < 0 || hh > 23 || mm < 0 || mm > 59)
        return NaN;
    return hh * 60 + mm;
}
function normalizeIntervals(raw) {
    const out = [];
    const list = Array.isArray(raw) ? raw : [];
    for (const it of list) {
        const start = safeStr(it === null || it === void 0 ? void 0 : it.start);
        const end = safeStr(it === null || it === void 0 ? void 0 : it.end);
        if (!start || !end)
            continue;
        const a = hmToMinutes(start);
        const b = hmToMinutes(end);
        if (!Number.isFinite(a) || !Number.isFinite(b))
            continue;
        if (b <= a)
            continue;
        out.push({ start, end });
    }
    // sort + de-overlap check
    out.sort((x, y) => hmToMinutes(x.start) - hmToMinutes(y.start));
    for (let i = 1; i < out.length; i++) {
        const prev = out[i - 1];
        const cur = out[i];
        const prevEnd = hmToMinutes(prev.end);
        const curStart = hmToMinutes(cur.start);
        if (curStart < prevEnd) {
            throw new https_1.HttpsError("invalid-argument", "Overlapping intervals are not allowed.");
        }
    }
    return out;
}
function normalizeWeeklyHours(raw) {
    const out = Object.fromEntries(DAY_KEYS.map((k) => [k, []]));
    for (const k of DAY_KEYS) {
        out[k] = normalizeIntervals(raw === null || raw === void 0 ? void 0 : raw[k]);
    }
    return out;
}
function normalizeWeeklyMeta(raw) {
    const base = {
        corporateOnly: false,
        requiresCorporateCode: false,
        locationLabel: "",
    };
    const out = Object.fromEntries(DAY_KEYS.map((k) => [k, { ...base }]));
    if (!raw || typeof raw !== "object")
        return out;
    for (const k of DAY_KEYS) {
        const m = raw[k];
        if (!m || typeof m !== "object")
            continue;
        out[k] = {
            corporateOnly: m.corporateOnly === true,
            requiresCorporateCode: m.requiresCorporateCode === true,
            locationLabel: safeStr(m.locationLabel),
        };
    }
    return out;
}
/**
 * Writes to:
 * clinics/{clinicId}/public/config/publicBooking/publicBooking
 *
 * Requires: caller is authenticated
 * (and your rules or backend membership check can be added later)
 */
exports.updateClinicWeeklyHoursFn = (0, https_1.onCall)({ region: "europe-west3", cors: true }, async (request) => {
    var _a, _b;
    const uid = (_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const data = ((_b = request.data) !== null && _b !== void 0 ? _b : {});
    const clinicId = safeStr(data.clinicId);
    if (!clinicId)
        throw new https_1.HttpsError("invalid-argument", "clinicId is required.");
    if (!data.weeklyHours || typeof data.weeklyHours !== "object") {
        throw new https_1.HttpsError("invalid-argument", "weeklyHours is required.");
    }
    // ✅ Normalize + validate
    const weeklyHours = normalizeWeeklyHours(data.weeklyHours);
    // meta optional; if absent keep existing doc value
    const metaProvided = data.weeklyHoursMeta && typeof data.weeklyHoursMeta === "object";
    const weeklyHoursMeta = metaProvided ? normalizeWeeklyMeta(data.weeklyHoursMeta) : null;
    const ref = db.doc(`clinics/${clinicId}/public/config/publicBooking/publicBooking`);
    await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists) {
            throw new https_1.HttpsError("failed-precondition", "Public booking not configured.");
        }
        const patch = {
            weeklyHours,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedBy: uid,
        };
        if (weeklyHoursMeta)
            patch.weeklyHoursMeta = weeklyHoursMeta;
        tx.set(ref, patch, { merge: true });
    });
    logger_1.logger.info("updateClinicWeeklyHoursFn ok", { clinicId, uid });
    return { ok: true };
});
//# sourceMappingURL=updateClinicWeeklyHours.js.map