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
/**
 * ✅ Option B (NO composite indexes):
 * Fetch candidates with only startUtc < rangeEnd (single-field index),
 * then filter in memory.
 *
 * Clinic-wide busy blocks (openingWindows should still respect these)
 *
 * Supports:
 *  - New: scope == "clinic"
 *  - Legacy: kind == "admin" AND practitionerId/clinicianId empty AND scope missing
 */
async function loadClinicWideBusyBlocks(clinicId, rangeStart, rangeEnd) {
    const col = db.collection(`clinics/${clinicId}/public/availability/blocks`);
    // ✅ Single-field query only (no composite index)
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
        // New schema: scope == clinic
        const isClinicScoped = scope === "clinic";
        // Legacy: admin + no practitioner assigned => treat as clinic-wide
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
/**
 * ✅ Option B (NO composite indexes):
 * Fetch candidates with only startUtc < rangeEnd (single-field index),
 * then filter in memory.
 *
 * Busy blocks:
 *  - clinic-wide blocks
 *  - practitioner blocks
 *  - legacy blocks without scope
 *
 * NOTE: if practitionerId empty, you still get clinic-wide blocks.
 */
async function loadBusyBlocks(clinicId, practitionerId, rangeStart, rangeEnd) {
    const pid = safeStr(practitionerId);
    const col = db.collection(`clinics/${clinicId}/public/availability/blocks`);
    // ✅ Single-field query only (no composite index)
    const snap = await col.where("startUtc", "<", rangeEnd).get();
    const out = [];
    for (const doc of snap.docs) {
        const d = doc.data();
        const s = d === null || d === void 0 ? void 0 : d.startUtc;
        const e = d === null || d === void 0 ? void 0 : d.endUtc;
        const status = safeStr(d === null || d === void 0 ? void 0 : d.status);
        const scope = safeStr(d === null || d === void 0 ? void 0 : d.scope); // may be missing
        const kind = safeStr(d === null || d === void 0 ? void 0 : d.kind).toLowerCase();
        const docPid = safeStr(d === null || d === void 0 ? void 0 : d.practitionerId);
        const docCid = safeStr(d === null || d === void 0 ? void 0 : d.clinicianId);
        if (!s || !e)
            continue;
        if (status === "cancelled")
            continue;
        // IMPORTANT: we should only include blocks that overlap the window
        const sMs = s.toMillis();
        const eMs = e.toMillis();
        if (!(rangeStart.toMillis() < eMs && rangeEnd.toMillis() > sMs))
            continue;
        let applies = false;
        if (scope === "clinic") {
            // Blocks everyone
            applies = true;
        }
        else if (scope === "practitioner") {
            // Applies only to the selected practitioner (if any)
            if (!pid)
                applies = false;
            else
                applies = docPid === pid || docCid === pid;
        }
        else if (!scope) {
            // Legacy documents (no scope field)
            if (kind === "admin" && !docPid && !docCid) {
                // legacy clinic-wide admin
                applies = true;
            }
            else {
                // legacy practitioner block
                if (!pid)
                    applies = false;
                else
                    applies = docPid === pid || docCid === pid;
            }
        }
        else {
            // Unknown scope values => ignore
            applies = false;
        }
        if (!applies)
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
    if (settings.weeklyHours && typeof settings.weeklyHours === "object") {
        for (const k of keys) {
            const v = settings.weeklyHours[k];
            if (Array.isArray(v))
                takeIntervals(k, v);
        }
        return out;
    }
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
                const closed = (row === null || row === void 0 ? void 0 : row.closed) === true || (row === null || row === void 0 ? void 0 : row.isClosed) === true;
                if (closed) {
                    out[dk] = [];
                    continue;
                }
                const intervals = (Array.isArray(row === null || row === void 0 ? void 0 : row.intervals) && row.intervals) ||
                    (Array.isArray(row === null || row === void 0 ? void 0 : row.windows) && row.windows) ||
                    (Array.isArray(row === null || row === void 0 ? void 0 : row.ranges) && row.ranges) ||
                    [];
                if (Array.isArray(intervals))
                    takeIntervals(dk, intervals);
            }
            return out;
        }
    }
    return out;
}
exports.listPublicSlotsFn = (0, https_1.onCall)({ region: "europe-west3", cors: true }, async (request) => {
    var _a, _b, _c;
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
        // Debug
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
        const settingsSnap = await db
            .doc(`clinics/${clinicId}/public/config/publicBooking/publicBooking`)
            .get();
        if (!settingsSnap.exists) {
            throw new https_1.HttpsError("failed-precondition", "Public booking not configured.");
        }
        const settings = ((_b = settingsSnap.data()) !== null && _b !== void 0 ? _b : {});
        // Validate practitionerId against allowlist (only if practitionerId provided)
        if (practitionerId) {
            const allowed = extractAllowedPractitionerIds(settings);
            const ok = allowed.includes(practitionerId);
            if (!ok) {
                throw new https_1.HttpsError("failed-precondition", "Selected practitioner is not available for public booking.");
            }
        }
        const tz = getTz(settings, safeStr(data.tz));
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
        // ✅ openingWindows MUST still subtract clinic-wide blocks
        const busyPromise = openingOnly
            ? loadClinicWideBusyBlocks(clinicId, rangeStartTs, rangeEndTs)
            : loadBusyBlocks(clinicId, practitionerId, rangeStartTs, rangeEndTs);
        const [closures, busy] = await Promise.all([closuresPromise, busyPromise]);
        const blocked = [
            ...closures.map((c) => ({ startMs: c.fromMs, endMs: c.toMs })),
            ...busy.map((b) => ({ startMs: b.startMs, endMs: b.endMs })),
        ];
        const weekly = normalizeWeeklyHours(settings);
        const hasAnyHours = Object.values(weekly).some((arr) => Array.isArray(arr) && arr.length > 0);
        // ---- Corporate context ----
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
        };
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
//# sourceMappingURL=listPublicSlots.js.map