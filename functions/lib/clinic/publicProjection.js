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
exports.buildPublicBookingProjection = buildPublicBookingProjection;
// functions/src/clinic/publicProjection.ts
const admin = __importStar(require("firebase-admin"));
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
}
function safeNum(v, fallback) {
    const n = typeof v === "number" ? v : Number(v);
    return Number.isFinite(n) ? n : fallback;
}
function isObj(v) {
    return !!v && typeof v === "object" && !Array.isArray(v);
}
// ---- Time parsing/validation helpers ----
function hmToMinutes(hm) {
    const m = /^(\d{2}):(\d{2})$/.exec((hm !== null && hm !== void 0 ? hm : "").toString().trim());
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
const DAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
function initWeeklyHours() {
    return { mon: [], tue: [], wed: [], thu: [], fri: [], sat: [], sun: [] };
}
function initWeeklyHoursMeta() {
    const base = {
        corporateOnly: false,
        requiresCorporateCode: false,
        locationLabel: "",
    };
    return {
        mon: { ...base },
        tue: { ...base },
        wed: { ...base },
        thu: { ...base },
        fri: { ...base },
        sat: { ...base },
        sun: { ...base },
    };
}
function takeIntervals(list) {
    const cleaned = [];
    if (!Array.isArray(list))
        return cleaned;
    for (const it of list) {
        if (!isObj(it))
            continue;
        const start = safeStr(it.start);
        const end = safeStr(it.end);
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
    return cleaned;
}
function dayKeyFromRow(row) {
    const rawDay = safeStr(row.day) ||
        safeStr(row.dayKey) ||
        safeStr(row.weekday) ||
        safeStr(row.id);
    const dk = rawDay.toLowerCase().slice(0, 3);
    if (!DAY_KEYS.includes(dk))
        return null;
    return dk;
}
function boolish(v) {
    if (v === true)
        return true;
    if (v === false)
        return false;
    if (typeof v === "string") {
        const s = v.trim().toLowerCase();
        if (s === "true" || s === "yes" || s === "1")
            return true;
        if (s === "false" || s === "no" || s === "0")
            return false;
    }
    if (typeof v === "number") {
        if (v === 1)
            return true;
        if (v === 0)
            return false;
    }
    return null;
}
function inferCorporateMetaFromDayRow(row) {
    var _a, _b, _c, _d, _e, _f;
    const corporateOnlyRaw = (_c = (_b = (_a = boolish(row.corporateOnly)) !== null && _a !== void 0 ? _a : boolish(row.corporateDay)) !== null && _b !== void 0 ? _b : boolish(row.corporate_only)) !== null && _c !== void 0 ? _c : null;
    const corporateObj = isObj(row.corporate) ? row.corporate : null;
    const corporateOnlyNested = corporateObj
        ? ((_e = (_d = boolish(corporateObj.corporateOnly)) !== null && _d !== void 0 ? _d : boolish(corporateObj.enabled)) !== null && _e !== void 0 ? _e : null)
        : null;
    const corporateOnly = ((_f = corporateOnlyRaw !== null && corporateOnlyRaw !== void 0 ? corporateOnlyRaw : corporateOnlyNested) !== null && _f !== void 0 ? _f : false) === true;
    const code = safeStr(row.corporateCode) ||
        safeStr(row.code) ||
        (corporateObj
            ? safeStr(corporateObj.code) || safeStr(corporateObj.corporateCode)
            : "");
    const locationLabel = safeStr(row.locationLabel) ||
        safeStr(row.location) ||
        (corporateObj
            ? safeStr(corporateObj.locationLabel) || safeStr(corporateObj.location)
            : "");
    const requiresCorporateCode = corporateOnly && code.trim().length > 0;
    return {
        corporateOnly,
        requiresCorporateCode,
        locationLabel,
    };
}
function inferCorporateMetaFromOpeningHoursDayList(openingHoursDaysArr) {
    var _a, _b, _c;
    const meta = initWeeklyHoursMeta();
    if (!Array.isArray(openingHoursDaysArr))
        return meta;
    for (const row of openingHoursDaysArr) {
        if (!isObj(row))
            continue;
        const dk = dayKeyFromRow(row);
        if (!dk)
            continue;
        const inferred = inferCorporateMetaFromDayRow(row);
        meta[dk] = {
            corporateOnly: (_a = inferred.corporateOnly) !== null && _a !== void 0 ? _a : meta[dk].corporateOnly,
            requiresCorporateCode: (_b = inferred.requiresCorporateCode) !== null && _b !== void 0 ? _b : meta[dk].requiresCorporateCode,
            locationLabel: (_c = inferred.locationLabel) !== null && _c !== void 0 ? _c : meta[dk].locationLabel,
        };
    }
    return meta;
}
function mergeMeta(target, patch) {
    var _a, _b;
    const out = { ...target };
    for (const day of DAY_KEYS) {
        const p = patch[day];
        if (!isObj(p))
            continue;
        out[day] = {
            corporateOnly: (_a = boolish(p.corporateOnly)) !== null && _a !== void 0 ? _a : out[day].corporateOnly,
            requiresCorporateCode: (_b = boolish(p.requiresCorporateCode)) !== null && _b !== void 0 ? _b : out[day].requiresCorporateCode,
            locationLabel: safeStr(p.locationLabel) || out[day].locationLabel,
        };
    }
    return out;
}
function normalizeWeeklyHoursFromSettings(settings) {
    const out = initWeeklyHours();
    // 1) Canonical: settings.weeklyHours
    if (isObj(settings.weeklyHours)) {
        for (const day of DAY_KEYS) {
            const v = settings.weeklyHours[day];
            if (Array.isArray(v))
                out[day] = takeIntervals(v);
            else
                out[day] = [];
        }
        return out;
    }
    // 2) Legacy: settings.openingHours
    const oh = settings.openingHours;
    if (!isObj(oh))
        return out;
    // 2a) openingHours.{mon..sun} = [{start,end}]
    let matchedKeyMap = false;
    for (const day of DAY_KEYS) {
        const v = oh[day];
        if (Array.isArray(v)) {
            matchedKeyMap = true;
            out[day] = takeIntervals(v);
        }
    }
    if (matchedKeyMap)
        return out;
    // 2b) openingHours.days[]
    const daysArr = oh.days;
    if (!Array.isArray(daysArr))
        return out;
    for (const row of daysArr) {
        if (!isObj(row))
            continue;
        const dk = dayKeyFromRow(row);
        if (!dk)
            continue;
        const openFlag = row.open === true ||
            row.isOpen === true ||
            row.closed === false ||
            row.isClosed === false;
        const closedFlag = row.closed === true ||
            row.isClosed === true ||
            row.open === false ||
            row.isOpen === false;
        if (closedFlag) {
            out[dk] = [];
            continue;
        }
        const intervals = (Array.isArray(row.intervals) && row.intervals) ||
            (Array.isArray(row.windows) && row.windows) ||
            (Array.isArray(row.ranges) && row.ranges) ||
            (safeStr(row.start) && safeStr(row.end)
                ? [{ start: row.start, end: row.end }]
                : []) ||
            [];
        const cleaned = takeIntervals(intervals);
        if (openFlag)
            out[dk] = cleaned;
        else if (cleaned.length > 0)
            out[dk] = cleaned;
    }
    return out;
}
function normalizeWeeklyHoursMetaFromSettings(settings) {
    let meta = initWeeklyHoursMeta();
    // 1) Canonical meta: settings.weeklyHoursMeta
    if (isObj(settings.weeklyHoursMeta)) {
        meta = mergeMeta(meta, settings.weeklyHoursMeta);
    }
    // 2) Legacy: settings.openingHours.days[]
    const oh = settings.openingHours;
    if (isObj(oh) && Array.isArray(oh.days)) {
        const inferred = inferCorporateMetaFromOpeningHoursDayList(oh.days);
        meta = mergeMeta(meta, inferred);
    }
    return meta;
}
function weeklyHoursToOpeningHours(weeklyHours) {
    const days = DAY_KEYS.map((day) => {
        var _a;
        const intervals = (_a = weeklyHours[day]) !== null && _a !== void 0 ? _a : [];
        if (intervals.length === 0) {
            return { day, open: false, start: "", end: "" };
        }
        return {
            day,
            open: true,
            start: intervals[0].start,
            end: intervals[0].end,
        };
    });
    return {
        weekStart: "mon",
        daysOrder: "mon",
        days,
    };
}
// --------------------
// Practitioner helpers
// --------------------
function normalizeMembershipStatus(m) {
    const s = safeStr(m.status).toLowerCase();
    if (s)
        return s;
    // Back-compat: no status => infer from active bool (or default active)
    if ("active" in m)
        return m.active === true ? "active" : "inactive";
    return "active"; // missing active treated as active historically
}
function isActiveMembership(m) {
    const status = normalizeMembershipStatus(m);
    return status === "active";
}
function normalizePractitionerDisplayName(pract, membership) {
    const dn = safeStr(pract.displayName) ||
        safeStr(pract.name) ||
        safeStr(membership === null || membership === void 0 ? void 0 : membership.displayName) ||
        safeStr(membership === null || membership === void 0 ? void 0 : membership.name) ||
        "Practitioner";
    return dn;
}
function normalizeServiceIdsAllowed(pract) {
    var _a, _b;
    const raw = (_b = (_a = pract.serviceIdsAllowed) !== null && _a !== void 0 ? _a : pract.allowedServiceIds) !== null && _b !== void 0 ? _b : pract.serviceIds;
    if (!Array.isArray(raw))
        return undefined;
    const cleaned = raw.map((x) => safeStr(x)).filter((x) => !!x);
    return cleaned.length ? cleaned : undefined;
}
function normalizeSortOrder(pract) {
    const n = safeNum(pract.sortOrder, NaN) ||
        safeNum(pract.order, NaN) ||
        safeNum(pract.rank, NaN) ||
        NaN;
    return Number.isFinite(n) ? n : undefined;
}
function isPractitionerActiveForBooking(pract) {
    const v = boolish(pract.activeForBooking);
    if (v === null)
        return true;
    return v === true;
}
function isPractitionerActive(pract) {
    const v = boolish(pract.active);
    if (v === null)
        return true;
    return v === true;
}
/**
 * Membership is OPTIONAL:
 * - If membership exists and is NOT active -> exclude
 * - If membership does not exist -> still include (so public booking works)
 */
function buildPublicPractitioners(args) {
    var _a, _b;
    const memberById = new Map();
    for (const m of (_a = args.memberships) !== null && _a !== void 0 ? _a : []) {
        if (!m || !safeStr(m.id))
            continue;
        memberById.set(safeStr(m.id), isObj(m.data) ? m.data : {});
    }
    const out = [];
    for (const p of (_b = args.practitioners) !== null && _b !== void 0 ? _b : []) {
        const uid = safeStr(p === null || p === void 0 ? void 0 : p.id);
        if (!uid)
            continue;
        const pData = isObj(p.data) ? p.data : {};
        const mem = memberById.get(uid); // may be undefined
        if (mem && !isActiveMembership(mem))
            continue;
        if (!isPractitionerActive(pData))
            continue;
        if (!isPractitionerActiveForBooking(pData))
            continue;
        const proj = {
            id: uid,
            displayName: normalizePractitionerDisplayName(pData, mem),
        };
        const serviceIdsAllowed = normalizeServiceIdsAllowed(pData);
        if (serviceIdsAllowed && serviceIdsAllowed.length) {
            proj.serviceIdsAllowed = serviceIdsAllowed;
        }
        const sortOrder = normalizeSortOrder(pData);
        if (typeof sortOrder === "number" && Number.isFinite(sortOrder)) {
            proj.sortOrder = sortOrder;
        }
        out.push(proj);
    }
    out.sort((a, b) => {
        var _a, _b, _c, _d;
        const ao = (_a = a.sortOrder) !== null && _a !== void 0 ? _a : 999999;
        const bo = (_b = b.sortOrder) !== null && _b !== void 0 ? _b : 999999;
        if (ao !== bo)
            return ao - bo;
        return ((_c = a.displayName) !== null && _c !== void 0 ? _c : "").localeCompare((_d = b.displayName) !== null && _d !== void 0 ? _d : "");
    });
    return out;
}
function readClinicProfileLike(clinicDoc) {
    const profile = isObj(clinicDoc.profile) ? clinicDoc.profile : {};
    const pick = (k) => {
        if (clinicDoc[k] !== undefined && clinicDoc[k] !== null)
            return clinicDoc[k];
        if (profile[k] !== undefined && profile[k] !== null)
            return profile[k];
        return null;
    };
    return {
        phone: pick("phone"),
        email: pick("email"),
        websiteUrl: pick("websiteUrl"),
        landingUrl: pick("landingUrl"),
        whatsapp: pick("whatsapp"),
    };
}
function buildPublicBookingProjection(args) {
    var _a, _b, _c;
    const now = admin.firestore.FieldValue.serverTimestamp();
    const settings = isObj(args.publicBookingSettingsDoc)
        ? args.publicBookingSettingsDoc
        : {};
    const bookingRules = isObj(settings.bookingRules) ? settings.bookingRules : {};
    const bookingStructure = isObj(settings.bookingStructure)
        ? settings.bookingStructure
        : {};
    const slotMinutes = safeNum(bookingStructure.publicSlotMinutes, NaN) ||
        safeNum(bookingStructure.slotMinutes, NaN) ||
        safeNum(bookingStructure.slotStepMinutes, NaN) ||
        60;
    const weeklyHours = normalizeWeeklyHoursFromSettings(settings);
    const weeklyHoursMeta = normalizeWeeklyHoursMetaFromSettings(settings);
    const openingHours = weeklyHoursToOpeningHours(weeklyHours);
    const services = ((_a = args.services) !== null && _a !== void 0 ? _a : []).map((s) => {
        var _a, _b, _c;
        const d = isObj(s.data) ? s.data : {};
        const minutes = safeNum(d.minutes, NaN) ||
            safeNum(d.defaultMinutes, NaN) ||
            safeNum(d.durationMinutes, NaN) ||
            30;
        const price = (_c = (_b = (_a = d.price) !== null && _a !== void 0 ? _a : d.defaultFee) !== null && _b !== void 0 ? _b : d.fee) !== null && _c !== void 0 ? _c : null;
        return {
            id: s.id,
            name: safeStr(d.name),
            minutes,
            price,
            description: safeStr(d.description),
        };
    });
    const practitioners = buildPublicPractitioners({
        practitioners: (_b = args.practitioners) !== null && _b !== void 0 ? _b : [],
        memberships: (_c = args.memberships) !== null && _c !== void 0 ? _c : [],
    });
    const clinicDoc = isObj(args.clinicDoc) ? args.clinicDoc : {};
    const c = readClinicProfileLike(clinicDoc);
    const contact = {
        landingUrl: safeStr(c.landingUrl),
        websiteUrl: safeStr(c.websiteUrl),
        whatsapp: safeStr(c.whatsapp),
        email: safeStr(c.email),
        phone: safeStr(c.phone),
    };
    return {
        clinicId: safeStr(args.clinicId),
        clinicName: safeStr(args.clinicName) || "Clinic",
        logoUrl: safeStr(args.logoUrl),
        contact,
        weeklyHours,
        weeklyHoursMeta,
        openingHours,
        bookingRules,
        slotMinutes,
        services,
        practitioners,
        updatedAt: now,
    };
}
//# sourceMappingURL=publicProjection.js.map