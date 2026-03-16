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
exports.getPublicBookingDiagnosticsFn = exports.getPublicBookingAppointmentTypesFn = exports.getPublicBookingLocationsFn = exports.getPublicBookingPractitionersFn = exports.getPublicMonthAvailabilityFn = exports.listPublicSlotsFn = void 0;
exports.invalidateSlotCacheForBooking = invalidateSlotCacheForBooking;
exports.intersectWeeklyHours = intersectWeeklyHours;
exports.computeEffectiveWeeklyHours = computeEffectiveWeeklyHours;
// functions/src/public/listPublicSlots.ts
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const logger_1 = require("firebase-functions/logger");
const rateLimit_1 = require("./rateLimit");
const permissions_1 = require("../clinic/permissions");
// Commit 17: Availability reads only from public/config/publicBooking/config (no writePublicBookingMirror / private settings).
// Commit 51: In-memory slot cache (TTL 45s, key: clinicId|locationId|practitionerId|appointmentTypeId|date in clinic TZ).
const bookingConfig_1 = require("./bookingConfig");
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
const SLOT_CACHE_TTL_MS = 45 * 1000;
const SLOT_CACHE_MAX_KEYS = 500;
const slotCache = new Map();
function evictSlotCacheIfNeeded() {
    if (slotCache.size <= SLOT_CACHE_MAX_KEYS)
        return;
    const entries = Array.from(slotCache.entries()).sort((a, b) => a[1].cachedAt - b[1].cachedAt);
    const toDelete = entries.length - SLOT_CACHE_MAX_KEYS;
    for (let i = 0; i < toDelete; i++) {
        slotCache.delete(entries[i][0]);
    }
}
/** Commit 51: Invalidate slot cache for a given clinic/practitioner/date after successful booking. */
function invalidateSlotCacheForBooking(clinicId, practitionerId, dateYmd) {
    const toDelete = [];
    for (const key of slotCache.keys()) {
        const parts = key.split("|");
        if (parts[0] === clinicId && parts[2] === practitionerId && parts[4] === dateYmd) {
            toDelete.push(key);
        }
    }
    for (const k of toDelete)
        slotCache.delete(k);
    if (toDelete.length > 0) {
        logger_1.logger.info("Slot cache invalidated after booking", {
            clinicId,
            practitionerId,
            dateYmd,
            keysRemoved: toDelete.length,
        });
    }
}
function safeStr(v) {
    return typeof v === "string" ? v.trim() : "";
}
function parseMillis(label, ms) {
    if (typeof ms !== "number" || !Number.isFinite(ms) || ms <= 0) {
        throw new https_1.HttpsError("invalid-argument", `Invalid ${label}Ms.`);
    }
    const d = new Date(ms);
    if (Number.isNaN(d.getTime())) {
        throw new https_1.HttpsError("invalid-argument", `Invalid ${label}Ms.`);
    }
    return d;
}
function parseIso(label, iso) {
    const t = Date.parse(iso);
    if (!Number.isFinite(t)) {
        throw new https_1.HttpsError("invalid-argument", `Invalid ${label} (expected ISO date string).`);
    }
    const d = new Date(t);
    if (Number.isNaN(d.getTime()))
        throw new https_1.HttpsError("invalid-argument", `Invalid ${label}.`);
    return d;
}
function getTz(settings, overrideTz) {
    return safeStr(overrideTz) || safeStr(settings.timezone) || "Europe/Prague";
}
function ymdFromDateInTz(d, tz) {
    var _a, _b, _c, _d, _e, _f;
    const parts = new Intl.DateTimeFormat("en-CA", {
        timeZone: tz,
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
    }).formatToParts(d);
    const y = (_b = (_a = parts.find((p) => p.type === "year")) === null || _a === void 0 ? void 0 : _a.value) !== null && _b !== void 0 ? _b : "";
    const m = (_d = (_c = parts.find((p) => p.type === "month")) === null || _c === void 0 ? void 0 : _c.value) !== null && _d !== void 0 ? _d : "";
    const day = (_f = (_e = parts.find((p) => p.type === "day")) === null || _e === void 0 ? void 0 : _e.value) !== null && _f !== void 0 ? _f : "";
    return `${y}-${m}-${day}`;
}
function dayKeyFromDateInTz(d, tz) {
    const weekday = new Intl.DateTimeFormat("en-US", {
        weekday: "short",
        timeZone: tz,
    }).format(d);
    const w = weekday.toLowerCase();
    if (w.startsWith("mon"))
        return "mon";
    if (w.startsWith("tue"))
        return "tue";
    if (w.startsWith("wed"))
        return "wed";
    if (w.startsWith("thu"))
        return "thu";
    if (w.startsWith("fri"))
        return "fri";
    if (w.startsWith("sat"))
        return "sat";
    return "sun";
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
function findCorporate(settings, corpSlug) {
    var _a;
    const slug = safeStr(corpSlug).toLowerCase();
    if (!slug)
        return null;
    const list = Array.isArray(settings.corporatePrograms)
        ? settings.corporatePrograms
        : [];
    return (_a = list.find((p) => safeStr(p === null || p === void 0 ? void 0 : p.corpSlug).toLowerCase() === slug)) !== null && _a !== void 0 ? _a : null;
}
function extractAllowedPractitionerIds(settings) {
    var _a, _b, _c, _d;
    const raw = (_d = (_a = (Array.isArray(settings.practitioners) ? settings.practitioners : null)) !== null && _a !== void 0 ? _a : (Array.isArray((_b = settings.publicBooking) === null || _b === void 0 ? void 0 : _b.practitioners)
        ? (_c = settings.publicBooking) === null || _c === void 0 ? void 0 : _c.practitioners
        : null)) !== null && _d !== void 0 ? _d : [];
    const ids = [];
    for (const item of raw) {
        if (item && typeof item === "object") {
            const id = safeStr(item.id);
            if (id)
                ids.push(id);
            continue;
        }
        if (typeof item === "string") {
            const m = item.match(/id:\s*"?([^"]+)"?/i);
            if (m === null || m === void 0 ? void 0 : m[1])
                ids.push(m[1].trim());
        }
    }
    return Array.from(new Set(ids));
}
async function loadClosures(clinicId, rangeStart, rangeEnd) {
    const snap = await db
        .collection(`clinics/${clinicId}/closures`)
        .where("active", "==", true)
        .where("fromAt", "<", rangeEnd)
        .get();
    const out = [];
    for (const doc of snap.docs) {
        const d = doc.data();
        const fromAt = d === null || d === void 0 ? void 0 : d.fromAt;
        const toAt = d === null || d === void 0 ? void 0 : d.toAt;
        if (!fromAt || !toAt)
            continue;
        const fromMs = fromAt.toMillis();
        const toMs = toAt.toMillis();
        if (rangeStart.toMillis() < toMs && rangeEnd.toMillis() > fromMs) {
            out.push({ fromMs, toMs });
        }
    }
    return out;
}
async function loadClinicWideBusyBlocks(clinicId, rangeStart, rangeEnd) {
    const col = db.collection(`clinics/${clinicId}/public/availability/blocks`);
    const snap = await col.where("startUtc", "<", rangeEnd).get();
    const out = [];
    for (const doc of snap.docs) {
        const d = doc.data();
        const s = d === null || d === void 0 ? void 0 : d.startUtc;
        const e = d === null || d === void 0 ? void 0 : d.endUtc;
        const status = safeStr(d === null || d === void 0 ? void 0 : d.status);
        if (!s || !e)
            continue;
        if (status === "cancelled")
            continue;
        const scope = safeStr(d === null || d === void 0 ? void 0 : d.scope);
        const kind = safeStr(d === null || d === void 0 ? void 0 : d.kind).toLowerCase();
        const pid = safeStr(d === null || d === void 0 ? void 0 : d.practitionerId);
        const cid = safeStr(d === null || d === void 0 ? void 0 : d.clinicianId);
        const isClinicScoped = scope === "clinic";
        const isLegacyClinicWideAdmin = !scope && kind === "admin" && !pid && !cid;
        if (!isClinicScoped && !isLegacyClinicWideAdmin)
            continue;
        const sMs = s.toMillis();
        const eMs = e.toMillis();
        if (rangeStart.toMillis() < eMs && rangeEnd.toMillis() > sMs) {
            out.push({ startMs: sMs, endMs: eMs });
        }
    }
    return out;
}
async function loadBusyBlocks(clinicId, practitionerId, rangeStart, rangeEnd) {
    const pid = safeStr(practitionerId);
    const col = db.collection(`clinics/${clinicId}/public/availability/blocks`);
    const snap = await col.where("startUtc", "<", rangeEnd).get();
    const out = [];
    for (const doc of snap.docs) {
        const d = doc.data();
        const s = d === null || d === void 0 ? void 0 : d.startUtc;
        const e = d === null || d === void 0 ? void 0 : d.endUtc;
        const status = safeStr(d === null || d === void 0 ? void 0 : d.status);
        const scope = safeStr(d === null || d === void 0 ? void 0 : d.scope);
        const kind = safeStr(d === null || d === void 0 ? void 0 : d.kind).toLowerCase();
        const docPid = safeStr(d === null || d === void 0 ? void 0 : d.practitionerId);
        const docCid = safeStr(d === null || d === void 0 ? void 0 : d.clinicianId);
        if (!s || !e)
            continue;
        if (status === "cancelled")
            continue;
        const sMs = s.toMillis();
        const eMs = e.toMillis();
        if (!(rangeStart.toMillis() < eMs && rangeEnd.toMillis() > sMs))
            continue;
        let applies = false;
        if (scope === "clinic") {
            applies = true;
        }
        else if (scope === "practitioner") {
            if (!pid)
                applies = false;
            else
                applies = docPid === pid || docCid === pid;
        }
        else if (!scope) {
            if (kind === "admin" && !docPid && !docCid) {
                applies = true;
            }
            else {
                if (!pid)
                    applies = false;
                else
                    applies = docPid === pid || docCid === pid;
            }
        }
        else {
            applies = false;
        }
        if (!applies)
            continue;
        out.push({ startMs: sMs, endMs: eMs });
    }
    return out;
}
async function loadAppointmentsAsBlocks(clinicId, practitionerId, rangeStart, rangeEnd) {
    var _a, _b;
    const pid = safeStr(practitionerId);
    if (!pid)
        return [];
    const col = db.collection(`clinics/${clinicId}/appointments`);
    const snap = await col.where("startAt", "<", rangeEnd).get();
    const out = [];
    for (const doc of snap.docs) {
        const d = doc.data();
        const docPid = safeStr(d === null || d === void 0 ? void 0 : d.practitionerId);
        if (docPid !== pid)
            continue;
        const status = safeStr(d === null || d === void 0 ? void 0 : d.status).toLowerCase();
        if (status === "cancelled")
            continue;
        const sTs = (_a = d === null || d === void 0 ? void 0 : d.startAt) !== null && _a !== void 0 ? _a : d === null || d === void 0 ? void 0 : d.start;
        const eTs = (_b = d === null || d === void 0 ? void 0 : d.endAt) !== null && _b !== void 0 ? _b : d === null || d === void 0 ? void 0 : d.end;
        if (!sTs || !eTs)
            continue;
        const sMs = sTs.toMillis();
        const eMs = eTs.toMillis();
        if (!(rangeStart.toMillis() < eMs && rangeEnd.toMillis() > sMs))
            continue;
        out.push({ startMs: sMs, endMs: eMs });
    }
    return out;
}
/**
 * Load practitioner overrides that overlap [rangeStart, rangeEnd].
 * When locationId is set, only include overrides whose locationId is null (global) or matches.
 * Used so public slots respect "unavailable" (time off) and "extra available" (one-off hours).
 */
async function loadPractitionerOverrides(clinicId, practitionerId, rangeStart, rangeEnd, locationId) {
    const pid = safeStr(practitionerId);
    if (!pid)
        return { unavailable: [], available: [] };
    const col = db
        .collection("clinics")
        .doc(clinicId)
        .collection("practitioners")
        .doc(pid)
        .collection("overrides");
    const snap = await col.where("toAt", ">", rangeStart).get();
    const rangeStartMs = rangeStart.toMillis();
    const rangeEndMs = rangeEnd.toMillis();
    const locId = safeStr(locationId);
    const unavailable = [];
    const available = [];
    for (const doc of snap.docs) {
        const d = doc.data();
        const fromAt = d === null || d === void 0 ? void 0 : d.fromAt;
        const toAt = d === null || d === void 0 ? void 0 : d.toAt;
        if (!fromAt || !toAt)
            continue;
        const fromMs = fromAt.toMillis();
        const toMs = toAt.toMillis();
        if (fromMs >= rangeEndMs)
            continue;
        const overrideLocId = (d === null || d === void 0 ? void 0 : d.locationId) == null || (d === null || d === void 0 ? void 0 : d.locationId) === "" ? null : safeStr(d.locationId);
        if (locId.length > 0 && overrideLocId != null && overrideLocId !== locId)
            continue;
        const isAvailable = (d === null || d === void 0 ? void 0 : d.isAvailable) === true;
        const block = { startMs: fromMs, endMs: toMs };
        if (isAvailable)
            available.push(block);
        else
            unavailable.push(block);
    }
    return { unavailable, available };
}
function slotContainedInRanges(startMs, endMs, ranges) {
    return ranges.some((r) => startMs >= r.startMs && endMs <= r.endMs);
}
function overlapsAny(startMs, endMs, blocks) {
    return blocks.some((b) => startMs < b.endMs && endMs > b.startMs);
}
function normalizeWeeklyHours(settings) {
    const keys = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
    const out = Object.fromEntries(keys.map((k) => [k, []]));
    const takeIntervals = (k, list) => {
        const cleaned = [];
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
            cleaned.push({ start, end });
        }
        out[k] = cleaned;
    };
    // Prefer canonical weeklyHours
    if (settings.weeklyHours && typeof settings.weeklyHours === "object") {
        for (const k of keys) {
            const v = settings.weeklyHours[k];
            if (Array.isArray(v))
                takeIntervals(k, v);
        }
        return out;
    }
    // Fallback: legacy openingHours
    const oh = settings.openingHours;
    if (oh && typeof oh === "object") {
        let matchedKeyMap = false;
        for (const k of keys) {
            const v = oh[k];
            if (Array.isArray(v)) {
                matchedKeyMap = true;
                takeIntervals(k, v);
            }
        }
        if (matchedKeyMap)
            return out;
        const daysArr = oh.days;
        if (Array.isArray(daysArr)) {
            for (const row of daysArr) {
                const rawDay = safeStr(row === null || row === void 0 ? void 0 : row.day) ||
                    safeStr(row === null || row === void 0 ? void 0 : row.dayKey) ||
                    safeStr(row === null || row === void 0 ? void 0 : row.weekday) ||
                    safeStr(row === null || row === void 0 ? void 0 : row.id);
                const dk = rawDay.toLowerCase().slice(0, 3);
                if (!keys.includes(dk))
                    continue;
                const closed = (row === null || row === void 0 ? void 0 : row.closed) === true ||
                    (row === null || row === void 0 ? void 0 : row.isClosed) === true ||
                    (row === null || row === void 0 ? void 0 : row.open) === false ||
                    (row === null || row === void 0 ? void 0 : row.isOpen) === false;
                if (closed) {
                    out[dk] = [];
                    continue;
                }
                const intervals = (Array.isArray(row === null || row === void 0 ? void 0 : row.intervals) && row.intervals) ||
                    (Array.isArray(row === null || row === void 0 ? void 0 : row.windows) && row.windows) ||
                    (Array.isArray(row === null || row === void 0 ? void 0 : row.ranges) && row.ranges) ||
                    (safeStr(row === null || row === void 0 ? void 0 : row.start) && safeStr(row === null || row === void 0 ? void 0 : row.end)
                        ? [{ start: row.start, end: row.end }]
                        : []) ||
                    [];
                if (Array.isArray(intervals))
                    takeIntervals(dk, intervals);
            }
            return out;
        }
    }
    return out;
}
async function loadStaffWeeklyAvailability(params) {
    const clinicId = safeStr(params.clinicId);
    const pid = safeStr(params.practitionerId);
    if (!clinicId || !pid)
        return null;
    const ref = db.doc(`clinics/${clinicId}/staffProfiles/${pid}/availability/default`);
    const snap = await ref.get();
    if (!snap.exists)
        return null;
    const data = snap.data();
    const weekly = data === null || data === void 0 ? void 0 : data.weekly;
    if (!weekly || typeof weekly !== "object")
        return null;
    const keys = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
    const out = Object.fromEntries(keys.map((k) => [k, []]));
    for (const k of keys) {
        const v = weekly[k];
        if (!Array.isArray(v))
            continue;
        const cleaned = [];
        for (const it of v) {
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
            cleaned.push({ start, end });
        }
        cleaned.sort((x, y) => hmToMinutes(x.start) - hmToMinutes(y.start));
        out[k] = cleaned;
    }
    const timezone = safeStr(data === null || data === void 0 ? void 0 : data.timezone) || undefined;
    return { timezone, weekly: out };
}
const AVAIL_DAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
/** dayOfWeek 1 = Monday → mon, 7 = Sunday → sun (canonical availability blocks). */
const DOW_TO_DAY = {
    1: "mon",
    2: "tue",
    3: "wed",
    4: "thu",
    5: "fri",
    6: "sat",
    7: "sun",
};
/**
 * Load practitioner availability from practitioners/{id}/availability filtered by locationId.
 * Used when the request is location-scoped so slots/calendar only show availability for that location.
 * See docs/AVAILABILITY_SOURCES.md.
 */
async function loadStaffWeeklyAvailabilityForLocation(params) {
    const clinicId = safeStr(params.clinicId);
    const pid = safeStr(params.practitionerId);
    const locationId = safeStr(params.locationId);
    if (!clinicId || !pid || !locationId)
        return null;
    const availCol = db
        .collection("clinics")
        .doc(clinicId)
        .collection("practitioners")
        .doc(pid)
        .collection("availability");
    const snap = await availCol.get();
    const perDay = Object.fromEntries(AVAIL_DAY_KEYS.map((k) => [k, []]));
    for (const doc of snap.docs) {
        const data = doc.data();
        if ((data === null || data === void 0 ? void 0 : data.active) === false)
            continue;
        if (safeStr(data === null || data === void 0 ? void 0 : data.locationId) !== locationId)
            continue;
        const blocks = Array.isArray(data === null || data === void 0 ? void 0 : data.blocks) ? data.blocks : [];
        for (const b of blocks) {
            if (!b || typeof b !== "object")
                continue;
            const bookableOnline = b.bookableOnline !== false;
            if (!bookableOnline)
                continue;
            const dayOfWeek = Number(b.dayOfWeek);
            const dayKey = DOW_TO_DAY[dayOfWeek];
            if (!dayKey)
                continue;
            const startM = hmToMinutes(safeStr(b.startTime));
            const endM = hmToMinutes(safeStr(b.endTime));
            if (startM == null || endM == null || endM <= startM)
                continue;
            perDay[dayKey].push({ a: startM, b: endM });
        }
    }
    const weekly = Object.fromEntries(AVAIL_DAY_KEYS.map((k) => [
        k,
        mergeIntervals(perDay[k]).map(({ a, b }) => ({
            start: minutesToHHmm(a),
            end: minutesToHHmm(b),
        })),
    ]));
    const hasAny = Object.values(weekly).some((arr) => arr.length > 0);
    if (!hasAny)
        return null;
    return { timezone: undefined, weekly };
}
function minutesToHHmm(m) {
    const hh = Math.floor(m / 60);
    const mm = m % 60;
    return `${String(hh).padStart(2, "0")}:${String(mm).padStart(2, "0")}`;
}
function mergeIntervals(list) {
    const sorted = [...list].sort((x, y) => x.a - y.a);
    const out = [];
    let cur = null;
    for (const it of sorted) {
        if (!cur) {
            cur = { a: it.a, b: it.b };
            continue;
        }
        if (it.a <= cur.b) {
            cur.b = Math.max(cur.b, it.b);
        }
        else {
            out.push(cur);
            cur = { a: it.a, b: it.b };
        }
    }
    if (cur)
        out.push(cur);
    return out;
}
function normalizeToMinutes(weekly) {
    const keys = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
    const out = Object.fromEntries(keys.map((k) => [k, []]));
    for (const k of keys) {
        const intervals = Array.isArray(weekly[k]) ? weekly[k] : [];
        const mins = [];
        for (const it of intervals) {
            const a = hmToMinutes(safeStr(it.start));
            const b = hmToMinutes(safeStr(it.end));
            if (!Number.isFinite(a) || !Number.isFinite(b))
                continue;
            if (b <= a)
                continue;
            mins.push({ a, b });
        }
        out[k] = mergeIntervals(mins);
    }
    return out;
}
function minsToWeekly(weeklyMins) {
    const keys = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
    const out = Object.fromEntries(keys.map((k) => [k, []]));
    const fmt = (m) => {
        const hh = Math.floor(m / 60);
        const mm = m % 60;
        return `${String(hh).padStart(2, "0")}:${String(mm).padStart(2, "0")}`;
    };
    for (const k of keys) {
        out[k] = (weeklyMins[k] || []).map((it) => ({
            start: fmt(it.a),
            end: fmt(it.b),
        }));
    }
    return out;
}
/** Exported for unit tests (multi-location slot resolution). */
function intersectWeeklyHours(clinicWeekly, staffWeekly) {
    const keys = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
    const a = normalizeToMinutes(clinicWeekly);
    const b = normalizeToMinutes(staffWeekly);
    const outMins = Object.fromEntries(keys.map((k) => [k, []]));
    for (const k of keys) {
        const A = a[k] || [];
        const B = b[k] || [];
        const out = [];
        let i = 0;
        let j = 0;
        while (i < A.length && j < B.length) {
            const x = A[i];
            const y = B[j];
            const start = Math.max(x.a, y.a);
            const end = Math.min(x.b, y.b);
            if (end > start)
                out.push({ a: start, b: end });
            if (x.b < y.b)
                i++;
            else
                j++;
        }
        outMins[k] = mergeIntervals(out);
    }
    return minsToWeekly(outMins);
}
/**
 * Compute effective weekly hours for slot resolution: clinic ∩ (location if present) ∩ (practitioner if present).
 * Exported for unit tests (multi-location slot resolution).
 */
function computeEffectiveWeeklyHours(clinicWeekly, locationWeekly, practitionerWeekly) {
    let afterClinic = clinicWeekly;
    if (locationWeekly && Object.values(locationWeekly).some((arr) => Array.isArray(arr) && arr.length > 0)) {
        afterClinic = intersectWeeklyHours(clinicWeekly, locationWeekly);
    }
    if (practitionerWeekly && Object.values(practitionerWeekly).some((arr) => Array.isArray(arr) && arr.length > 0)) {
        return intersectWeeklyHours(afterClinic, practitionerWeekly);
    }
    return afterClinic;
}
// Commit 17: Availability engine reads only from public mirror (config doc). No private settings reads.
const CONFIG_DOC_PATH = (clinicId) => `clinics/${clinicId}/public/config/publicBooking/config`;
const FULL_MIRROR_PATH = (clinicId) => `clinics/${clinicId}/public/config/publicBooking/publicBooking`;
const DAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
function defaultWeeklyHours() {
    return Object.fromEntries(DAY_KEYS.map((k) => [k, []]));
}
/** Normalize one location's weekly hours from mirror (same shape as clinic weeklyHours). */
function normalizeLocationWeeklyHoursFromMirror(raw) {
    const out = defaultWeeklyHours();
    if (!raw || typeof raw !== "object" || Array.isArray(raw))
        return out;
    const obj = raw;
    for (const day of DAY_KEYS) {
        const v = obj[day];
        if (!Array.isArray(v))
            continue;
        out[day] = v
            .filter((it) => it && typeof it === "object" && safeStr(it.start) && safeStr(it.end))
            .map((it) => ({ start: safeStr(it.start), end: safeStr(it.end) }));
    }
    return out;
}
/** Load booking rules + weeklyHours + locationOpeningHours from mirror config doc only. Uses defaults if missing. */
async function loadPublicConfigFromMirror(clinicId) {
    const configRef = db.doc(CONFIG_DOC_PATH(clinicId));
    const configSnap = await configRef.get();
    if (!configSnap.exists || !configSnap.data()) {
        logger_1.logger.warn("[projection/publicBooking] public booking config missing; using defaults", {
            clinicId,
        });
        return {
            timezone: "UTC",
            slotStepMinutes: 15,
            minNoticeMinutes: 0,
            maxAdvanceDays: 90,
            weeklyHours: defaultWeeklyHours(),
            locationOpeningHours: {},
            onlineBookingEnabled: true,
        };
    }
    const d = configSnap.data();
    const rules = (0, bookingConfig_1.normalizeBookingRulesFromConfigDoc)(d);
    const rulesRaw = (d === null || d === void 0 ? void 0 : d.bookingRules) && typeof d.bookingRules === "object" ? d.bookingRules : {};
    const wh = (d === null || d === void 0 ? void 0 : d.weeklyHours) && typeof d.weeklyHours === "object" ? d.weeklyHours : {};
    const locHoursRaw = (d === null || d === void 0 ? void 0 : d.locationOpeningHours) && typeof d.locationOpeningHours === "object" ? d.locationOpeningHours : {};
    const timezone = rules.timezone || "UTC";
    const slotStepMinutes = typeof rulesRaw.slotStepMinutes === "number" && [5, 10, 15, 20, 30].includes(rulesRaw.slotStepMinutes)
        ? rulesRaw.slotStepMinutes
        : 15;
    const minNoticeMinutes = rules.minNoticeMinutes;
    const maxAdvanceDays = rules.maxAdvanceDays;
    const weeklyHours = defaultWeeklyHours();
    for (const day of DAY_KEYS) {
        const v = wh[day];
        if (Array.isArray(v)) {
            weeklyHours[day] = v
                .filter((it) => it && typeof it === "object" && safeStr(it.start) && safeStr(it.end))
                .map((it) => ({ start: safeStr(it.start), end: safeStr(it.end) }));
        }
    }
    const locationOpeningHours = {};
    for (const [locId, raw] of Object.entries(locHoursRaw)) {
        if (typeof locId !== "string" || !locId.trim())
            continue;
        const normalized = normalizeLocationWeeklyHoursFromMirror(raw);
        const hasAny = DAY_KEYS.some((day) => { var _a, _b; return ((_b = (_a = normalized[day]) === null || _a === void 0 ? void 0 : _a.length) !== null && _b !== void 0 ? _b : 0) > 0; });
        if (hasAny)
            locationOpeningHours[locId.trim()] = normalized;
    }
    const onlineBookingEnabled = rulesRaw.onlineBookingEnabled !== false;
    return {
        timezone,
        slotStepMinutes,
        minNoticeMinutes,
        maxAdvanceDays,
        weeklyHours,
        locationOpeningHours,
        onlineBookingEnabled,
    };
}
/** Load practitioners + corporatePrograms from full mirror (for allowlist). Does not read private settings. */
async function loadFullMirrorExtras(clinicId) {
    var _a;
    const fullRef = db.doc(FULL_MIRROR_PATH(clinicId));
    const snap = await fullRef.get();
    if (!snap.exists || !snap.data())
        return { practitioners: [], corporatePrograms: undefined };
    const d = snap.data();
    const raw = Array.isArray(d === null || d === void 0 ? void 0 : d.practitioners) ? d.practitioners : Array.isArray((_a = d === null || d === void 0 ? void 0 : d.publicBooking) === null || _a === void 0 ? void 0 : _a.practitioners)
        ? d.publicBooking.practitioners
        : [];
    const practitioners = [];
    for (const item of raw) {
        if (item && typeof item === "object") {
            const id = safeStr(item.id);
            if (id) {
                const allowedLocationIds = Array.isArray(item.allowedLocationIds)
                    ? item.allowedLocationIds.filter((x) => typeof x === "string" && x.trim())
                    : undefined;
                const entry = {
                    id,
                    displayName: safeStr(item.displayName),
                    serviceIdsAllowed: item.serviceIdsAllowed,
                    sortOrder: item.sortOrder,
                    allowedLocationIds,
                };
                const title = safeStr(item.title);
                if (title)
                    entry.title = title;
                const photoUrl = safeStr(item.photoUrl);
                if (photoUrl)
                    entry.photoUrl = photoUrl;
                const bio = safeStr(item.bio);
                if (bio)
                    entry.bio = bio;
                practitioners.push(entry);
            }
        }
    }
    const corporatePrograms = Array.isArray(d === null || d === void 0 ? void 0 : d.corporatePrograms) ? d.corporatePrograms : undefined;
    return { practitioners, corporatePrograms };
}
/** Commit 17: Load settings for availability from mirror config only. No private settings fallback. */
async function loadPublicSettingsFromMirror(clinicId) {
    var _a;
    const [config, extras] = await Promise.all([
        loadPublicConfigFromMirror(clinicId),
        loadFullMirrorExtras(clinicId),
    ]);
    return {
        timezone: config.timezone,
        slotStepMinutes: config.slotStepMinutes,
        minNoticeMinutes: config.minNoticeMinutes,
        maxAdvanceDays: config.maxAdvanceDays,
        weeklyHours: config.weeklyHours,
        locationOpeningHours: (_a = config.locationOpeningHours) !== null && _a !== void 0 ? _a : {},
        onlineBookingEnabled: config.onlineBookingEnabled,
        practitioners: extras.practitioners,
        corporatePrograms: extras.corporatePrograms,
    };
}
exports.listPublicSlotsFn = (0, https_1.onCall)({ region: "europe-west3", cors: true }, async (request) => {
    var _a, _b, _c;
    try {
        const data = ((_a = request.data) !== null && _a !== void 0 ? _a : {});
        const clinicId = safeStr(data.clinicId);
        const serviceId = safeStr(data.serviceId);
        const practitionerId = safeStr(data.practitionerId);
        const locationId = safeStr(data.locationId) || undefined;
        const appointmentTypeId = safeStr(data.appointmentTypeId) || undefined;
        if (!clinicId) {
            throw new https_1.HttpsError("invalid-argument", "clinicId is required.");
        }
        const purpose = safeStr(data.purpose);
        const openingOnly = purpose === "openingWindows";
        logger_1.logger.info("listPublicSlots purpose", {
            clinicId,
            purpose,
            openingOnly,
            practitionerId: practitionerId || null,
        });
        const fromUtc = safeStr(data.fromUtc);
        const toUtc = safeStr(data.toUtc);
        const rangeStartDt = fromUtc
            ? parseIso("fromUtc", fromUtc)
            : parseMillis("rangeStart", data.rangeStartMs);
        const rangeEndDt = toUtc
            ? parseIso("toUtc", toUtc)
            : parseMillis("rangeEnd", data.rangeEndMs);
        if (rangeEndDt <= rangeStartDt) {
            throw new https_1.HttpsError("invalid-argument", "Invalid range.");
        }
        // Rate limit
        try {
            await (0, rateLimit_1.enforceRateLimit)({
                db,
                clinicId,
                req: request.rawRequest,
                cfg: { name: "listPublicSlots", max: 120, windowSeconds: 60 },
            });
        }
        catch (e) {
            logger_1.logger.warn("Rate limit skipped/failed (callable)", {
                clinicId,
                err: String(e),
            });
        }
        // ✅ Commit 17: Read only from mirror config (no private settings)
        const settings = await loadPublicSettingsFromMirror(clinicId);
        const isOpeningWindows = purpose === "openingWindows";
        if (!isOpeningWindows && settings.onlineBookingEnabled === false) {
            throw new https_1.HttpsError("failed-precondition", "Booking is temporarily unavailable.");
        }
        // Validate practitionerId against allowlist (only if practitionerId provided AND not openingWindows)
        // For openingWindows (internal calendar), we allow any practitioner - they just need to exist in the clinic
        if (practitionerId) {
            if (isOpeningWindows) {
                // ✅ For internal calendar, verify practitioner exists in clinic (but don't check public allowlist)
                const memberRef = db.doc(`clinics/${clinicId}/members/${practitionerId}`);
                const legacyRef = db.doc(`clinics/${clinicId}/memberships/${practitionerId}`);
                const [memberSnap, legacySnap] = await Promise.all([
                    memberRef.get(),
                    legacyRef.get(),
                ]);
                if (!memberSnap.exists && !legacySnap.exists) {
                    throw new https_1.HttpsError("failed-precondition", `Practitioner ${practitionerId} is not a member of this clinic.`);
                }
            }
            else {
                // ✅ For public booking, check against allowlist
                const allowed = extractAllowedPractitionerIds(settings);
                const ok = allowed.includes(practitionerId);
                if (!ok) {
                    throw new https_1.HttpsError("failed-precondition", "Selected practitioner is not available for public booking.");
                }
            }
        }
        const clinicTz = getTz(settings, "");
        const step = typeof settings.slotStepMinutes === "number"
            ? settings.slotStepMinutes
            : 15;
        if (!isOpeningWindows) {
            const cacheKey = [
                clinicId,
                locationId !== null && locationId !== void 0 ? locationId : "",
                practitionerId !== null && practitionerId !== void 0 ? practitionerId : "",
                appointmentTypeId !== null && appointmentTypeId !== void 0 ? appointmentTypeId : "",
                ymdFromDateInTz(rangeStartDt, clinicTz),
            ].join("|");
            const cached = slotCache.get(cacheKey);
            if (cached && Date.now() - cached.cachedAt < SLOT_CACHE_TTL_MS) {
                return { ...cached.result, cached: true };
            }
        }
        const minNotice = typeof settings.minNoticeMinutes === "number"
            ? settings.minNoticeMinutes
            : 0;
        const maxAdvanceDays = typeof settings.maxAdvanceDays === "number"
            ? settings.maxAdvanceDays
            : 365;
        const nowMs = Date.now();
        const maxMs = nowMs + maxAdvanceDays * 86400000;
        const rangeStartTs = admin.firestore.Timestamp.fromDate(rangeStartDt);
        const rangeEndTs = admin.firestore.Timestamp.fromDate(rangeEndDt);
        const closuresPromise = loadClosures(clinicId, rangeStartTs, rangeEndTs);
        const busyPromise = openingOnly
            ? loadClinicWideBusyBlocks(clinicId, rangeStartTs, rangeEndTs)
            : loadBusyBlocks(clinicId, practitionerId, rangeStartTs, rangeEndTs);
        const apptPromise = !openingOnly && practitionerId
            ? loadAppointmentsAsBlocks(clinicId, practitionerId, rangeStartTs, rangeEndTs)
            : Promise.resolve([]);
        const staffAvailPromise = practitionerId && locationId
            ? loadStaffWeeklyAvailabilityForLocation({
                clinicId,
                practitionerId,
                locationId,
            })
            : practitionerId
                ? loadStaffWeeklyAvailability({ clinicId, practitionerId })
                : Promise.resolve(null);
        const overridesPromise = practitionerId
            ? loadPractitionerOverrides(clinicId, practitionerId, rangeStartTs, rangeEndTs, locationId)
            : Promise.resolve({ unavailable: [], available: [] });
        const [closures, busy, apptBlocks, staffAvail, overrides] = await Promise.all([
            closuresPromise,
            busyPromise,
            apptPromise,
            staffAvailPromise,
            overridesPromise,
        ]);
        // Commit 52: Use only clinic timezone for slot/day logic; client tz is for display only.
        const tz = safeStr(staffAvail === null || staffAvail === void 0 ? void 0 : staffAvail.timezone) ||
            safeStr(settings.timezone) ||
            clinicTz ||
            "Europe/Prague";
        const blocked = [
            ...closures.map((c) => ({ startMs: c.fromMs, endMs: c.toMs })),
            ...busy.map((b) => ({ startMs: b.startMs, endMs: b.endMs })),
            ...apptBlocks.map((a) => ({ startMs: a.startMs, endMs: a.endMs })),
            ...overrides.unavailable,
        ];
        const clinicWeekly = normalizeWeeklyHours(settings);
        const locHours = locationId && ((_b = settings.locationOpeningHours) === null || _b === void 0 ? void 0 : _b[locationId])
            ? settings.locationOpeningHours[locationId]
            : null;
        const weekly = computeEffectiveWeeklyHours(clinicWeekly, locHours, practitionerId && (staffAvail === null || staffAvail === void 0 ? void 0 : staffAvail.weekly) ? staffAvail.weekly : null);
        const hasAnyHours = Object.values(weekly).some((arr) => Array.isArray(arr) && arr.length > 0);
        const corpSlug = safeStr(data.corpSlug) || undefined;
        const corpCode = safeStr(data.corpCode) || undefined;
        const programs = Array.isArray(settings.corporatePrograms)
            ? settings.corporatePrograms
            : [];
        const dayFlags = {};
        let corpDaySet = null;
        let corpUnlocked = false;
        let corpMode = null;
        let corpDisplayName;
        if (corpSlug) {
            const corp = findCorporate(settings, corpSlug);
            if (!corp)
                throw new https_1.HttpsError("permission-denied", "Invalid corporate link.");
            corpMode = corp.mode === "CODE_UNLOCK" ? "CODE_UNLOCK" : "LINK_ONLY";
            corpDaySet = new Set(Array.isArray(corp.days) ? corp.days.map(String) : []);
            corpUnlocked =
                corpMode === "CODE_UNLOCK" ? safeStr(corpCode).length > 0 : true;
            corpDisplayName = safeStr(corp.displayName) || undefined;
        }
        else {
            const linkOnlyDays = new Set();
            for (const p of programs) {
                const mode = p.mode === "CODE_UNLOCK" ? "CODE_UNLOCK" : "LINK_ONLY";
                if (mode === "LINK_ONLY") {
                    (Array.isArray(p.days) ? p.days : []).forEach((d) => linkOnlyDays.add(String(d)));
                }
            }
            corpDaySet = linkOnlyDays;
        }
        {
            const seen = new Set();
            for (let t = rangeStartDt.getTime(); t < rangeEndDt.getTime(); t += 86400000) {
                const dt = new Date(t);
                const ymd = ymdFromDateInTz(dt, tz);
                if (seen.has(ymd))
                    continue;
                seen.add(ymd);
                if (corpSlug) {
                    const isCorp = (corpDaySet === null || corpDaySet === void 0 ? void 0 : corpDaySet.has(ymd)) === true;
                    dayFlags[ymd] = isCorp
                        ? {
                            corporateOnly: true,
                            mode: corpMode,
                            corpSlug,
                            displayName: corpDisplayName,
                        }
                        : { corporateOnly: false, mode: null };
                    continue;
                }
                const isCorp = (corpDaySet === null || corpDaySet === void 0 ? void 0 : corpDaySet.has(ymd)) === true;
                dayFlags[ymd] = isCorp
                    ? { corporateOnly: true, mode: "LINK_ONLY" }
                    : { corporateOnly: false, mode: null };
            }
        }
        if (!hasAnyHours) {
            const result = {
                ok: true,
                clinicId,
                serviceId,
                practitionerId,
                locationId: locationId || null,
                appointmentTypeId: appointmentTypeId || null,
                tz,
                stepMinutes: step,
                corporate: corpSlug
                    ? { corpSlug, mode: corpMode, unlocked: corpUnlocked }
                    : null,
                weeklyHours: weekly,
                dayFlags,
                slots: [],
                openingOnly,
                staffAvailabilityApplied: Boolean(practitionerId && (staffAvail === null || staffAvail === void 0 ? void 0 : staffAvail.weekly)),
                appointmentsApplied: Boolean(!openingOnly && practitionerId),
            };
            if (!isOpeningWindows) {
                const cacheKey = [
                    clinicId,
                    locationId !== null && locationId !== void 0 ? locationId : "",
                    practitionerId !== null && practitionerId !== void 0 ? practitionerId : "",
                    appointmentTypeId !== null && appointmentTypeId !== void 0 ? appointmentTypeId : "",
                    ymdFromDateInTz(rangeStartDt, clinicTz),
                ].join("|");
                slotCache.set(cacheKey, { result, cachedAt: Date.now() });
                evictSlotCacheIfNeeded();
            }
            return result;
        }
        const slots = [];
        for (let t = rangeStartDt.getTime(); t + step * 60000 <= rangeEndDt.getTime(); t += step * 60000) {
            const startMs = t;
            const endMs = t + step * 60000;
            if (startMs < nowMs + minNotice * 60000)
                continue;
            if (startMs > maxMs)
                continue;
            const startDt = new Date(startMs);
            const endDt = new Date(endMs);
            const ymd = ymdFromDateInTz(startDt, tz);
            if (corpSlug) {
                if (!corpDaySet.has(ymd))
                    continue;
                if (!corpUnlocked)
                    continue;
            }
            else {
                if (corpDaySet.has(ymd))
                    continue;
            }
            const dk = dayKeyFromDateInTz(startDt, tz);
            const intervals = Array.isArray(weekly[dk])
                ? weekly[dk]
                : [];
            if (!intervals.length)
                continue;
            const startHm = new Intl.DateTimeFormat("en-GB", {
                timeZone: tz,
                hour: "2-digit",
                minute: "2-digit",
                hour12: false,
            }).format(startDt);
            const endHm = new Intl.DateTimeFormat("en-GB", {
                timeZone: tz,
                hour: "2-digit",
                minute: "2-digit",
                hour12: false,
            }).format(endDt);
            const sMin = hmToMinutes(startHm);
            const eMin = hmToMinutes(endHm);
            if (!Number.isFinite(sMin) || !Number.isFinite(eMin))
                continue;
            const withinWeekly = intervals.some((it) => {
                const a = hmToMinutes(safeStr(it.start));
                const b = hmToMinutes(safeStr(it.end));
                if (!Number.isFinite(a) || !Number.isFinite(b) || b <= a)
                    return false;
                return sMin >= a && eMin <= b;
            });
            const withinOverride = slotContainedInRanges(startMs, endMs, overrides.available);
            if (!withinWeekly && !withinOverride)
                continue;
            if (overlapsAny(startMs, endMs, blocked))
                continue;
            slots.push({ startMs, endMs });
        }
        const result = {
            ok: true,
            clinicId,
            serviceId,
            practitionerId,
            locationId: locationId || null,
            appointmentTypeId: appointmentTypeId || null,
            tz,
            stepMinutes: step,
            corporate: corpSlug
                ? { corpSlug, mode: corpMode, unlocked: corpUnlocked }
                : null,
            weeklyHours: weekly,
            dayFlags,
            slots,
            openingOnly,
            staffAvailabilityApplied: Boolean(practitionerId && (staffAvail === null || staffAvail === void 0 ? void 0 : staffAvail.weekly)),
            appointmentsApplied: Boolean(!openingOnly && practitionerId),
        };
        if (!isOpeningWindows) {
            const cacheKey = [
                clinicId,
                locationId !== null && locationId !== void 0 ? locationId : "",
                practitionerId !== null && practitionerId !== void 0 ? practitionerId : "",
                appointmentTypeId !== null && appointmentTypeId !== void 0 ? appointmentTypeId : "",
                ymdFromDateInTz(rangeStartDt, clinicTz),
            ].join("|");
            slotCache.set(cacheKey, { result, cachedAt: Date.now() });
            evictSlotCacheIfNeeded();
        }
        return result;
    }
    catch (err) {
        logger_1.logger.error("listPublicSlots failed", {
            err: (_c = err === null || err === void 0 ? void 0 : err.message) !== null && _c !== void 0 ? _c : String(err),
            stack: err === null || err === void 0 ? void 0 : err.stack,
            code: err === null || err === void 0 ? void 0 : err.code,
        });
        if (err instanceof https_1.HttpsError)
            throw err;
        throw new https_1.HttpsError("internal", "listPublicSlots crashed.");
    }
});
exports.getPublicMonthAvailabilityFn = (0, https_1.onCall)({ region: "europe-west3", cors: true }, async (request) => {
    var _a, _b, _c, _d;
    try {
        // Auth optional: public booking page may call without sign-in; still return availability.
        const data = ((_a = request.data) !== null && _a !== void 0 ? _a : {});
        const clinicId = safeStr(data.clinicId);
        const practitionerId = safeStr(data.practitionerId);
        const locationId = safeStr(data.locationId) || undefined;
        const serviceId = safeStr(data.serviceId) || "default";
        if (!clinicId || !practitionerId) {
            throw new https_1.HttpsError("invalid-argument", "clinicId and practitionerId are required.");
        }
        const monthStartMs = typeof data.monthStartMs === "number" ? data.monthStartMs : 0;
        const monthEndMs = typeof data.monthEndMs === "number" ? data.monthEndMs : 0;
        if (!Number.isFinite(monthStartMs) || !Number.isFinite(monthEndMs) || monthEndMs <= monthStartMs) {
            throw new https_1.HttpsError("invalid-argument", "Invalid monthStartMs / monthEndMs.");
        }
        const monthStartDt = new Date(monthStartMs);
        const monthEndDt = new Date(monthEndMs);
        const rangeStartTs = admin.firestore.Timestamp.fromDate(monthStartDt);
        const rangeEndTs = admin.firestore.Timestamp.fromDate(monthEndDt);
        const settings = await loadPublicSettingsFromMirror(clinicId);
        const allowed = extractAllowedPractitionerIds(settings);
        if (!allowed.includes(practitionerId)) {
            throw new https_1.HttpsError("failed-precondition", "Selected practitioner is not available for public booking.");
        }
        const tz = safeStr(data.tz) || getTz(settings, "") || "Europe/Prague";
        const minNotice = typeof settings.minNoticeMinutes === "number" ? settings.minNoticeMinutes : 60;
        const maxAdvanceDays = typeof settings.maxAdvanceDays === "number" ? settings.maxAdvanceDays : 365;
        const nowMs = Date.now();
        const maxMs = nowMs + maxAdvanceDays * 86400000;
        const corpCode = safeStr(data.corpCode) || undefined;
        const programs = Array.isArray(settings.corporatePrograms) ? settings.corporatePrograms : [];
        const corpDaySet = new Set();
        for (const p of programs) {
            const mode = p.mode === "CODE_UNLOCK" ? "CODE_UNLOCK" : "LINK_ONLY";
            if (mode === "LINK_ONLY") {
                (Array.isArray(p.days) ? p.days : []).forEach((d) => corpDaySet.add(String(d)));
            }
        }
        const dayFlags = {};
        for (let t = monthStartDt.getTime(); t < monthEndDt.getTime(); t += 86400000) {
            const dt = new Date(t);
            const ymd = ymdFromDateInTz(dt, tz);
            dayFlags[ymd] = corpDaySet.has(ymd)
                ? { corporateOnly: true, mode: "LINK_ONLY" }
                : { corporateOnly: false, mode: null };
        }
        const staffAvailPromise = practitionerId && locationId
            ? loadStaffWeeklyAvailabilityForLocation({
                clinicId,
                practitionerId,
                locationId,
            })
            : practitionerId
                ? loadStaffWeeklyAvailability({ clinicId, practitionerId })
                : Promise.resolve(null);
        const overridesPromiseMonth = loadPractitionerOverrides(clinicId, practitionerId, rangeStartTs, rangeEndTs, locationId);
        const [closures, busy, apptBlocks, staffAvail, overridesMonth] = await Promise.all([
            loadClosures(clinicId, rangeStartTs, rangeEndTs),
            loadBusyBlocks(clinicId, practitionerId, rangeStartTs, rangeEndTs),
            loadAppointmentsAsBlocks(clinicId, practitionerId, rangeStartTs, rangeEndTs),
            staffAvailPromise,
            overridesPromiseMonth,
        ]);
        const blocked = [
            ...closures.map((c) => ({ startMs: c.fromMs, endMs: c.toMs })),
            ...busy.map((b) => ({ startMs: b.startMs, endMs: b.endMs })),
            ...apptBlocks.map((a) => ({ startMs: a.startMs, endMs: a.endMs })),
            ...overridesMonth.unavailable,
        ];
        const clinicWeekly = normalizeWeeklyHours(settings);
        const weekly = (staffAvail === null || staffAvail === void 0 ? void 0 : staffAvail.weekly)
            ? intersectWeeklyHours(clinicWeekly, staffAvail.weekly)
            : clinicWeekly;
        const days = {};
        const hourMs = 60 * 60 * 1000;
        for (let t = monthStartDt.getTime(); t + hourMs <= monthEndDt.getTime(); t += hourMs) {
            const startMs = t;
            const endMs = t + hourMs;
            if (startMs < nowMs + minNotice * 60000)
                continue;
            if (startMs > maxMs)
                continue;
            const startDt = new Date(startMs);
            const ymd = ymdFromDateInTz(startDt, tz);
            const minuteInTz = Number(new Intl.DateTimeFormat("en-GB", {
                timeZone: tz,
                minute: "2-digit",
                hour12: false,
            }).format(startDt));
            if (!Number.isFinite(minuteInTz) || minuteInTz !== 0)
                continue;
            const isCorpDay = corpDaySet.has(ymd);
            if (isCorpDay && !corpCode)
                continue;
            const dk = dayKeyFromDateInTz(startDt, tz);
            const intervals = Array.isArray(weekly[dk]) ? weekly[dk] : [];
            if (!intervals.length)
                continue;
            const startHm = new Intl.DateTimeFormat("en-GB", {
                timeZone: tz,
                hour: "2-digit",
                minute: "2-digit",
                hour12: false,
            }).format(startDt);
            const endHm = new Intl.DateTimeFormat("en-GB", {
                timeZone: tz,
                hour: "2-digit",
                minute: "2-digit",
                hour12: false,
            }).format(new Date(endMs));
            const sMin = hmToMinutes(startHm);
            const eMin = hmToMinutes(endHm);
            if (!Number.isFinite(sMin) || !Number.isFinite(eMin))
                continue;
            const withinWeekly = intervals.some((it) => {
                const a = hmToMinutes(safeStr(it.start));
                const b = hmToMinutes(safeStr(it.end));
                if (!Number.isFinite(a) || !Number.isFinite(b) || b <= a)
                    return false;
                return sMin >= a && eMin <= b;
            });
            const withinOverride = slotContainedInRanges(startMs, endMs, overridesMonth.available);
            if (!withinWeekly && !withinOverride)
                continue;
            if (overlapsAny(startMs, endMs, blocked))
                continue;
            const cur = days[ymd];
            const flag = dayFlags[ymd];
            days[ymd] = {
                count: ((_b = cur === null || cur === void 0 ? void 0 : cur.count) !== null && _b !== void 0 ? _b : 0) + 1,
                corporateOnly: (_c = flag === null || flag === void 0 ? void 0 : flag.corporateOnly) !== null && _c !== void 0 ? _c : false,
            };
        }
        return { days };
    }
    catch (err) {
        logger_1.logger.error("getPublicMonthAvailability failed", {
            err: (_d = err === null || err === void 0 ? void 0 : err.message) !== null && _d !== void 0 ? _d : String(err),
            stack: err === null || err === void 0 ? void 0 : err.stack,
            code: err === null || err === void 0 ? void 0 : err.code,
        });
        if (err instanceof https_1.HttpsError)
            throw err;
        // Return empty days so client can still show calendar without dots
        return { days: {} };
    }
});
/**
 * Returns the public booking practitioner list from the full mirror (server-side read).
 * Use this from the public booking UI instead of reading Firestore directly to avoid
 * client-side "Unexpected state" / assertion errors in the Firestore web SDK.
 *
 * Filters:
 * - locationId: returns only practitioners eligible at that location
 *   (allowedLocationIds empty/undefined = all locations, else must include locationId).
 * - serviceId / appointmentTypeId: returns only practitioners eligible for that service
 *   (serviceIdsAllowed empty/undefined = all services, else must include serviceId).
 *
 * Returns full public-safe projected fields so the UI can display rich practitioner info.
 */
exports.getPublicBookingPractitionersFn = (0, https_1.onCall)({ region: "europe-west3", cors: true }, async (request) => {
    var _a, _b, _c, _d, _e, _f;
    try {
        const clinicId = safeStr((_a = request.data) === null || _a === void 0 ? void 0 : _a.clinicId);
        if (!clinicId) {
            throw new https_1.HttpsError("invalid-argument", "clinicId is required.");
        }
        const locationId = safeStr((_b = request.data) === null || _b === void 0 ? void 0 : _b.locationId) || undefined;
        const serviceId = safeStr((_c = request.data) === null || _c === void 0 ? void 0 : _c.serviceId) ||
            safeStr((_d = request.data) === null || _d === void 0 ? void 0 : _d.appointmentTypeId) ||
            undefined;
        const { practitioners } = await loadFullMirrorExtras(clinicId);
        let list = practitioners;
        if (locationId) {
            list = list.filter((p) => {
                const ids = p.allowedLocationIds;
                if (!ids || ids.length === 0)
                    return true;
                return ids.includes(locationId);
            });
        }
        if (serviceId) {
            list = list.filter((p) => {
                const ids = p.serviceIdsAllowed;
                if (!ids || ids.length === 0)
                    return true;
                return ids.includes(serviceId);
            });
        }
        return {
            practitioners: list.map((p) => {
                var _a, _b, _c, _d, _e, _f, _g;
                return ({
                    id: p.id,
                    displayName: (_a = p.displayName) !== null && _a !== void 0 ? _a : "",
                    title: (_b = p.title) !== null && _b !== void 0 ? _b : null,
                    photoUrl: (_c = p.photoUrl) !== null && _c !== void 0 ? _c : null,
                    bio: (_d = p.bio) !== null && _d !== void 0 ? _d : null,
                    sortOrder: (_e = p.sortOrder) !== null && _e !== void 0 ? _e : 0,
                    allowedLocationIds: (_f = p.allowedLocationIds) !== null && _f !== void 0 ? _f : [],
                    serviceIdsAllowed: (_g = p.serviceIdsAllowed) !== null && _g !== void 0 ? _g : [],
                });
            }),
        };
    }
    catch (err) {
        if (err instanceof https_1.HttpsError)
            throw err;
        const msg = (_e = err === null || err === void 0 ? void 0 : err.message) !== null && _e !== void 0 ? _e : String(err);
        logger_1.logger.error("getPublicBookingPractitionersFn failed", {
            clinicId: (_f = request.data) === null || _f === void 0 ? void 0 : _f.clinicId,
            error: msg,
            code: err === null || err === void 0 ? void 0 : err.code,
        });
        return { practitioners: [] };
    }
});
/**
 * Returns the public booking locations list from the full mirror (server-side read).
 * Use from the public booking UI for the location-first selector.
 */
exports.getPublicBookingLocationsFn = (0, https_1.onCall)({ region: "europe-west3", cors: true }, async (request) => {
    var _a, _b, _c;
    try {
        const clinicId = safeStr((_a = request.data) === null || _a === void 0 ? void 0 : _a.clinicId);
        if (!clinicId) {
            throw new https_1.HttpsError("invalid-argument", "clinicId is required.");
        }
        const fullRef = db.doc(FULL_MIRROR_PATH(clinicId));
        const snap = await fullRef.get();
        if (!snap.exists || !snap.data()) {
            return { locations: [] };
        }
        const d = snap.data();
        const raw = Array.isArray(d === null || d === void 0 ? void 0 : d.locations) ? d.locations : [];
        const locations = raw.map((item) => ({
            id: safeStr(item === null || item === void 0 ? void 0 : item.id) || "",
            name: safeStr(item === null || item === void 0 ? void 0 : item.name) || safeStr(item === null || item === void 0 ? void 0 : item.id) || "",
        })).filter((x) => x.id.length > 0);
        return { locations };
    }
    catch (err) {
        if (err instanceof https_1.HttpsError)
            throw err;
        const msg = (_b = err === null || err === void 0 ? void 0 : err.message) !== null && _b !== void 0 ? _b : String(err);
        logger_1.logger.error("getPublicBookingLocationsFn failed", {
            clinicId: (_c = request.data) === null || _c === void 0 ? void 0 : _c.clinicId,
            error: msg,
            code: err === null || err === void 0 ? void 0 : err.code,
        });
        return { locations: [] };
    }
});
/**
 * Returns the public booking appointment types list from the full mirror (server-side read).
 * Use from the public booking UI for the appointment-type selector (location-first flow step 2).
 */
exports.getPublicBookingAppointmentTypesFn = (0, https_1.onCall)({ region: "europe-west3", cors: true }, async (request) => {
    var _a, _b, _c;
    try {
        const clinicId = safeStr((_a = request.data) === null || _a === void 0 ? void 0 : _a.clinicId);
        if (!clinicId) {
            throw new https_1.HttpsError("invalid-argument", "clinicId is required.");
        }
        const fullRef = db.doc(FULL_MIRROR_PATH(clinicId));
        const snap = await fullRef.get();
        if (!snap.exists || !snap.data()) {
            return { appointmentTypes: [] };
        }
        const d = snap.data();
        const raw = Array.isArray(d === null || d === void 0 ? void 0 : d.appointmentTypes) ? d.appointmentTypes : [];
        const appointmentTypes = raw.map((item) => ({
            id: safeStr(item === null || item === void 0 ? void 0 : item.id) || "",
            name: safeStr(item === null || item === void 0 ? void 0 : item.name) || safeStr(item === null || item === void 0 ? void 0 : item.id) || "",
            defaultDurationMinutes: typeof (item === null || item === void 0 ? void 0 : item.defaultDurationMinutes) === "number" ? item.defaultDurationMinutes : 30,
            description: safeStr(item === null || item === void 0 ? void 0 : item.description) || undefined,
            defaultPrice: typeof (item === null || item === void 0 ? void 0 : item.defaultPrice) === "number" ? item.defaultPrice : undefined,
            colorHex: safeStr(item === null || item === void 0 ? void 0 : item.colorHex) || undefined,
        })).filter((x) => x.id.length > 0);
        return { appointmentTypes };
    }
    catch (err) {
        if (err instanceof https_1.HttpsError)
            throw err;
        const msg = (_b = err === null || err === void 0 ? void 0 : err.message) !== null && _b !== void 0 ? _b : String(err);
        logger_1.logger.error("getPublicBookingAppointmentTypesFn failed", {
            clinicId: (_c = request.data) === null || _c === void 0 ? void 0 : _c.clinicId,
            error: msg,
            code: err === null || err === void 0 ? void 0 : err.code,
        });
        return { appointmentTypes: [] };
    }
});
/**
 * Diagnostic callable (staff only: settings.read). Returns mirror state and practitioner
 * visibility so you can see why "no clinicians" appears. Call from Flutter or Console.
 */
exports.getPublicBookingDiagnosticsFn = (0, https_1.onCall)({ region: "europe-west3", cors: true }, async (request) => {
    var _a, _b, _c, _d;
    if (!((_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid)) {
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    }
    const clinicId = safeStr((_b = request.data) === null || _b === void 0 ? void 0 : _b.clinicId);
    if (!clinicId) {
        throw new https_1.HttpsError("invalid-argument", "clinicId is required.");
    }
    await (0, permissions_1.requireClinicPermission)(db, clinicId, request.auth.uid, "settings.read");
    const fullRef = db.doc(FULL_MIRROR_PATH(clinicId));
    const mirrorSnap = await fullRef.get();
    const mirrorExists = mirrorSnap.exists && !!mirrorSnap.data();
    const mirrorData = mirrorSnap.data();
    const practitionerCountInMirror = Array.isArray(mirrorData === null || mirrorData === void 0 ? void 0 : mirrorData.practitioners)
        ? mirrorData.practitioners.length
        : 0;
    const locationCountInMirror = Array.isArray(mirrorData === null || mirrorData === void 0 ? void 0 : mirrorData.locations)
        ? mirrorData.locations.length
        : 0;
    const [practitionersSnap, membersSnap, membershipsSnap] = await Promise.all([
        db.collection(`clinics/${clinicId}/practitioners`).get(),
        db.collection(`clinics/${clinicId}/members`).get(),
        db.collection(`clinics/${clinicId}/memberships`).get(),
    ]);
    const memberStatusByUid = new Map();
    for (const d of membersSnap.docs) {
        const data = d.data();
        const status = ((_c = data === null || data === void 0 ? void 0 : data.status) !== null && _c !== void 0 ? _c : "").toString().toLowerCase();
        const active = data === null || data === void 0 ? void 0 : data.active;
        const s = status || (active === true ? "active" : active === false ? "inactive" : "active");
        memberStatusByUid.set(d.id, s || "active");
    }
    for (const d of membershipsSnap.docs) {
        if (!memberStatusByUid.has(d.id)) {
            const data = d.data();
            const status = ((_d = data === null || data === void 0 ? void 0 : data.status) !== null && _d !== void 0 ? _d : "").toString().toLowerCase();
            const active = data === null || data === void 0 ? void 0 : data.active;
            const s = status || (active === true ? "active" : active === false ? "inactive" : "active");
            memberStatusByUid.set(d.id, s || "active");
        }
    }
    const practitionersInClinic = practitionersSnap.docs.map((d) => {
        var _a;
        const data = d.data();
        const membershipStatus = (_a = memberStatusByUid.get(d.id)) !== null && _a !== void 0 ? _a : "none";
        const membershipActive = membershipStatus === "none" || membershipStatus === "active";
        return {
            id: d.id,
            showInPublicBooking: (data === null || data === void 0 ? void 0 : data.showInPublicBooking) === true,
            active: (data === null || data === void 0 ? void 0 : data.active) !== false,
            activeForBooking: (data === null || data === void 0 ? void 0 : data.activeForBooking) !== false,
            membershipStatus,
            membershipActive,
        };
    });
    const withVisibility = practitionersInClinic.filter((p) => p.showInPublicBooking).length;
    const withVisibilityButInactiveMembership = practitionersInClinic.filter((p) => p.showInPublicBooking && !p.membershipActive).length;
    let hint;
    if (practitionerCountInMirror === 0 && withVisibility > 0) {
        hint =
            withVisibilityButInactiveMembership > 0
                ? `${withVisibilityButInactiveMembership} practitioner(s) have showInPublicBooking but inactive/suspended membership. Set membership to Active in Settings → Team, then re-save Public booking.`
                : "Mirror has 0 practitioners but some have showInPublicBooking. Re-save Settings → Public booking to rebuild the mirror.";
    }
    else if (practitionerCountInMirror === 0 && withVisibility === 0) {
        hint =
            "No practitioners have showInPublicBooking: true. Turn ON in Settings → Public booking and Save.";
    }
    return {
        mirrorExists,
        practitionerCountInMirror,
        locationCountInMirror,
        practitionersInClinicCount: practitionersInClinic.length,
        practitionersWithPublicVisibility: withVisibility,
        practitioners: practitionersInClinic,
        hint,
    };
});
//# sourceMappingURL=listPublicSlots.js.map