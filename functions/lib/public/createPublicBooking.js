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
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.createPublicBooking = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const firebase_functions_1 = require("firebase-functions");
const crypto_1 = __importDefault(require("crypto"));
const createAppointmentInternal_1 = require("./../clinic/appointments/createAppointmentInternal");
// -------------------------------
// Helpers
// -------------------------------
function safeStr(v) {
    return typeof v === "string" ? v.trim() : "";
}
function requireNonEmpty(label, value) {
    if (!value.trim())
        throw new https_1.HttpsError("invalid-argument", `${label} is required.`);
}
function requireEmail(value) {
    const s = value.trim();
    if (!s.includes("@") || s.length < 6) {
        throw new https_1.HttpsError("invalid-argument", "patient.email is invalid.");
    }
}
function parseMillis(label, ms) {
    if (typeof ms !== "number" || !Number.isFinite(ms) || ms <= 0) {
        throw new https_1.HttpsError("invalid-argument", `Invalid ${label}Ms.`);
    }
    const d = new Date(ms);
    if (Number.isNaN(d.getTime()))
        throw new https_1.HttpsError("invalid-argument", `Invalid ${label}Ms.`);
    return d;
}
function sha256Hex(input) {
    return crypto_1.default.createHash("sha256").update(input).digest("hex");
}
function randomTokenId() {
    // URL-safe-ish token id
    return crypto_1.default.randomBytes(24).toString("base64url");
}
function mustBeJson(req) {
    var _a, _b, _c;
    const ct = safeStr((_b = (_a = req.headers) === null || _a === void 0 ? void 0 : _a["content-type"]) !== null && _b !== void 0 ? _b : (_c = req.headers) === null || _c === void 0 ? void 0 : _c["Content-Type"]);
    if (!ct.toLowerCase().includes("application/json")) {
        throw new https_1.HttpsError("invalid-argument", "Content-Type must be application/json.");
    }
}
function getTz(settings) {
    const tz = safeStr(settings.timezone);
    return tz || "Europe/Prague";
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
function hmFromDateInTz(d, tz) {
    var _a, _b, _c, _d;
    const parts = new Intl.DateTimeFormat("en-GB", {
        timeZone: tz,
        hour: "2-digit",
        minute: "2-digit",
        hour12: false,
    }).formatToParts(d);
    const hh = (_b = (_a = parts.find((p) => p.type === "hour")) === null || _a === void 0 ? void 0 : _a.value) !== null && _b !== void 0 ? _b : "00";
    const mm = (_d = (_c = parts.find((p) => p.type === "minute")) === null || _c === void 0 ? void 0 : _c.value) !== null && _d !== void 0 ? _d : "00";
    return `${hh}:${mm}`;
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
function dayKeyFromDateInTz(d, tz) {
    const weekday = new Intl.DateTimeFormat("en-US", { weekday: "short", timeZone: tz }).format(d);
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
function ensureNoticeAndHorizonOrThrow(settings, startDt) {
    const minNotice = typeof settings.minNoticeMinutes === "number" ? settings.minNoticeMinutes : 0;
    const maxDays = typeof settings.maxAdvanceDays === "number" ? settings.maxAdvanceDays : 365;
    const now = Date.now();
    const diffMin = (startDt.getTime() - now) / 60000;
    if (diffMin < minNotice) {
        throw new https_1.HttpsError("failed-precondition", `This booking requires at least ${minNotice} minutes notice.`);
    }
    const diffDays = (startDt.getTime() - now) / 86400000;
    if (diffDays > maxDays) {
        throw new https_1.HttpsError("failed-precondition", `Bookings are only allowed up to ${maxDays} days in advance.`);
    }
}
function ensureWithinOpenHoursOrThrow(settings, startDt, endDt) {
    var _a;
    const tz = getTz(settings);
    const weekly = (_a = settings.weeklyHours) !== null && _a !== void 0 ? _a : {};
    const dayKey = dayKeyFromDateInTz(startDt, tz);
    const intervals = Array.isArray(weekly[dayKey]) ? weekly[dayKey] : [];
    if (!intervals.length) {
        throw new https_1.HttpsError("failed-precondition", "Clinic is closed on that day.");
    }
    const startHm = hmFromDateInTz(startDt, tz);
    const endHm = hmFromDateInTz(endDt, tz);
    const sMin = hmToMinutes(startHm);
    const eMin = hmToMinutes(endHm);
    if (!Number.isFinite(sMin) || !Number.isFinite(eMin)) {
        throw new https_1.HttpsError("invalid-argument", "Invalid appointment time in clinic timezone.");
    }
    const ok = intervals.some((it) => {
        const a = hmToMinutes(safeStr(it.start));
        const b = hmToMinutes(safeStr(it.end));
        if (!Number.isFinite(a) || !Number.isFinite(b) || b <= a)
            return false;
        return sMin >= a && eMin <= b;
    });
    if (!ok)
        throw new https_1.HttpsError("failed-precondition", "Requested time is outside opening hours.");
}
function findCorporateProgram(settings, corpSlug) {
    var _a;
    const slug = safeStr(corpSlug).toLowerCase();
    if (!slug)
        return null;
    const list = Array.isArray(settings.corporatePrograms) ? settings.corporatePrograms : [];
    return (_a = list.find((p) => safeStr(p === null || p === void 0 ? void 0 : p.corpSlug).toLowerCase() === slug)) !== null && _a !== void 0 ? _a : null;
}
function validateCorporateAccessOrThrow(settings, startDt, serviceId, practitionerId, corpSlug, corpCode) {
    if (!corpSlug)
        return { corp: null, unlocked: false };
    const program = findCorporateProgram(settings, corpSlug);
    if (!program)
        throw new https_1.HttpsError("permission-denied", "Invalid corporate link.");
    const tz = getTz(settings);
    const ymd = ymdFromDateInTz(startDt, tz);
    const allowedDays = Array.isArray(program.days) ? program.days : [];
    if (!allowedDays.includes(ymd)) {
        throw new https_1.HttpsError("permission-denied", "That date is not available for this corporate program.");
    }
    const allowedServices = Array.isArray(program.serviceIdsAllowed) ? program.serviceIdsAllowed : [];
    if (allowedServices.length && !allowedServices.includes(serviceId)) {
        throw new https_1.HttpsError("permission-denied", "This service is not available for the corporate program.");
    }
    const allowedPractitioners = Array.isArray(program.practitionerIdsAllowed) ? program.practitionerIdsAllowed : [];
    if (allowedPractitioners.length && !allowedPractitioners.includes(practitionerId)) {
        throw new https_1.HttpsError("permission-denied", "This practitioner is not available for the corporate program.");
    }
    const mode = program.mode === "CODE_UNLOCK" ? "CODE_UNLOCK" : "LINK_ONLY";
    if (mode === "CODE_UNLOCK") {
        const expected = safeStr(program.staticCode);
        const provided = safeStr(corpCode);
        if (!expected || provided !== expected) {
            throw new https_1.HttpsError("permission-denied", "Corporate code is incorrect.");
        }
    }
    return { corp: program, unlocked: true };
}
// -------------------------------
// Rate limit helper (Firestore window counter)
// -------------------------------
async function enforceRateLimit(params) {
    var _a;
    const { db, clinicId, req, name, max, windowSeconds } = params;
    const xf = safeStr((_a = req.headers) === null || _a === void 0 ? void 0 : _a["x-forwarded-for"]);
    const ip = (xf.split(",")[0] || safeStr(req.ip) || "unknown").trim();
    const key = sha256Hex(`${name}|${clinicId}|${ip}`);
    const ref = db.collection("publicRateLimits").doc(key);
    const nowMs = Date.now();
    const windowMs = windowSeconds * 1000;
    await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        let count = 0;
        let windowStartMs = nowMs;
        if (snap.exists) {
            const d = snap.data();
            count = typeof d.count === "number" ? d.count : 0;
            windowStartMs = typeof d.windowStartMs === "number" ? d.windowStartMs : nowMs;
        }
        if (nowMs - windowStartMs >= windowMs) {
            count = 0;
            windowStartMs = nowMs;
        }
        if (count >= max) {
            throw new https_1.HttpsError("resource-exhausted", "Too many requests. Please try again shortly.");
        }
        tx.set(ref, {
            name,
            clinicId,
            ip,
            count: count + 1,
            windowStartMs,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    });
}
// -------------------------------
// Booking action token (manage link)
// -------------------------------
async function createManageToken(params) {
    const { db, clinicId, appointmentId } = params;
    const ttlDays = typeof params.ttlDays === "number" ? params.ttlDays : 7;
    const tokenId = randomTokenId();
    const ref = db.collection("clinics").doc(clinicId).collection("bookingActions").doc(tokenId);
    const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + ttlDays * 24 * 60 * 60 * 1000);
    await ref.set({
        appointmentId,
        action: "manage",
        expiresAt,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        usedAt: null,
    });
    return { tokenId, expiresAt };
}
async function brevoSendTemplateEmail(args) {
    const res = await fetch("https://api.brevo.com/v3/smtp/email", {
        method: "POST",
        headers: {
            "api-key": args.apiKey,
            "content-type": "application/json",
        },
        body: JSON.stringify({
            sender: { name: args.senderName, email: args.senderEmail },
            to: args.to,
            templateId: args.templateId,
            params: args.params,
        }),
    });
    const text = await res.text().catch(() => "");
    let json = null;
    try {
        json = text ? JSON.parse(text) : null;
    }
    catch {
        // ignore
    }
    if (!res.ok) {
        firebase_functions_1.logger.error("Brevo send failed", { status: res.status, body: json !== null && json !== void 0 ? json : text });
        throw new Error(`Brevo send failed (${res.status}).`);
    }
    return { messageId: json === null || json === void 0 ? void 0 : json.messageId };
}
// -------------------------------
// Main handler (Gen2 onRequest)
// -------------------------------
exports.createPublicBooking = (0, https_1.onRequest)({
    region: "europe-west3",
    cors: true,
    timeoutSeconds: 30,
}, async (req, res) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q, _r, _s, _t, _u, _v, _w, _x, _y, _z;
    try {
        if (req.method !== "POST") {
            res.status(405).json({ ok: false, error: "method-not-allowed" });
            return;
        }
        mustBeJson(req);
        const data = ((_a = req.body) !== null && _a !== void 0 ? _a : {});
        const clinicId = safeStr(data.clinicId);
        const serviceId = safeStr(data.serviceId);
        const practitionerId = safeStr(data.practitionerId);
        requireNonEmpty("clinicId", clinicId);
        requireNonEmpty("serviceId", serviceId);
        requireNonEmpty("practitionerId", practitionerId);
        const startDt = parseMillis("start", data.startMs);
        const endDt = parseMillis("end", data.endMs);
        if (endDt <= startDt)
            throw new https_1.HttpsError("invalid-argument", "Invalid start/end (end must be after start).");
        const firstName = safeStr((_b = data.patient) === null || _b === void 0 ? void 0 : _b.firstName);
        const lastName = safeStr((_c = data.patient) === null || _c === void 0 ? void 0 : _c.lastName);
        const email = safeStr((_d = data.patient) === null || _d === void 0 ? void 0 : _d.email).toLowerCase();
        const phone = safeStr((_e = data.patient) === null || _e === void 0 ? void 0 : _e.phone);
        requireNonEmpty("patient.firstName", firstName);
        requireNonEmpty("patient.email", email);
        requireEmail(email);
        const db = admin.firestore();
        // Rate limit booking endpoint (strict-ish)
        await enforceRateLimit({
            db,
            clinicId,
            req,
            name: "createPublicBooking",
            max: 20,
            windowSeconds: 60,
        });
        // --------------------------
        // Load settings (required)
        // clinics/{clinicId}/settings/publicBooking
        // --------------------------
        const settingsRef = db.collection("clinics").doc(clinicId).collection("settings").doc("publicBooking");
        const settingsSnap = await settingsRef.get();
        if (!settingsSnap.exists) {
            throw new https_1.HttpsError("failed-precondition", "Public booking is not configured for this clinic.");
        }
        const settings = ((_f = settingsSnap.data()) !== null && _f !== void 0 ? _f : {});
        // --------------------------
        // Booking rules (hours + notice + horizon)
        // Closures enforced inside createAppointmentInternal :contentReference[oaicite:2]{index=2}
        // --------------------------
        ensureNoticeAndHorizonOrThrow(settings, startDt);
        const corpSlug = safeStr(data.corpSlug) || undefined;
        const corpCode = safeStr(data.corpCode) || undefined;
        const corpCheck = validateCorporateAccessOrThrow(settings, startDt, serviceId, practitionerId, corpSlug, corpCode);
        ensureWithinOpenHoursOrThrow(settings, startDt, endDt);
        // --------------------------
        // Upsert minimal patient doc in clinics/{clinicId}/patients/{patientId}
        // Aligns with internal denormalization :contentReference[oaicite:3]{index=3}
        // --------------------------
        const patientKey = sha256Hex(`${clinicId}|${email}`);
        const patientRef = db.collection("clinics").doc(clinicId).collection("patients").doc(patientKey);
        await patientRef.set({
            firstName,
            lastName: lastName || "",
            email,
            phone: phone || "",
            source: "publicBooking",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        // Service fallback (email readability + appointment denormalization)
        const serviceNameFallback = safeStr((_g = settings.publicServiceNames) === null || _g === void 0 ? void 0 : _g[serviceId]) || serviceId;
        // --------------------------
        // Create appointment via canonical internal writer :contentReference[oaicite:4]{index=4}
        // --------------------------
        const apptResult = await (0, createAppointmentInternal_1.createAppointmentInternal)(db, {
            clinicId,
            kind: "new",
            patientId: patientRef.id,
            serviceId,
            practitionerId,
            startDt,
            endDt,
            resourceIds: [],
            actorUid: "public-booking",
            allowClosedOverride: false,
            serviceNameFallback,
        });
        const appointmentId = safeStr(apptResult === null || apptResult === void 0 ? void 0 : apptResult.appointmentId);
        // --------------------------
        // Create manage-link token (for cancel/reschedule from email)
        // --------------------------
        let manage = { tokenId: "", expiresAtMs: 0, manageUrl: "" };
        if (appointmentId) {
            const { tokenId, expiresAt } = await createManageToken({
                db,
                clinicId,
                appointmentId,
                ttlDays: 7,
            });
            const baseUrl = safeStr((_h = settings.emails) === null || _h === void 0 ? void 0 : _h.publicActionBaseUrl);
            const manageUrl = baseUrl
                ? `${baseUrl}?c=${encodeURIComponent(clinicId)}&t=${encodeURIComponent(tokenId)}`
                : "";
            manage = { tokenId, expiresAtMs: expiresAt.toMillis(), manageUrl };
        }
        // --------------------------
        // Brevo emails (best-effort; booking must not fail if email fails)
        // --------------------------
        const tz = getTz(settings);
        const dateYmd = ymdFromDateInTz(startDt, tz);
        const startHm = hmFromDateInTz(startDt, tz);
        const endHm = hmFromDateInTz(endDt, tz);
        const patientCopy = (_j = settings.patientCopy) !== null && _j !== void 0 ? _j : {};
        const brevoCfg = (_l = (_k = settings.emails) === null || _k === void 0 ? void 0 : _k.brevo) !== null && _l !== void 0 ? _l : {};
        const clinicianRecipients = Array.isArray((_m = settings.emails) === null || _m === void 0 ? void 0 : _m.clinicianRecipients)
            ? settings.emails.clinicianRecipients
            : [];
        const BREVO_API_KEY = safeStr(process.env.BREVO_API_KEY);
        let patientEmailStatus = { attempted: false };
        let clinicianEmailStatus = { attempted: false };
        const canSend = !!BREVO_API_KEY &&
            !!safeStr(brevoCfg.senderEmail) &&
            !!safeStr(brevoCfg.senderName) &&
            typeof brevoCfg.patientTemplateId === "number" &&
            typeof brevoCfg.clinicianTemplateId === "number";
        if (canSend) {
            // Patient email
            try {
                patientEmailStatus.attempted = true;
                const out = await brevoSendTemplateEmail({
                    apiKey: BREVO_API_KEY,
                    senderName: safeStr(brevoCfg.senderName),
                    senderEmail: safeStr(brevoCfg.senderEmail),
                    to: [{ email, name: `${firstName}${lastName ? " " + lastName : ""}`.trim() }],
                    templateId: brevoCfg.patientTemplateId,
                    params: {
                        firstName,
                        lastName: lastName || "",
                        date: dateYmd,
                        startTime: startHm,
                        endTime: endHm,
                        timezone: tz,
                        serviceId,
                        serviceName: serviceNameFallback,
                        whatsappLine: safeStr(patientCopy.whatsappLine),
                        whatToBring: safeStr(patientCopy.whatToBring),
                        arrivalInfo: safeStr(patientCopy.arrivalInfo),
                        cancellationPolicy: safeStr(patientCopy.cancellationPolicy),
                        cancellationUrl: safeStr(patientCopy.cancellationUrl),
                        corpSlug: corpSlug || "",
                        corpName: safeStr((_o = corpCheck.corp) === null || _o === void 0 ? void 0 : _o.displayName),
                        appointmentId: appointmentId || "",
                        manageUrl: manage.manageUrl || "",
                    },
                });
                patientEmailStatus.ok = true;
                patientEmailStatus.messageId = (_p = out.messageId) !== null && _p !== void 0 ? _p : null;
            }
            catch (e) {
                patientEmailStatus.ok = false;
                patientEmailStatus.error = (_q = e === null || e === void 0 ? void 0 : e.message) !== null && _q !== void 0 ? _q : String(e);
            }
            // Clinician email
            if (clinicianRecipients.length) {
                try {
                    clinicianEmailStatus.attempted = true;
                    const to = clinicianRecipients
                        .map((addr) => safeStr(addr))
                        .filter((addr) => addr.includes("@"))
                        .map((addr) => ({ email: addr }));
                    if (to.length) {
                        const out = await brevoSendTemplateEmail({
                            apiKey: BREVO_API_KEY,
                            senderName: safeStr(brevoCfg.senderName),
                            senderEmail: safeStr(brevoCfg.senderEmail),
                            to,
                            templateId: brevoCfg.clinicianTemplateId,
                            params: {
                                patientName: `${firstName}${lastName ? " " + lastName : ""}`.trim(),
                                patientEmail: email,
                                patientPhone: phone || "",
                                date: dateYmd,
                                startTime: startHm,
                                endTime: endHm,
                                timezone: tz,
                                serviceId,
                                serviceName: serviceNameFallback,
                                practitionerId,
                                corpSlug: corpSlug || "",
                                corpName: safeStr((_r = corpCheck.corp) === null || _r === void 0 ? void 0 : _r.displayName),
                                appointmentId: appointmentId || "",
                            },
                        });
                        clinicianEmailStatus.ok = true;
                        clinicianEmailStatus.messageId = (_s = out.messageId) !== null && _s !== void 0 ? _s : null;
                    }
                    else {
                        clinicianEmailStatus.ok = false;
                        clinicianEmailStatus.error = "No valid clinicianRecipients configured.";
                    }
                }
                catch (e) {
                    clinicianEmailStatus.ok = false;
                    clinicianEmailStatus.error = (_t = e === null || e === void 0 ? void 0 : e.message) !== null && _t !== void 0 ? _t : String(e);
                }
            }
        }
        else {
            patientEmailStatus = {
                attempted: false,
                ok: false,
                error: "Brevo not configured (missing API key or templateIds).",
            };
            clinicianEmailStatus = {
                attempted: false,
                ok: false,
                error: "Brevo not configured (missing API key or templateIds).",
            };
        }
        res.status(200).json({
            ok: true,
            clinicId,
            serviceId,
            practitionerId,
            startMs: startDt.getTime(),
            endMs: endDt.getTime(),
            patient: {
                id: patientRef.id,
                firstName,
                lastName: lastName || null,
                email,
                phone: phone || null,
            },
            corporate: corpSlug
                ? {
                    corpSlug,
                    unlocked: corpCheck.unlocked,
                    displayName: safeStr((_u = corpCheck.corp) === null || _u === void 0 ? void 0 : _u.displayName) || null,
                    mode: (_w = (_v = corpCheck.corp) === null || _v === void 0 ? void 0 : _v.mode) !== null && _w !== void 0 ? _w : "LINK_ONLY",
                }
                : null,
            appointment: apptResult,
            manage,
            emails: {
                patient: patientEmailStatus,
                clinician: clinicianEmailStatus,
            },
        });
    }
    catch (err) {
        firebase_functions_1.logger.error("createPublicBooking failed", {
            err: (_x = err === null || err === void 0 ? void 0 : err.message) !== null && _x !== void 0 ? _x : String(err),
            stack: err === null || err === void 0 ? void 0 : err.stack,
            code: err === null || err === void 0 ? void 0 : err.code,
            details: err === null || err === void 0 ? void 0 : err.details,
        });
        if (err instanceof https_1.HttpsError) {
            const status = err.code === "invalid-argument"
                ? 400
                : err.code === "unauthenticated"
                    ? 401
                    : err.code === "permission-denied"
                        ? 403
                        : err.code === "failed-precondition"
                            ? 409
                            : err.code === "resource-exhausted"
                                ? 429
                                : 500;
            res.status(status).json({
                ok: false,
                error: err.code,
                message: err.message,
                details: (_y = err.details) !== null && _y !== void 0 ? _y : null,
            });
            return;
        }
        res.status(500).json({
            ok: false,
            error: "internal",
            message: "createPublicBooking crashed. Check function logs.",
            details: { original: (_z = err === null || err === void 0 ? void 0 : err.message) !== null && _z !== void 0 ? _z : String(err) },
        });
    }
});
//# sourceMappingURL=createPublicBooking.js.map