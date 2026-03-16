"use strict";
/**
 * Commit 16: Projection builder (private → public mirror).
 * Writes clinics/{clinicId}/public/config/publicBooking/config from
 * clinics/{clinicId}/settings/publicBooking and clinic doc.
 * Event-driven (trigger); no callables write /public/** except optional manual rebuild.
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
exports.onLocationWritePublicBookingConfigProjection = exports.projectionsRebuildPublicBookingConfig = exports.onPublicBookingSettingsWriteProjection = void 0;
exports.buildPublicBookingConfigV1 = buildPublicBookingConfigV1;
exports.writePublicBookingConfigProjection = writePublicBookingConfigProjection;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/v2/firestore");
const https_1 = require("firebase-functions/v2/https");
const https_2 = require("firebase-functions/v2/https");
const logger_1 = require("firebase-functions/logger");
const permissions_1 = require("../permissions");
const hash_1 = require("./hash");
const paths_1 = require("./paths");
const questionnaireTemplates_1 = require("../questionnaires/questionnaireTemplates");
const DAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
const BOOKING_RULES_DEFAULTS = {
    slotStepMinutes: 15,
    minNoticeMinutes: 0,
    maxAdvanceDays: 90,
    allowNewPatients: true,
    requireEmail: true,
    requirePhone: false,
    cancellationPolicyHours: 24,
    onlineBookingEnabled: true,
};
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
function takeIntervals(list) {
    const out = [];
    if (!Array.isArray(list))
        return out;
    for (const it of list) {
        if (!isObj(it))
            continue;
        const start = safeStr(it.start);
        const end = safeStr(it.end);
        if (start && end)
            out.push({ start, end });
    }
    return out;
}
function normalizeWeeklyHours(settings) {
    const out = {
        mon: [], tue: [], wed: [], thu: [], fri: [], sat: [], sun: [],
    };
    const wh = settings.weeklyHours;
    if (!isObj(wh))
        return out;
    for (const day of DAY_KEYS) {
        const v = wh[day];
        out[day] = Array.isArray(v) ? takeIntervals(v) : [];
    }
    return out;
}
function buildBookingRules(settings) {
    const r = { ...BOOKING_RULES_DEFAULTS };
    if (safeNum(settings.slotStepMinutes, NaN) >= 0)
        r.slotStepMinutes = Number(settings.slotStepMinutes);
    if (safeNum(settings.minNoticeMinutes, NaN) >= 0)
        r.minNoticeMinutes = Number(settings.minNoticeMinutes);
    if (safeNum(settings.maxAdvanceDays, NaN) >= 0)
        r.maxAdvanceDays = Number(settings.maxAdvanceDays);
    if (settings.allowNewPatients === true || settings.allowNewPatients === false)
        r.allowNewPatients = settings.allowNewPatients;
    if (settings.requireEmail === true || settings.requireEmail === false)
        r.requireEmail = settings.requireEmail;
    if (settings.requirePhone === true || settings.requirePhone === false)
        r.requirePhone = settings.requirePhone;
    if (safeNum(settings.cancellationPolicyHours, NaN) >= 0)
        r.cancellationPolicyHours = Number(settings.cancellationPolicyHours);
    if (settings.onlineBookingEnabled === true || settings.onlineBookingEnabled === false)
        r.onlineBookingEnabled = settings.onlineBookingEnabled;
    return r;
}
/**
 * Build the v1 public config payload (no PII). Caller sets updatedAt when writing.
 */
function normalizeLocationOpeningHours(locations) {
    var _a;
    const out = {};
    for (const loc of locations) {
        const wh = (_a = loc.data) === null || _a === void 0 ? void 0 : _a.weeklyHours;
        if (!isObj(wh))
            continue;
        const normalized = {};
        for (const day of DAY_KEYS) {
            const v = wh[day];
            normalized[day] = Array.isArray(v) ? takeIntervals(v) : [];
        }
        const hasAny = DAY_KEYS.some((d) => { var _a, _b; return ((_b = (_a = normalized[d]) === null || _a === void 0 ? void 0 : _a.length) !== null && _b !== void 0 ? _b : 0) > 0; });
        if (hasAny)
            out[loc.id] = normalized;
    }
    return out;
}
function buildPublicBookingConfigV1(args) {
    var _a, _b, _c, _d, _e;
    const settings = isObj(args.settingsDoc) ? args.settingsDoc : {};
    const clinic = isObj(args.clinicDoc) ? args.clinicDoc : {};
    const timezone = safeStr((_a = clinic.timezone) !== null && _a !== void 0 ? _a : (_b = clinic.profile) === null || _b === void 0 ? void 0 : _b.timezone) || "UTC";
    const currencyCode = safeStr((_c = clinic.currencyCode) !== null && _c !== void 0 ? _c : (_d = clinic.profile) === null || _d === void 0 ? void 0 : _d.currencyCode) || "EUR";
    const bookingRules = buildBookingRules(settings);
    bookingRules.questionnaireFlow = args.questionnaireFlow;
    const weeklyHours = normalizeWeeklyHours(settings);
    const locationOpeningHours = (_e = args.locationOpeningHours) !== null && _e !== void 0 ? _e : {};
    const payloadForHash = {
        schemaVersion: 1,
        clinicId: args.clinicId,
        source: {
            publicBookingUpdatedAt: args.settingsUpdatedAt,
            openingHoursUpdatedAt: args.settingsUpdatedAt,
            clinicUpdatedAt: args.clinicUpdatedAt,
        },
        jurisdiction: { timezone, currencyCode },
        bookingRules,
        weeklyHours,
        locationOpeningHours,
    };
    const hash = (0, hash_1.sha256Hex)(payloadForHash);
    return {
        schemaVersion: 1,
        clinicId: args.clinicId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        source: {
            publicBookingUpdatedAt: args.settingsUpdatedAt,
            openingHoursUpdatedAt: args.settingsUpdatedAt,
            clinicUpdatedAt: args.clinicUpdatedAt,
        },
        jurisdiction: { timezone, currencyCode },
        bookingRules,
        weeklyHours,
        locationOpeningHours,
        hash,
    };
}
/**
 * Write the minimal config doc. Idempotent: same inputs → same hash → same content.
 * Reads all locations for the clinic and includes locationOpeningHours in the config.
 */
async function writePublicBookingConfigProjection(clinicId, settingsSnap, clinicSnap) {
    var _a, _b, _c, _d, _e, _f;
    const db = admin.firestore();
    const settingsData = (settingsSnap === null || settingsSnap === void 0 ? void 0 : settingsSnap.exists) ? ((_a = settingsSnap.data()) !== null && _a !== void 0 ? _a : {}) : {};
    const settingsUpdatedAt = (settingsSnap === null || settingsSnap === void 0 ? void 0 : settingsSnap.exists) && (settingsSnap === null || settingsSnap === void 0 ? void 0 : settingsSnap.get("updatedAt"))
        ? settingsSnap.get("updatedAt")
        : null;
    const clinicData = (clinicSnap === null || clinicSnap === void 0 ? void 0 : clinicSnap.exists) ? ((_b = clinicSnap.data()) !== null && _b !== void 0 ? _b : {}) : {};
    const clinicUpdatedAt = (clinicSnap === null || clinicSnap === void 0 ? void 0 : clinicSnap.exists) && (clinicSnap === null || clinicSnap === void 0 ? void 0 : clinicSnap.get("updatedAt"))
        ? clinicSnap.get("updatedAt")
        : null;
    const locationsSnap = await db.collection(`clinics/${clinicId}/locations`).get();
    const locations = locationsSnap.docs.map((d) => { var _a; return ({ id: d.id, data: ((_a = d.data()) !== null && _a !== void 0 ? _a : {}) }); });
    const locationOpeningHours = normalizeLocationOpeningHours(locations);
    const questionnaireFlow = await (0, questionnaireTemplates_1.buildPublicQuestionnaireFlow)(db, clinicId, settingsData.questionnaireFlow);
    const payload = buildPublicBookingConfigV1({
        clinicId,
        settingsDoc: settingsData,
        settingsUpdatedAt,
        clinicDoc: clinicData,
        clinicUpdatedAt,
        questionnaireFlow,
        locationOpeningHours,
    });
    const ref = db.doc((0, paths_1.publicBookingConfigDocPath)(clinicId));
    await ref.set(payload, { merge: true });
    logger_1.logger.info("[projection/publicBooking] wrote config", {
        clinicId,
        hash: payload.hash,
        locationCount: Object.keys(locationOpeningHours).length,
        source: {
            publicBookingUpdatedAt: (_d = (_c = settingsUpdatedAt === null || settingsUpdatedAt === void 0 ? void 0 : settingsUpdatedAt.toMillis) === null || _c === void 0 ? void 0 : _c.call(settingsUpdatedAt)) !== null && _d !== void 0 ? _d : null,
            clinicUpdatedAt: (_f = (_e = clinicUpdatedAt === null || clinicUpdatedAt === void 0 ? void 0 : clinicUpdatedAt.toMillis) === null || _e === void 0 ? void 0 : _e.call(clinicUpdatedAt)) !== null && _f !== void 0 ? _f : null,
        },
    });
}
/**
 * Trigger: on write to clinics/{clinicId}/settings/publicBooking.
 * Writes minimal public config to .../public/config/publicBooking/config.
 * On delete: write defaults with source.publicBookingUpdatedAt = null.
 *
 * Data flow (opening hours correlation):
 * - Opening hours UI saves via settings.updatePublicBookingConfig (or updateClinicWeeklyHoursFn wrapper) → settings/publicBooking.
 * - This trigger runs and writes weeklyHours (and booking rules) to public/config/publicBooking/config.
 * - listPublicSlotsFn and clinician calendar read only from that config; public booking slots use it too.
 * - Flutter may also call projectionsRebuildPublicBookingConfig after save for immediate sync.
 */
exports.onPublicBookingSettingsWriteProjection = (0, firestore_1.onDocumentWritten)({
    region: "europe-west3",
    document: "clinics/{clinicId}/settings/publicBooking",
}, async (event) => {
    var _a, _b, _c;
    const clinicId = safeStr((_a = event.params) === null || _a === void 0 ? void 0 : _a.clinicId);
    if (!clinicId)
        return;
    const afterSnap = (_b = event.data) === null || _b === void 0 ? void 0 : _b.after;
    const settingsSnap = afterSnap && afterSnap.exists ? afterSnap : null;
    const settingsData = settingsSnap ? ((_c = settingsSnap.data()) !== null && _c !== void 0 ? _c : {}) : {};
    const db = admin.firestore();
    const clinicSnap = await db.doc(`clinics/${clinicId}`).get();
    if (!settingsSnap && afterSnap && !afterSnap.exists) {
        await writePublicBookingConfigProjection(clinicId, null, clinicSnap);
        logger_1.logger.info("[projection/publicBooking] settings deleted, wrote defaults", { clinicId });
        return;
    }
    await writePublicBookingConfigProjection(clinicId, settingsSnap !== null && settingsSnap !== void 0 ? settingsSnap : null, clinicSnap);
});
/**
 * Manual rebuild callable. Permission: settings.write.
 * Runs the same projection once (reads settings + clinic + locations, writes public config).
 */
exports.projectionsRebuildPublicBookingConfig = (0, https_1.onCall)({ region: "europe-west3" }, async (request) => {
    var _a, _b;
    if (!((_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid)) {
        throw new https_2.HttpsError("unauthenticated", "Sign in required.");
    }
    const clinicId = safeStr((_b = request.data) === null || _b === void 0 ? void 0 : _b.clinicId);
    if (!clinicId) {
        throw new https_2.HttpsError("invalid-argument", "clinicId is required.");
    }
    const db = admin.firestore();
    await (0, permissions_1.requireClinicPermission)(db, clinicId, request.auth.uid, "settings.write");
    const [settingsSnap, clinicSnap] = await Promise.all([
        db.doc(`clinics/${clinicId}/settings/publicBooking`).get(),
        db.doc(`clinics/${clinicId}`).get(),
    ]);
    await writePublicBookingConfigProjection(clinicId, settingsSnap, clinicSnap);
    return { ok: true, clinicId };
});
/**
 * Trigger: on write to clinics/{clinicId}/locations/{locationId}.
 * Re-runs the public booking config projection so locationOpeningHours in the mirror stays in sync.
 */
exports.onLocationWritePublicBookingConfigProjection = (0, firestore_1.onDocumentWritten)({
    region: "europe-west3",
    document: "clinics/{clinicId}/locations/{locationId}",
}, async (event) => {
    var _a;
    const clinicId = safeStr((_a = event.params) === null || _a === void 0 ? void 0 : _a.clinicId);
    if (!clinicId)
        return;
    const db = admin.firestore();
    const [settingsSnap, clinicSnap] = await Promise.all([
        db.doc(`clinics/${clinicId}/settings/publicBooking`).get(),
        db.doc(`clinics/${clinicId}`).get(),
    ]);
    await writePublicBookingConfigProjection(clinicId, settingsSnap, clinicSnap);
    logger_1.logger.info("[projection/publicBooking] location write, refreshed config", { clinicId });
});
//# sourceMappingURL=publicBookingProjection.js.map