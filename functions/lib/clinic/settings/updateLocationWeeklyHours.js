"use strict";
/**
 * Location opening hours: update weeklyHours for a location.
 * Validation: location hours must be within clinic opening hours (location ⊆ clinic).
 * Write path: clinics/{clinicId}/locations/{locationId}.weeklyHours
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
exports.locationHoursWithinClinic = locationHoursWithinClinic;
exports.updateLocationWeeklyHours = updateLocationWeeklyHours;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const permissions_1 = require("../permissions");
const audit_1 = require("../audit/audit");
const validators_1 = require("./validators");
const db = admin.firestore();
const FV = admin.firestore.FieldValue;
const DAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
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
function takeIntervals(list) {
    const out = [];
    if (!Array.isArray(list))
        return out;
    for (const it of list) {
        if (!it || typeof it !== "object" || Array.isArray(it))
            continue;
        const start = safeStr(it.start);
        const end = safeStr(it.end);
        if (!start || !end)
            continue;
        const a = hmToMinutes(start);
        const b = hmToMinutes(end);
        if (!Number.isFinite(a) || !Number.isFinite(b) || b <= a)
            continue;
        out.push({ start, end });
    }
    return out;
}
function normalizeWeeklyHours(raw) {
    const out = {};
    for (const day of DAY_KEYS) {
        out[day] = [];
    }
    if (!raw || typeof raw !== "object" || Array.isArray(raw))
        return out;
    const obj = raw;
    for (const day of DAY_KEYS) {
        const v = obj[day];
        out[day] = Array.isArray(v) ? takeIntervals(v) : [];
    }
    return out;
}
/** Check that every location interval on each day is contained in some clinic interval that day. Exported for tests. */
function locationHoursWithinClinic(clinicWeekly, locationWeekly) {
    var _a, _b;
    for (const day of DAY_KEYS) {
        const locIntervals = (_a = locationWeekly[day]) !== null && _a !== void 0 ? _a : [];
        const clinicIntervals = (_b = clinicWeekly[day]) !== null && _b !== void 0 ? _b : [];
        if (locIntervals.length === 0)
            continue;
        if (clinicIntervals.length === 0) {
            return { ok: false, message: `Location has hours on ${day} but clinic is closed that day. Location hours must fall within clinic opening hours.` };
        }
        const clinicMins = clinicIntervals.map((i) => ({ a: hmToMinutes(i.start), b: hmToMinutes(i.end) }));
        for (const loc of locIntervals) {
            const la = hmToMinutes(loc.start);
            const lb = hmToMinutes(loc.end);
            const contained = clinicMins.some((c) => la >= c.a && lb <= c.b);
            if (!contained) {
                return { ok: false, message: `Location hours on ${day} (${loc.start}–${loc.end}) extend outside clinic opening hours. Location hours must fall within clinic opening hours.` };
            }
        }
    }
    return { ok: true };
}
async function updateLocationWeeklyHours(request) {
    var _a, _b, _c;
    if (!((_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid)) {
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    }
    const data = request.data;
    const clinicId = (0, validators_1.requireNonEmptyString)(data === null || data === void 0 ? void 0 : data.clinicId, "clinicId");
    const locationId = (0, validators_1.requireNonEmptyString)(data === null || data === void 0 ? void 0 : data.locationId, "locationId");
    const weeklyHoursRaw = data === null || data === void 0 ? void 0 : data.weeklyHours;
    const locationWeekly = normalizeWeeklyHours(weeklyHoursRaw);
    const hasAny = DAY_KEYS.some((d) => { var _a, _b; return ((_b = (_a = locationWeekly[d]) === null || _a === void 0 ? void 0 : _a.length) !== null && _b !== void 0 ? _b : 0) > 0; });
    const uid = request.auth.uid;
    await (0, permissions_1.requireClinicPermission)(db, clinicId, uid, "settings.write");
    const [settingsSnap, locSnap] = await Promise.all([
        db.doc(`clinics/${clinicId}/settings/publicBooking`).get(),
        db.doc(`clinics/${clinicId}/locations/${locationId}`).get(),
    ]);
    if (!locSnap.exists) {
        throw new https_1.HttpsError("not-found", "Location not found.");
    }
    const settingsData = settingsSnap.exists ? ((_b = settingsSnap.data()) !== null && _b !== void 0 ? _b : {}) : {};
    const clinicWeekly = normalizeWeeklyHours(settingsData.weeklyHours);
    if (hasAny) {
        const check = locationHoursWithinClinic(clinicWeekly, locationWeekly);
        if (!check.ok) {
            throw new https_1.HttpsError("invalid-argument", (_c = check.message) !== null && _c !== void 0 ? _c : "Location hours must fall within clinic opening hours.");
        }
    }
    const updateData = {
        updatedAt: FV.serverTimestamp(),
        weeklyHours: locationWeekly,
    };
    await db.doc(`clinics/${clinicId}/locations/${locationId}`).update(updateData);
    await (0, audit_1.writeSettingsAuditEvent)(db, clinicId, "settings.location.openingHours.updated", uid, `clinics/${clinicId}/locations`, locationId, { weeklyHours: locationWeekly });
    return { ok: true, locationId };
}
//# sourceMappingURL=updateLocationWeeklyHours.js.map