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
exports.listPublicSlotsFn = void 0;
// functions/src/public/listPublicSlots.ts
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const logger_1 = require("firebase-functions/logger");
const rateLimit_1 = require("./rateLimit");
// ✅ Adjust this import path to match your project
// e.g. "../clinic/writePublicBookingMirror" or "../clinic/publicProjectionWriter"
const writePublicBookingMirror_1 = require("../clinic/writePublicBookingMirror");
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
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
// ✅ NEW: self-healing loader for public settings
async function loadPublicSettingsOrRebuildMirror(clinicId) {
    var _a, _b;
    const mirrorRef = db.doc(`clinics/${clinicId}/public/config/publicBooking/publicBooking`);
    const mirrorSnap = await mirrorRef.get();
    if (mirrorSnap.exists) {
        const d = ((_a = mirrorSnap.data()) !== null && _a !== void 0 ? _a : {});
        // If it looks healthy, use it.
        // (We consider it healthy if it has at least one of weeklyHours/openingHours.)
        const hasHours = (d.weeklyHours && typeof d.weeklyHours === "object") ||
            (d.openingHours && typeof d.openingHours === "object");
        if (hasHours)
            return d;
        logger_1.logger.warn("Public booking mirror exists but appears incomplete; attempting rebuild", {
            clinicId,
            hasWeeklyHours: !!d.weeklyHours,
            hasOpeningHours: !!d.openingHours,
        });
    }
    // If mirror missing OR incomplete -> rebuild from settings
    const settingsRef = db.doc(`clinics/${clinicId}/settings/publicBooking`);
    const settingsSnap = await settingsRef.get();
    if (!settingsSnap.exists) {
        throw new https_1.HttpsError("failed-precondition", "Public booking not configured (missing settings/publicBooking).");
    }
    const rawSettings = ((_b = settingsSnap.data()) !== null && _b !== void 0 ? _b : {});
    // This writes the mirror + returns the projection
    const projection = await (0, writePublicBookingMirror_1.writePublicBookingMirror)(clinicId, rawSettings);
    return (projection !== null && projection !== void 0 ? projection : {});
}
exports.listPublicSlotsFn = (0, https_1.onCall)({ region: "europe-west3", cors: true }, async (request) => {
    var _a, _b;
    try {
        const data = ((_a = request.data) !== null && _a !== void 0 ? _a : {});
        const clinicId = safeStr(data.clinicId);
        const serviceId = safeStr(data.serviceId);
        const practitionerId = safeStr(data.practitionerId);
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
        // ✅ Use self-healing settings loader
        const settings = await loadPublicSettingsOrRebuildMirror(clinicId);
        // Validate practitionerId against allowlist (only if practitionerId provided)
        if (practitionerId) {
            const allowed = extractAllowedPractitionerIds(settings);
            const ok = allowed.includes(practitionerId);
            if (!ok) {
                throw new https_1.HttpsError("failed-precondition", "Selected practitioner is not available for public booking.");
            }
        }
        const clinicTz = getTz(settings, "");
        const step = typeof settings.slotStepMinutes === "number"
            ? settings.slotStepMinutes
            : 15;
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
        const staffAvailPromise = practitionerId
            ? loadStaffWeeklyAvailability({ clinicId, practitionerId })
            : Promise.resolve(null);
        const [closures, busy, apptBlocks, staffAvail] = await Promise.all([
            closuresPromise,
            busyPromise,
            apptPromise,
            staffAvailPromise,
        ]);
        const tzOverride = safeStr(data.tz);
        const tz = tzOverride ||
            safeStr(staffAvail === null || staffAvail === void 0 ? void 0 : staffAvail.timezone) ||
            safeStr(settings.timezone) ||
            clinicTz ||
            "Europe/Prague";
        const blocked = [
            ...closures.map((c) => ({ startMs: c.fromMs, endMs: c.toMs })),
            ...busy.map((b) => ({ startMs: b.startMs, endMs: b.endMs })),
            ...apptBlocks.map((a) => ({ startMs: a.startMs, endMs: a.endMs })),
        ];
        const clinicWeekly = normalizeWeeklyHours(settings);
        const weekly = practitionerId && (staffAvail === null || staffAvail === void 0 ? void 0 : staffAvail.weekly)
            ? intersectWeeklyHours(clinicWeekly, staffAvail.weekly)
            : clinicWeekly;
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
            return {
                ok: true,
                clinicId,
                serviceId,
                practitionerId,
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
            const within = intervals.some((it) => {
                const a = hmToMinutes(safeStr(it.start));
                const b = hmToMinutes(safeStr(it.end));
                if (!Number.isFinite(a) || !Number.isFinite(b) || b <= a)
                    return false;
                return sMin >= a && eMin <= b;
            });
            if (!within)
                continue;
            if (overlapsAny(startMs, endMs, blocked))
                continue;
            slots.push({ startMs, endMs });
        }
        return {
            ok: true,
            clinicId,
            serviceId,
            practitionerId,
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
    }
    catch (err) {
        logger_1.logger.error("listPublicSlots failed", {
            err: (_b = err === null || err === void 0 ? void 0 : err.message) !== null && _b !== void 0 ? _b : String(err),
            stack: err === null || err === void 0 ? void 0 : err.stack,
            code: err === null || err === void 0 ? void 0 : err.code,
        });
        if (err instanceof https_1.HttpsError)
            throw err;
        throw new https_1.HttpsError("internal", "listPublicSlots crashed.");
    }
});
//# sourceMappingURL=listPublicSlots.js.map