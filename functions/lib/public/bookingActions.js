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
exports.rescheduleBookingWithToken = exports.cancelBookingWithToken = exports.getManageContext = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const firebase_functions_1 = require("firebase-functions");
const rateLimit_1 = require("./rateLimit");
function safeStr(v) {
    return typeof v === "string" ? v.trim() : "";
}
function mustBeJson(req) {
    var _a, _b, _c;
    const ct = safeStr((_b = (_a = req.headers) === null || _a === void 0 ? void 0 : _a["content-type"]) !== null && _b !== void 0 ? _b : (_c = req.headers) === null || _c === void 0 ? void 0 : _c["Content-Type"]);
    if (!ct.toLowerCase().includes("application/json")) {
        throw new https_1.HttpsError("invalid-argument", "Content-Type must be application/json.");
    }
}
function parseMillis(label, ms) {
    if (typeof ms !== "number" || !Number.isFinite(ms) || ms <= 0) {
        throw new https_1.HttpsError("invalid-argument", `Invalid ${label}Ms.`);
    }
    const d = new Date(ms);
    if (Number.isNaN(d.getTime()))
        throw new https_1.HttpsError("invalid-argument", `Invalid ${label}Ms.`);
    return admin.firestore.Timestamp.fromDate(d);
}
function isObj(v) {
    return !!v && typeof v === "object" && !Array.isArray(v);
}
const DAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
function weekdayKeyForMillis(ms, tz) {
    var _a;
    // Uses runtime tz conversion (Node supports Intl with timeZone)
    const short = new Intl.DateTimeFormat("en-US", { weekday: "short", timeZone: tz }).format(new Date(ms));
    const k = short.toLowerCase().slice(0, 3);
    if (DAY_KEYS.includes(k))
        return k;
    // Fallback: assume UTC mapping (worst-case)
    const wd = new Date(ms).getUTCDay(); // 0=Sun..6=Sat
    const map = { 0: "sun", 1: "mon", 2: "tue", 3: "wed", 4: "thu", 5: "fri", 6: "sat" };
    return (_a = map[wd]) !== null && _a !== void 0 ? _a : "mon";
}
function settingsRef(db, clinicId) {
    return db.doc(`clinics/${clinicId}/settings/publicBooking`);
}
/**
 * Timezone source:
 * - Canonical is clinics/{clinicId}/settings/publicBooking.timezone
 * - Fallback to Europe/Prague if missing
 */
async function readClinicTimezone(db, clinicId) {
    const snap = await settingsRef(db, clinicId).get();
    const d = snap.exists ? snap.data() : {};
    return safeStr(d === null || d === void 0 ? void 0 : d.timezone) || "Europe/Prague";
}
function formatStartTimeLocal(params) {
    var _a;
    const d = params.startAt.toDate();
    const fmt = new Intl.DateTimeFormat((_a = params.locale) !== null && _a !== void 0 ? _a : "en-US", {
        weekday: "short",
        day: "2-digit",
        month: "short",
        year: "numeric",
        hour: "2-digit",
        minute: "2-digit",
        hour12: false,
        timeZone: params.clinicTz,
    });
    return fmt.format(d);
}
function fmtGoogleUtc(ts) {
    // Google expects UTC format: YYYYMMDDTHHmmssZ
    return ts
        .toDate()
        .toISOString()
        .replace(/[-:]/g, "")
        .replace(/\.\d{3}Z$/, "Z");
}
function buildGoogleCalendarUrl(params) {
    var _a, _b;
    const qs = new URLSearchParams({
        action: "TEMPLATE",
        text: params.title,
        dates: `${fmtGoogleUtc(params.startAt)}/${fmtGoogleUtc(params.endAt)}`,
        details: (_a = params.details) !== null && _a !== void 0 ? _a : "",
        location: (_b = params.location) !== null && _b !== void 0 ? _b : "",
    });
    return `https://www.google.com/calendar/render?${qs.toString()}`;
}
/**
 * Read corporate-only rules for a specific weekday from canonical settings.
 * We support a few shapes:
 * - openingHours.days[] where index 0..6 = Mon..Sun, or each item has day/dayKey
 * - openingHours.{mon..sun} where each has corporateOnly/corporateCode (rare)
 */
function getCorporateRuleForDay(settingsData, dayKey) {
    const openingHours = settingsData === null || settingsData === void 0 ? void 0 : settingsData.openingHours;
    let corporateOnly = false;
    let corporateCode = "";
    // Shape A: openingHours.days[]
    const days = openingHours === null || openingHours === void 0 ? void 0 : openingHours.days;
    if (Array.isArray(days) && days.length >= 7) {
        // Try by explicit key first
        const match = days.find((d) => safeStr(d === null || d === void 0 ? void 0 : d.day).toLowerCase() === dayKey || safeStr(d === null || d === void 0 ? void 0 : d.dayKey).toLowerCase() === dayKey);
        const row = match !== null && match !== void 0 ? match : days[DAY_KEYS.indexOf(dayKey)];
        if (row) {
            corporateOnly = (row === null || row === void 0 ? void 0 : row.corporateOnly) === true;
            corporateCode = safeStr(row === null || row === void 0 ? void 0 : row.corporateCode);
            return { corporateOnly, corporateCode };
        }
    }
    // Shape B: openingHours.{mon..sun}
    if (isObj(openingHours) && isObj(openingHours[dayKey])) {
        const row = openingHours[dayKey];
        corporateOnly = (row === null || row === void 0 ? void 0 : row.corporateOnly) === true;
        corporateCode = safeStr(row === null || row === void 0 ? void 0 : row.corporateCode);
        return { corporateOnly, corporateCode };
    }
    return { corporateOnly: false, corporateCode: "" };
}
/**
 * Corporate enforcement for RESCHEDULE:
 * - If target day is corporate-only, reschedule is allowed only if the appointment is already corporate-authorized.
 * - If a corporate code is configured on that day, the appointment must carry the matching code (case-insensitive).
 *
 * Where do we read "used code" from?
 * We support multiple legacy shapes on appointment:
 * - appointment.corporate.corporateCodeUsed
 * - appointment.corporateCodeUsed
 * - appointment.corporateCode
 */
function assertCorporateRescheduleAllowed(params) {
    var _a, _b;
    const { clinicTz, settingsData, newStartAt, appointmentData } = params;
    const dayKey = weekdayKeyForMillis(newStartAt.toMillis(), clinicTz);
    const rule = getCorporateRuleForDay(settingsData, dayKey);
    if (!rule.corporateOnly)
        return;
    const apptCorporateOnly = ((_a = appointmentData === null || appointmentData === void 0 ? void 0 : appointmentData.corporate) === null || _a === void 0 ? void 0 : _a.corporateOnly) === true ||
        (appointmentData === null || appointmentData === void 0 ? void 0 : appointmentData.corporateOnly) === true;
    // If the day is corporate-only, the appointment must be corporate-authorized.
    if (!apptSnapCorporateAllowed(apptCorporateOnly)) {
        throw new https_1.HttpsError("permission-denied", "This day is reserved for corporate bookings.");
    }
    const used = safeStr((_b = appointmentData === null || appointmentData === void 0 ? void 0 : appointmentData.corporate) === null || _b === void 0 ? void 0 : _b.corporateCodeUsed) ||
        safeStr(appointmentData === null || appointmentData === void 0 ? void 0 : appointmentData.corporateCodeUsed) ||
        safeStr(appointmentData === null || appointmentData === void 0 ? void 0 : appointmentData.corporateCode);
    const required = safeStr(rule.corporateCode);
    // If settings require a code, enforce exact (case-insensitive) match.
    if (required) {
        if (!used) {
            throw new https_1.HttpsError("permission-denied", "A corporate booking code is required for this day.");
        }
        if (used.toLowerCase() !== required.toLowerCase()) {
            throw new https_1.HttpsError("permission-denied", "Invalid corporate booking code for this day.");
        }
    }
}
function apptSnapCorporateAllowed(apptCorporateOnly) {
    return apptCorporateOnly === true;
}
async function assertNoClosureOverlap(params) {
    const { db, clinicId, startAt, endAt } = params;
    const snap = await db
        .collection(`clinics/${clinicId}/closures`)
        .where("active", "==", true)
        .where("fromAt", "<", endAt)
        .get();
    for (const doc of snap.docs) {
        const data = doc.data();
        const fromAt = data === null || data === void 0 ? void 0 : data.fromAt;
        const toAt = data === null || data === void 0 ? void 0 : data.toAt;
        if (!fromAt || !toAt)
            continue;
        const overlaps = startAt.toMillis() < toAt.toMillis() && endAt.toMillis() > fromAt.toMillis();
        if (overlaps) {
            throw new https_1.HttpsError("failed-precondition", "Requested time overlaps a clinic closure.", {
                closureId: doc.id,
            });
        }
    }
}
async function assertNoApptOverlap(params) {
    const { db, clinicId, practitionerId, startAt, endAt, excludeAppointmentId } = params;
    const snap = await db
        .collection(`clinics/${clinicId}/appointments`)
        .where("practitionerId", "==", practitionerId)
        .where("status", "==", "booked")
        .where("startAt", "<", endAt)
        .get();
    for (const doc of snap.docs) {
        if (doc.id === excludeAppointmentId)
            continue;
        const d = doc.data();
        const s = d === null || d === void 0 ? void 0 : d.startAt;
        const e = d === null || d === void 0 ? void 0 : d.endAt;
        if (!s || !e)
            continue;
        const overlaps = startAt.toMillis() < e.toMillis() && endAt.toMillis() > s.toMillis();
        if (overlaps)
            throw new https_1.HttpsError("failed-precondition", "Requested time overlaps an existing booking.");
    }
}
async function readValidToken(db, clinicId, tokenId) {
    const ref = db.collection("clinics").doc(clinicId).collection("bookingActions").doc(tokenId);
    const snap = await ref.get();
    if (!snap.exists)
        throw new https_1.HttpsError("permission-denied", "Invalid or expired link.");
    const d = snap.data();
    const expiresAt = d === null || d === void 0 ? void 0 : d.expiresAt;
    if (!expiresAt || expiresAt.toMillis() <= Date.now()) {
        throw new https_1.HttpsError("permission-denied", "This link has expired.");
    }
    const appointmentId = safeStr(d === null || d === void 0 ? void 0 : d.appointmentId);
    if (!appointmentId)
        throw new https_1.HttpsError("permission-denied", "Invalid or expired link.");
    return { ref, token: d, appointmentId };
}
function busyBlockRef(db, clinicId, appointmentId) {
    return db.doc(`clinics/${clinicId}/public/availability/blocks/${appointmentId}`);
}
// WhatsApp contact link (clinic-specific later if you want)
const DEFAULT_WHATSAPP_URL = "https://wa.me/+6421707687";
exports.getManageContext = (0, https_1.onRequest)({ region: "europe-west3", cors: true, timeoutSeconds: 30 }, async (req, res) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q, _r, _s, _t, _u, _v;
    try {
        if (req.method !== "POST")
            return void res.status(405).json({ ok: false, error: "method-not-allowed" });
        mustBeJson(req);
        const clinicId = safeStr((_a = req.body) === null || _a === void 0 ? void 0 : _a.clinicId);
        const tokenId = safeStr((_b = req.body) === null || _b === void 0 ? void 0 : _b.tokenId);
        if (!clinicId || !tokenId)
            throw new https_1.HttpsError("invalid-argument", "clinicId and tokenId required.");
        const db = admin.firestore();
        await (0, rateLimit_1.enforceRateLimit)({ db, clinicId, req, cfg: { name: "getManageContext", max: 60, windowSeconds: 60 } });
        const { appointmentId } = await readValidToken(db, clinicId, tokenId);
        const apptRef = db.collection("clinics").doc(clinicId).collection("appointments").doc(appointmentId);
        const apptSnap = await apptRef.get();
        if (!apptSnap.exists)
            throw new https_1.HttpsError("failed-precondition", "Booking not found.");
        const a = apptSnap.data();
        const startAt = a === null || a === void 0 ? void 0 : a.startAt;
        const endAt = a === null || a === void 0 ? void 0 : a.endAt;
        const clinicTz = await readClinicTimezone(db, clinicId);
        const startTimeLocal = startAt ? formatStartTimeLocal({ startAt, clinicTz, locale: "en-US" }) : "";
        const clinicName = safeStr(a === null || a === void 0 ? void 0 : a.clinicName) || safeStr((_c = req.body) === null || _c === void 0 ? void 0 : _c.clinicName) || "";
        const serviceName = safeStr(a === null || a === void 0 ? void 0 : a.serviceName);
        const practitionerName = safeStr(a === null || a === void 0 ? void 0 : a.practitionerName);
        const locationName = safeStr(a === null || a === void 0 ? void 0 : a.locationName) || safeStr(a === null || a === void 0 ? void 0 : a.location) || "";
        const googleCalendarUrl = startAt && endAt
            ? buildGoogleCalendarUrl({
                title: clinicName ? `Appointment at ${clinicName}` : "Appointment",
                startAt,
                endAt,
                details: `${serviceName}${practitionerName ? ` with ${practitionerName}` : ""}`.trim(),
                location: locationName,
            })
            : "";
        res.status(200).json({
            ok: true,
            clinicId,
            appointmentId,
            clinicTimezone: clinicTz,
            appointment: {
                status: (_d = a === null || a === void 0 ? void 0 : a.status) !== null && _d !== void 0 ? _d : "",
                startMs: (_g = (_f = (_e = a === null || a === void 0 ? void 0 : a.startAt) === null || _e === void 0 ? void 0 : _e.toMillis) === null || _f === void 0 ? void 0 : _f.call(_e)) !== null && _g !== void 0 ? _g : null,
                endMs: (_k = (_j = (_h = a === null || a === void 0 ? void 0 : a.endAt) === null || _h === void 0 ? void 0 : _h.toMillis) === null || _j === void 0 ? void 0 : _j.call(_h)) !== null && _k !== void 0 ? _k : null,
                startTimeLocal,
                googleCalendarUrl,
                whatsAppUrl: DEFAULT_WHATSAPP_URL,
                patientName: (_l = a === null || a === void 0 ? void 0 : a.patientName) !== null && _l !== void 0 ? _l : "",
                serviceName,
                practitionerName,
                practitionerId: (_m = a === null || a === void 0 ? void 0 : a.practitionerId) !== null && _m !== void 0 ? _m : "",
                locationName,
                // Optional visibility for UI
                corporateOnly: (_q = (_p = (_o = a === null || a === void 0 ? void 0 : a.corporate) === null || _o === void 0 ? void 0 : _o.corporateOnly) !== null && _p !== void 0 ? _p : a === null || a === void 0 ? void 0 : a.corporateOnly) !== null && _q !== void 0 ? _q : false,
                corporateCodeUsed: (_t = (_s = (_r = a === null || a === void 0 ? void 0 : a.corporate) === null || _r === void 0 ? void 0 : _r.corporateCodeUsed) !== null && _s !== void 0 ? _s : a === null || a === void 0 ? void 0 : a.corporateCodeUsed) !== null && _t !== void 0 ? _t : null,
            },
        });
    }
    catch (err) {
        firebase_functions_1.logger.error("getManageContext failed", { err: (_u = err === null || err === void 0 ? void 0 : err.message) !== null && _u !== void 0 ? _u : String(err), code: err === null || err === void 0 ? void 0 : err.code, stack: err === null || err === void 0 ? void 0 : err.stack });
        if (err instanceof https_1.HttpsError) {
            const status = err.code === "invalid-argument"
                ? 400
                : err.code === "permission-denied"
                    ? 403
                    : err.code === "resource-exhausted"
                        ? 429
                        : 409;
            return void res.status(status).json({ ok: false, error: err.code, message: err.message, details: (_v = err.details) !== null && _v !== void 0 ? _v : null });
        }
        res.status(500).json({ ok: false, error: "internal", message: "getManageContext crashed." });
    }
});
exports.cancelBookingWithToken = (0, https_1.onRequest)({ region: "europe-west3", cors: true, timeoutSeconds: 30 }, async (req, res) => {
    var _a, _b, _c, _d;
    try {
        if (req.method !== "POST")
            return void res.status(405).json({ ok: false, error: "method-not-allowed" });
        mustBeJson(req);
        const clinicId = safeStr((_a = req.body) === null || _a === void 0 ? void 0 : _a.clinicId);
        const tokenId = safeStr((_b = req.body) === null || _b === void 0 ? void 0 : _b.tokenId);
        if (!clinicId || !tokenId)
            throw new https_1.HttpsError("invalid-argument", "clinicId and tokenId required.");
        const db = admin.firestore();
        await (0, rateLimit_1.enforceRateLimit)({ db, clinicId, req, cfg: { name: "cancelBookingWithToken", max: 30, windowSeconds: 60 } });
        const { appointmentId } = await readValidToken(db, clinicId, tokenId);
        const apptRef = db.collection("clinics").doc(clinicId).collection("appointments").doc(appointmentId);
        const blockRef = busyBlockRef(db, clinicId, appointmentId);
        await db.runTransaction(async (tx) => {
            const apptSnap = await tx.get(apptRef);
            if (!apptSnap.exists)
                throw new https_1.HttpsError("failed-precondition", "Booking not found.");
            const a = apptSnap.data();
            if ((a === null || a === void 0 ? void 0 : a.status) !== "booked")
                throw new https_1.HttpsError("failed-precondition", "Booking cannot be cancelled.");
            tx.update(apptRef, {
                status: "cancelled",
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedByUid: "public-link",
            });
            // ✅ Keep public availability mirror consistent
            tx.set(blockRef, {
                status: "cancelled",
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
        });
        res.status(200).json({ ok: true, clinicId, appointmentId });
    }
    catch (err) {
        firebase_functions_1.logger.error("cancelBookingWithToken failed", { err: (_c = err === null || err === void 0 ? void 0 : err.message) !== null && _c !== void 0 ? _c : String(err), code: err === null || err === void 0 ? void 0 : err.code, stack: err === null || err === void 0 ? void 0 : err.stack });
        if (err instanceof https_1.HttpsError) {
            const status = err.code === "invalid-argument"
                ? 400
                : err.code === "permission-denied"
                    ? 403
                    : err.code === "resource-exhausted"
                        ? 429
                        : 409;
            return void res.status(status).json({ ok: false, error: err.code, message: err.message, details: (_d = err.details) !== null && _d !== void 0 ? _d : null });
        }
        res.status(500).json({ ok: false, error: "internal", message: "cancelBookingWithToken crashed." });
    }
});
exports.rescheduleBookingWithToken = (0, https_1.onRequest)({ region: "europe-west3", cors: true, timeoutSeconds: 30 }, async (req, res) => {
    var _a, _b, _c, _d, _e, _f;
    try {
        if (req.method !== "POST")
            return void res.status(405).json({ ok: false, error: "method-not-allowed" });
        mustBeJson(req);
        const clinicId = safeStr((_a = req.body) === null || _a === void 0 ? void 0 : _a.clinicId);
        const tokenId = safeStr((_b = req.body) === null || _b === void 0 ? void 0 : _b.tokenId);
        if (!clinicId || !tokenId)
            throw new https_1.HttpsError("invalid-argument", "clinicId and tokenId required.");
        const newStartAt = parseMillis("newStart", (_c = req.body) === null || _c === void 0 ? void 0 : _c.newStartMs);
        const newEndAt = parseMillis("newEnd", (_d = req.body) === null || _d === void 0 ? void 0 : _d.newEndMs);
        if (newEndAt.toMillis() <= newStartAt.toMillis())
            throw new https_1.HttpsError("invalid-argument", "Invalid start/end.");
        const db = admin.firestore();
        await (0, rateLimit_1.enforceRateLimit)({ db, clinicId, req, cfg: { name: "rescheduleBookingWithToken", max: 30, windowSeconds: 60 } });
        const { appointmentId } = await readValidToken(db, clinicId, tokenId);
        const apptRef = db.collection("clinics").doc(clinicId).collection("appointments").doc(appointmentId);
        const blockRef = busyBlockRef(db, clinicId, appointmentId);
        // We'll read canonical settings inside the transaction to apply corporate rules consistently.
        const canonRef = settingsRef(db, clinicId);
        await db.runTransaction(async (tx) => {
            const apptSnap = await tx.get(apptRef);
            if (!apptSnap.exists)
                throw new https_1.HttpsError("failed-precondition", "Booking not found.");
            const a = apptSnap.data();
            if ((a === null || a === void 0 ? void 0 : a.status) !== "booked")
                throw new https_1.HttpsError("failed-precondition", "Booking cannot be rescheduled.");
            const practitionerId = safeStr(a === null || a === void 0 ? void 0 : a.practitionerId);
            if (!practitionerId)
                throw new https_1.HttpsError("failed-precondition", "Booking has no practitioner.");
            // ✅ Corporate-only enforcement (server-side)
            const canonSnap = await tx.get(canonRef);
            const canon = canonSnap.exists ? canonSnap.data() : {};
            const clinicTz = safeStr(canon === null || canon === void 0 ? void 0 : canon.timezone) || "Europe/Prague";
            assertCorporateRescheduleAllowed({
                clinicTz,
                settingsData: canon,
                newStartAt,
                appointmentData: a,
            });
            // Closures
            await assertNoClosureOverlap({ db, clinicId, startAt: newStartAt, endAt: newEndAt });
            // Appointment overlap check
            await assertNoApptOverlap({
                db,
                clinicId,
                practitionerId,
                startAt: newStartAt,
                endAt: newEndAt,
                excludeAppointmentId: appointmentId,
            });
            tx.update(apptRef, {
                startAt: newStartAt,
                endAt: newEndAt,
                start: newStartAt, // legacy mirrors
                end: newEndAt,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedByUid: "public-link",
            });
            // ✅ Keep public availability mirror consistent
            tx.set(blockRef, {
                startUtc: newStartAt,
                endUtc: newEndAt,
                status: "booked",
                // ✅ Canonical field used by listPublicSlots.ts
                practitionerId,
                // ✅ Optional legacy field (safe to keep during migration)
                clinicianId: practitionerId,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
        });
        res.status(200).json({
            ok: true,
            clinicId,
            appointmentId,
            newStartMs: newStartAt.toMillis(),
            newEndMs: newEndAt.toMillis(),
        });
    }
    catch (err) {
        firebase_functions_1.logger.error("rescheduleBookingWithToken failed", { err: (_e = err === null || err === void 0 ? void 0 : err.message) !== null && _e !== void 0 ? _e : String(err), code: err === null || err === void 0 ? void 0 : err.code, stack: err === null || err === void 0 ? void 0 : err.stack });
        if (err instanceof https_1.HttpsError) {
            const status = err.code === "invalid-argument"
                ? 400
                : err.code === "permission-denied"
                    ? 403
                    : err.code === "resource-exhausted"
                        ? 429
                        : 409;
            return void res.status(status).json({ ok: false, error: err.code, message: err.message, details: (_f = err.details) !== null && _f !== void 0 ? _f : null });
        }
        res.status(500).json({ ok: false, error: "internal", message: "rescheduleBookingWithToken crashed." });
    }
});
//# sourceMappingURL=bookingActions.js.map