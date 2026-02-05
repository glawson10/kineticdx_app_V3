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
exports.onBookingRequestCreateV2 = void 0;
// functions/src/clinic/booking/onBookingRequestCreate.ts
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/v2/firestore");
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const logger_1 = require("firebase-functions/logger");
const crypto = __importStar(require("crypto"));
const createAppointmentInternal_1 = require("./../appointments/createAppointmentInternal");
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
// ✅ Secret (set via: firebase functions:secrets:set BREVO_API_KEY)
const BREVO_API_KEY = (0, params_1.defineSecret)("BREVO_API_KEY");
// ✅ Default public app base URLs (fallback by environment if per-clinic missing)
const DEFAULT_PUBLIC_APP_BASE_URL_PROD = "https://kineticdx-app-v3.web.app";
const DEFAULT_PUBLIC_APP_BASE_URL_DEV = "https://kineticdx-v3-dev.web.app";
// ✅ Footer/logo default (clinic email footer) — set this to your Firebase Storage PUBLIC download URL
// IMPORTANT: this must be a publicly reachable https URL (Brevo can't read gs:// URLs).
// If you haven’t made it public yet, grab the “Download URL” from the Storage console.
const DEFAULT_KINETICDX_FOOTER_LOGO_URL = "https://firebasestorage.googleapis.com/v0/b/kineticdx-v3-dev.appspot.com/o/brevo%2Fkineticdx_logo2.png?alt=media";
function tsToDate(t) {
    if (t && typeof t.toDate === "function")
        return t.toDate();
    throw new Error("Invalid timestamp");
}
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
}
function lowerEmail(v) {
    return safeStr(v).toLowerCase();
}
function isLikelyValidEmail(email) {
    const e = safeStr(email).toLowerCase();
    if (!e)
        return false;
    // basic sanity: must contain @ and a dot after it
    const at = e.indexOf("@");
    if (at <= 0)
        return false;
    const dot = e.lastIndexOf(".");
    if (dot <= at + 1)
        return false;
    return true;
}
function normalizeEmail(v) {
    const e = lowerEmail(v);
    return isLikelyValidEmail(e) ? e : "";
}
function normalizePhone(v) {
    const s = safeStr(v);
    if (!s)
        return "";
    const cleaned = s.replace(/[^\d+]/g, "");
    const normalized = cleaned.startsWith("+")
        ? "+" + cleaned.slice(1).replace(/\+/g, "")
        : cleaned.replace(/\+/g, "");
    // Require at least ~6 digits to be considered matchable
    const digits = normalized.replace(/[^\d]/g, "");
    if (digits.length < 6)
        return "";
    return normalized;
}
function buildSearchTokens(parts) {
    const tokens = new Set();
    for (const p of parts) {
        const s = safeStr(p).toLowerCase();
        if (!s)
            continue;
        for (const t of s.split(/\s+/)) {
            const tt = t.trim();
            if (tt.length >= 2)
                tokens.add(tt);
        }
    }
    return Array.from(tokens);
}
function buildFullName(first, last) {
    return [safeStr(first), safeStr(last)].filter(Boolean).join(" ").trim();
}
function redactEmail(email) {
    const e = safeStr(email);
    const at = e.indexOf("@");
    if (at <= 1)
        return "***";
    return `${e[0]}***${e.slice(at - 1)}`;
}
// ─────────────────────────────────────────────────────────────
// ✅ Intake invite helpers (token + hash + invite doc)
// ─────────────────────────────────────────────────────────────
function randomToken(bytes = 32) {
    return crypto.randomBytes(bytes).toString("base64url");
}
function sha256Base64Url(s) {
    return crypto.createHash("sha256").update(s).digest("base64url");
}
async function createIntakeInvite(params) {
    var _a, _b, _c;
    const ttlHours = (_a = params.ttlHours) !== null && _a !== void 0 ? _a : 72;
    const rawToken = randomToken(32);
    const tokenHash = sha256Base64Url(rawToken);
    const inviteRef = db.collection(`clinics/${params.clinicId}/intakeInvites`).doc();
    const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + ttlHours * 60 * 60 * 1000);
    await inviteRef.set({
        schemaVersion: 1,
        clinicId: params.clinicId,
        appointmentId: params.appointmentId,
        patientId: (_b = params.patientId) !== null && _b !== void 0 ? _b : null,
        patientEmailNorm: (_c = params.patientEmailNorm) !== null && _c !== void 0 ? _c : null,
        tokenHash,
        expiresAt,
        usedAt: null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { inviteId: inviteRef.id, rawToken, expiresAt };
}
// ─────────────────────────────────────────────────────────────
// Timezone helpers + Google Calendar link
// ─────────────────────────────────────────────────────────────
function formatStartTimeLocal(params) {
    var _a;
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
    return fmt.format(params.startDt);
}
function fmtGoogleUtc(d) {
    return d.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
}
function buildGoogleCalendarUrl(params) {
    var _a, _b;
    const qs = new URLSearchParams({
        action: "TEMPLATE",
        text: params.title,
        dates: `${fmtGoogleUtc(params.startDt)}/${fmtGoogleUtc(params.endDt)}`,
        details: (_a = params.details) !== null && _a !== void 0 ? _a : "",
        location: (_b = params.location) !== null && _b !== void 0 ? _b : "",
    });
    return `https://www.google.com/calendar/render?${qs.toString()}`;
}
async function readClinicTimezone(dbi, clinicId) {
    const snap = await dbi.doc(`clinics/${clinicId}/settings/publicBooking`).get();
    const d = snap.exists ? snap.data() : {};
    return safeStr(d === null || d === void 0 ? void 0 : d.timezone) || "Europe/Prague";
}
async function readPublicBookingMirror(clinicId) {
    const snap = await db
        .doc(`clinics/${clinicId}/public/config/publicBooking/publicBooking`)
        .get();
    return snap.exists ? snap.data() : {};
}
async function tryGetClinicPublicBranding(params) {
    const d = await readPublicBookingMirror(params.clinicId);
    return {
        clinicName: safeStr(d === null || d === void 0 ? void 0 : d.clinicName),
        logoUrl: safeStr(d === null || d === void 0 ? void 0 : d.logoUrl),
    };
}
// ─────────────────────────────────────────────────────────────
// ✅ Public practitioner allowlist extraction + enforcement
// ─────────────────────────────────────────────────────────────
function extractPublicPractitioners(mirrorDoc) {
    var _a, _b, _c;
    const raw = (_c = (_a = (Array.isArray(mirrorDoc === null || mirrorDoc === void 0 ? void 0 : mirrorDoc.practitioners) ? mirrorDoc.practitioners : null)) !== null && _a !== void 0 ? _a : (Array.isArray((_b = mirrorDoc === null || mirrorDoc === void 0 ? void 0 : mirrorDoc.publicBooking) === null || _b === void 0 ? void 0 : _b.practitioners)
        ? mirrorDoc.publicBooking.practitioners
        : null)) !== null && _c !== void 0 ? _c : [];
    const out = [];
    for (const x of raw) {
        if (x && typeof x === "object") {
            const id = safeStr(x.id);
            if (!id)
                continue;
            out.push({
                id,
                displayName: safeStr(x.displayName) || undefined,
                serviceIdsAllowed: Array.isArray(x.serviceIdsAllowed)
                    ? x.serviceIdsAllowed.map((v) => safeStr(v)).filter(Boolean)
                    : undefined,
                sortOrder: typeof x.sortOrder === "number" ? x.sortOrder : undefined,
            });
            continue;
        }
        if (typeof x === "string") {
            const idMatch = x.match(/id:\s*"?([^"]+)"?/i);
            const nameMatch = x.match(/displayName:\s*"?([^"]+)"?/i);
            const id = safeStr(idMatch === null || idMatch === void 0 ? void 0 : idMatch[1]);
            if (!id)
                continue;
            out.push({
                id,
                displayName: safeStr(nameMatch === null || nameMatch === void 0 ? void 0 : nameMatch[1]) || undefined,
            });
        }
    }
    const byId = new Map();
    for (const p of out)
        if (!byId.has(p.id))
            byId.set(p.id, p);
    return Array.from(byId.values());
}
function assertPractitionerAllowedOrThrow(params) {
    const practitionerId = safeStr(params.practitionerId);
    if (!practitionerId)
        throw new https_1.HttpsError("failed-precondition", "Missing practitioner id.");
    const practitioners = extractPublicPractitioners(params.publicMirror);
    if (!practitioners.length) {
        throw new https_1.HttpsError("failed-precondition", "Public booking practitioners are not configured.");
    }
    const ok = practitioners.some((p) => p.id === practitionerId);
    if (!ok) {
        throw new https_1.HttpsError("failed-precondition", "Selected practitioner is not available for public booking.");
    }
}
// ─────────────────────────────────────────────────────────────
// Practitioner name resolution (for emails + template params)
// ─────────────────────────────────────────────────────────────
function tryGetPractitionerNameFromPublicMirror(params) {
    const pid = safeStr(params.practitionerId);
    if (!pid)
        return "";
    const list = extractPublicPractitioners(params.publicMirror);
    const hit = list.find((p) => p.id === pid);
    return safeStr(hit === null || hit === void 0 ? void 0 : hit.displayName);
}
async function tryGetPractitionerNameFromFirestore(params) {
    var _a;
    const clinicId = safeStr(params.clinicId);
    const practitionerId = safeStr(params.practitionerId);
    if (!clinicId || !practitionerId)
        return "";
    const candidates = [
        `clinics/${clinicId}/memberships/${practitionerId}`,
        `clinics/${clinicId}/members/${practitionerId}`,
        `clinics/${clinicId}/staff/${practitionerId}`,
        `clinics/${clinicId}/practitioners/${practitionerId}`,
        `users/${practitionerId}`,
    ];
    for (const path of candidates) {
        const snap = await db.doc(path).get();
        if (!snap.exists)
            continue;
        const d = (_a = snap.data()) !== null && _a !== void 0 ? _a : {};
        const name = safeStr(d.displayName) ||
            safeStr(d.name) ||
            buildFullName(safeStr(d.firstName), safeStr(d.lastName));
        if (name)
            return name;
    }
    return "";
}
async function resolvePractitionerDisplayName(params) {
    const fromMirror = params.publicMirror
        ? tryGetPractitionerNameFromPublicMirror({
            practitionerId: params.practitionerId,
            publicMirror: params.publicMirror,
        })
        : "";
    if (fromMirror)
        return fromMirror;
    const fromDb = await tryGetPractitionerNameFromFirestore({
        clinicId: params.clinicId,
        practitionerId: params.practitionerId,
    });
    if (fromDb)
        return fromDb;
    return "";
}
async function getClinicNotificationSettings(clinicId) {
    var _a;
    const docRef = db.doc(`clinics/${clinicId}/settings/notifications`);
    const docSnap = await docRef.get();
    if (!docSnap.exists)
        return {};
    return (_a = docSnap.data()) !== null && _a !== void 0 ? _a : {};
}
function resolveTemplateId(settings, eventId, localeHint) {
    var _a, _b, _c, _d;
    const ev = (_a = settings.events) === null || _a === void 0 ? void 0 : _a[eventId];
    if (!(ev === null || ev === void 0 ? void 0 : ev.enabled))
        return null;
    const locale = (localeHint || settings.defaultLocale || "en").toLowerCase();
    const byLoc = (_b = ev.templateIdByLocale) !== null && _b !== void 0 ? _b : {};
    return (_d = (_c = byLoc[locale]) !== null && _c !== void 0 ? _c : byLoc["en"]) !== null && _d !== void 0 ? _d : null;
}
async function writeNotificationLog(params) {
    var _a, _b;
    await db.collection(`clinics/${params.clinicId}/notificationLogs`).add({
        eventId: params.eventId,
        appointmentPath: params.appointmentPath,
        to: redactEmail(params.toEmail),
        provider: "brevo",
        messageId: (_a = params.messageId) !== null && _a !== void 0 ? _a : null,
        status: params.status,
        errorMessage: (_b = params.errorMessage) !== null && _b !== void 0 ? _b : null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
}
async function brevoSendTemplateEmail(input) {
    var _a;
    const fetchAny = globalThis.fetch;
    if (typeof fetchAny !== "function") {
        throw new Error("Global fetch is not available (Node 18+ required).");
    }
    const res = await fetchAny("https://api.brevo.com/v3/smtp/email", {
        method: "POST",
        headers: {
            accept: "application/json",
            "content-type": "application/json",
            "api-key": input.apiKey,
        },
        body: JSON.stringify({
            sender: input.senderId ? { id: input.senderId } : undefined,
            replyTo: input.replyToEmail ? { email: input.replyToEmail } : undefined,
            to: input.to,
            templateId: input.templateId,
            params: (_a = input.params) !== null && _a !== void 0 ? _a : {},
        }),
    });
    const text = await res.text();
    if (!res.ok)
        throw new Error(`Brevo send failed: ${res.status} ${text.slice(0, 400)}`);
    const data = JSON.parse(text);
    return { messageId: data.messageId };
}
async function tryGetClinicianEmail(clinicId, practitionerId) {
    var _a, _b;
    const candidates = [
        `clinics/${clinicId}/memberships/${practitionerId}`,
        `clinics/${clinicId}/members/${practitionerId}`,
        `clinics/${clinicId}/staff/${practitionerId}`,
        `clinics/${clinicId}/practitioners/${practitionerId}`,
    ];
    for (const path of candidates) {
        const snap = await db.doc(path).get();
        if (!snap.exists)
            continue;
        const d = (_a = snap.data()) !== null && _a !== void 0 ? _a : {};
        const email = normalizeEmail(d.email) ||
            normalizeEmail(d.invitedEmail) || // ✅ ADD THIS
            normalizeEmail((_b = d.contact) === null || _b === void 0 ? void 0 : _b.email); // optional
        if (email)
            return email;
    }
    // ✅ Optional fallback: Auth email for that uid
    try {
        const user = await admin.auth().getUser(practitionerId);
        const authEmail = normalizeEmail(user.email);
        if (authEmail)
            return authEmail;
    }
    catch {
        // ignore
    }
    return null;
}
async function tryGetClinicInboxEmail(clinicId) {
    var _a;
    const candidates = [
        `clinics/${clinicId}`,
        `clinics/${clinicId}/settings/profile`,
        `clinics/${clinicId}/settings/clinicProfile`,
    ];
    for (const path of candidates) {
        const snap = await db.doc(path).get();
        if (!snap.exists)
            continue;
        const data = (_a = snap.data()) !== null && _a !== void 0 ? _a : {};
        const email = normalizeEmail(data.email) ||
            normalizeEmail(data.inboxEmail) ||
            normalizeEmail(data.supportEmail);
        if (email)
            return email;
    }
    return null;
}
async function sendBookingNotificationsBestEffort(args) {
    var _a, _b, _c, _d, _e, _f, _g;
    const patientEmail = normalizeEmail(args.patientEmail);
    if (!patientEmail) {
        logger_1.logger.info("No valid patient email supplied; skipping email send.", {
            clinicId: args.clinicId,
            appointmentId: args.appointmentId,
        });
        return;
    }
    const settings = await getClinicNotificationSettings(args.clinicId);
    if (!Object.keys(settings !== null && settings !== void 0 ? settings : {}).length) {
        logger_1.logger.warn("Notification settings doc missing", {
            clinicId: args.clinicId,
            expectedPath: `clinics/${args.clinicId}/settings/notifications`,
        });
    }
    const apiKey = BREVO_API_KEY.value();
    const senderId = (_a = settings.brevo) === null || _a === void 0 ? void 0 : _a.senderId;
    const replyToEmail = (_b = settings.brevo) === null || _b === void 0 ? void 0 : _b.replyToEmail;
    const startTimeLocal = formatStartTimeLocal({
        startDt: args.startDt,
        clinicTz: args.clinicTz,
        locale: "en-US",
    });
    const googleCalendarUrl = buildGoogleCalendarUrl({
        title: `Appointment at ${args.clinicName || "Clinic"}`,
        startDt: args.startDt,
        endDt: args.endDt,
        details: `${args.serviceName}${args.practitionerName ? ` with ${args.practitionerName}` : ""}`.trim(),
    });
    const friendlyPractitionerName = safeStr(args.practitionerName) || "Your clinician";
    // ✅ logo handling:
    // - clinicLogoUrl: pulled from public mirror (your clinic logo)
    // - footerLogoUrl: per-clinic override in notifications OR DEFAULT_KINETICDX_FOOTER_LOGO_URL
    const footerLogoUrl = safeStr(args.footerLogoUrl) ||
        safeStr((_c = settings.branding) === null || _c === void 0 ? void 0 : _c.footerLogoUrl) ||
        safeStr(DEFAULT_KINETICDX_FOOTER_LOGO_URL);
    const paramsForBrevo = {
        clinicName: args.clinicName,
        patientName: args.patientName,
        startTimeLocal,
        practitionerName: friendlyPractitionerName,
        clinicianName: friendlyPractitionerName,
        whatsAppUrl: safeStr(args.whatsAppUrl) || "https://wa.me/+6421707687",
        googleCalendarUrl,
        preAssessmentUrl: safeStr(args.preAssessmentUrl),
        // ✅ Template params your Brevo template should reference
        clinicLogoUrl: safeStr(args.clinicLogoUrl),
        footerLogoUrl: footerLogoUrl,
        clinicId: args.clinicId,
        appointmentId: args.appointmentId,
        practitionerId: args.practitionerId,
        serviceName: args.serviceName,
        timezone: args.clinicTz,
    };
    // 1) Patient confirmation
    const patientTemplateId = resolveTemplateId(settings, "booking.created.patientConfirmation", args.localeHint);
    if (!patientTemplateId) {
        await writeNotificationLog({
            clinicId: args.clinicId,
            eventId: "booking.created.patientConfirmation",
            appointmentPath: args.appointmentPath,
            toEmail: patientEmail,
            status: "skipped",
            errorMessage: "Template not configured or event disabled (booking.created.patientConfirmation).",
        });
    }
    else {
        try {
            const result = await brevoSendTemplateEmail({
                apiKey,
                senderId,
                replyToEmail,
                to: [{ email: patientEmail, name: args.patientName }],
                templateId: patientTemplateId,
                params: paramsForBrevo,
            });
            await writeNotificationLog({
                clinicId: args.clinicId,
                eventId: "booking.created.patientConfirmation",
                appointmentPath: args.appointmentPath,
                toEmail: patientEmail,
                status: "accepted",
                messageId: result.messageId,
            });
        }
        catch (e) {
            await writeNotificationLog({
                clinicId: args.clinicId,
                eventId: "booking.created.patientConfirmation",
                appointmentPath: args.appointmentPath,
                toEmail: patientEmail,
                status: "error",
                errorMessage: safeStr(e === null || e === void 0 ? void 0 : e.message).slice(0, 500) || "Unknown send error",
            });
        }
    }
    // 2) Clinician notification
    const clinicianTemplateId = resolveTemplateId(settings, "booking.created.clinicianNotification", args.localeHint);
    if (!clinicianTemplateId)
        return;
    const mode = (_g = (_f = (_e = (_d = settings.events) === null || _d === void 0 ? void 0 : _d["booking.created.clinicianNotification"]) === null || _e === void 0 ? void 0 : _e.recipientPolicy) === null || _f === void 0 ? void 0 : _f.mode) !== null && _g !== void 0 ? _g : "practitionerOnAppointment";
    const clinicianEmail = await tryGetClinicianEmail(args.clinicId, args.practitionerId);
    const clinicInboxEmail = await tryGetClinicInboxEmail(args.clinicId);
    const recipients = [];
    if ((mode === "practitionerOnAppointment" || mode === "both") && clinicianEmail) {
        recipients.push({ email: clinicianEmail });
    }
    if ((mode === "clinicInbox" || mode === "both") && clinicInboxEmail) {
        recipients.push({ email: clinicInboxEmail });
    }
    if (recipients.length === 0) {
        await writeNotificationLog({
            clinicId: args.clinicId,
            eventId: "booking.created.clinicianNotification",
            appointmentPath: args.appointmentPath,
            toEmail: clinicianEmail || clinicInboxEmail || "unknown",
            status: "skipped",
            errorMessage: "No clinician or clinic inbox email found for recipientPolicy.",
        });
        return;
    }
    try {
        const result = await brevoSendTemplateEmail({
            apiKey,
            senderId,
            replyToEmail,
            to: recipients,
            templateId: clinicianTemplateId,
            params: paramsForBrevo,
        });
        await writeNotificationLog({
            clinicId: args.clinicId,
            eventId: "booking.created.clinicianNotification",
            appointmentPath: args.appointmentPath,
            toEmail: recipients[0].email,
            status: "accepted",
            messageId: result.messageId,
        });
    }
    catch (e) {
        await writeNotificationLog({
            clinicId: args.clinicId,
            eventId: "booking.created.clinicianNotification",
            appointmentPath: args.appointmentPath,
            toEmail: recipients[0].email,
            status: "error",
            errorMessage: safeStr(e === null || e === void 0 ? void 0 : e.message).slice(0, 500) || "Unknown send error",
        });
    }
}
// ─────────────────────────────────────────────────────────────
// Patient match helpers
// ─────────────────────────────────────────────────────────────
async function findPatientByEmailNorm(patientsCol, emailNorm) {
    if (!emailNorm)
        return "";
    let q = await patientsCol.where("contact.emailNorm", "==", emailNorm).limit(1).get();
    if (!q.empty)
        return q.docs[0].id;
    q = await patientsCol.where("emailNorm", "==", emailNorm).limit(1).get();
    if (!q.empty)
        return q.docs[0].id;
    q = await patientsCol.where("contact.email", "==", emailNorm).limit(1).get();
    if (!q.empty)
        return q.docs[0].id;
    q = await patientsCol.where("email", "==", emailNorm).limit(1).get();
    if (!q.empty)
        return q.docs[0].id;
    return "";
}
async function findPatientByPhoneNorm(patientsCol, phoneNorm) {
    if (!phoneNorm)
        return "";
    let q = await patientsCol.where("contact.phoneNorm", "==", phoneNorm).limit(1).get();
    if (!q.empty)
        return q.docs[0].id;
    q = await patientsCol.where("phoneNorm", "==", phoneNorm).limit(1).get();
    if (!q.empty)
        return q.docs[0].id;
    q = await patientsCol.where("contact.phone", "==", phoneNorm).limit(1).get();
    if (!q.empty)
        return q.docs[0].id;
    q = await patientsCol.where("phone", "==", phoneNorm).limit(1).get();
    if (!q.empty)
        return q.docs[0].id;
    return "";
}
function buildPatientCreateDoc(params) {
    const now = admin.firestore.FieldValue.serverTimestamp();
    const nested = {
        schemaVersion: 2,
        clinicId: params.clinicId,
        identity: {
            firstName: params.firstName,
            lastName: params.lastName,
            preferredName: null,
            dateOfBirth: params.dob,
            sex: null,
            pronouns: null,
            language: null,
        },
        contact: {
            email: params.emailRaw || null,
            emailNorm: params.emailNorm || null,
            phone: params.phoneRaw || null,
            phoneNorm: params.phoneNorm || null,
            preferredMethod: null,
            address: params.address
                ? { line1: params.address, line2: null, city: null, postcode: null, country: null }
                : { line1: null, line2: null, city: null, postcode: null, country: null },
            consent: { sms: null, email: null },
        },
        emergencyContact: { name: null, relationship: null, phone: null },
        referrer: { source: null, name: null, org: null, phone: null, email: null },
        billing: {
            isDifferent: false,
            name: null,
            address: null,
            insurer: { provider: null, policyNumber: null },
            invoiceNotes: null,
        },
        tags: [],
        alerts: [],
        adminNotes: null,
        status: { active: true, archived: false, archivedAt: null },
        retention: {
            policy: "7y",
            retentionUntil: admin.firestore.Timestamp.fromMillis(Date.now() + 1000 * 60 * 60 * 24 * 365 * 7),
        },
        createdFrom: "publicBooking",
        createdAt: now,
        updatedAt: now,
        // Search helpers
        fullName: params.fullName,
        fullNameLower: params.fullNameLower,
        searchTokens: params.searchTokens,
        // Legacy mirrors
        firstName: params.firstName,
        lastName: params.lastName,
        dob: params.dob,
        email: params.emailRaw || "",
        emailNorm: params.emailNorm || "",
        phone: params.phoneRaw || "",
        phoneNorm: params.phoneNorm || "",
        address: params.address,
        active: true,
        archived: false,
        archivedAt: null,
    };
    return nested;
}
function buildPatientUpdatePatch(params) {
    const patch = {
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        "identity.firstName": params.firstName,
        "identity.lastName": params.lastName,
        "contact.email": params.emailRaw || null,
        "contact.emailNorm": params.emailNorm || null,
        "contact.phone": params.phoneRaw || null,
        "contact.phoneNorm": params.phoneNorm || null,
        fullName: params.fullName,
        fullNameLower: params.fullNameLower,
        searchTokens: params.searchTokens,
        // legacy mirrors
        firstName: params.firstName,
        lastName: params.lastName,
        email: params.emailRaw || "",
        emailNorm: params.emailNorm || "",
        phone: params.phoneRaw || "",
        phoneNorm: params.phoneNorm || "",
    };
    if (params.dob) {
        patch["identity.dateOfBirth"] = params.dob;
        patch["dob"] = params.dob;
    }
    return patch;
}
// ─────────────────────────────────────────────────────────────
// ✅ Public app URL resolution + deep link builder
// ─────────────────────────────────────────────────────────────
function normalizeBaseUrl(url) {
    let u = safeStr(url);
    if (!u)
        return DEFAULT_PUBLIC_APP_BASE_URL_PROD;
    u = u.trim();
    while (u.endsWith("/"))
        u = u.slice(0, -1);
    return u || DEFAULT_PUBLIC_APP_BASE_URL_PROD;
}
function isDevProject() {
    const gcloudProject = safeStr(process.env.GCLOUD_PROJECT).toLowerCase();
    if (gcloudProject)
        return gcloudProject.includes("dev");
    try {
        const cfg = safeStr(process.env.FIREBASE_CONFIG);
        if (cfg) {
            const parsed = JSON.parse(cfg);
            const pid = safeStr(parsed === null || parsed === void 0 ? void 0 : parsed.projectId).toLowerCase();
            if (pid)
                return pid.includes("dev");
        }
    }
    catch {
        // ignore
    }
    return false;
}
function defaultBaseUrlForEnvironment() {
    return isDevProject() ? DEFAULT_PUBLIC_APP_BASE_URL_DEV : DEFAULT_PUBLIC_APP_BASE_URL_PROD;
}
async function readPublicBaseUrl(clinicId) {
    const snap = await db.doc(`clinics/${clinicId}/settings/publicBooking`).get();
    const d = snap.exists ? snap.data() : {};
    const fromDoc = safeStr(d === null || d === void 0 ? void 0 : d.publicBaseUrl);
    if (fromDoc)
        return normalizeBaseUrl(fromDoc);
    return normalizeBaseUrl(defaultBaseUrlForEnvironment());
}
function buildIntakeStartUrl(params) {
    const base = normalizeBaseUrl(params.baseUrl);
    const hashIndex = base.indexOf("#");
    const cleanBase = hashIndex >= 0 ? base.slice(0, hashIndex) : base;
    const c = encodeURIComponent(params.clinicId);
    const t = encodeURIComponent(params.token);
    const useHash = params.useHashRouting !== false;
    return useHash
        ? `${cleanBase}/#/intake/start?c=${c}&t=${t}`
        : `${cleanBase}/intake/start?c=${c}&t=${t}`;
}
// ─────────────────────────────────────────────────────────────
// Firestore trigger (CREATE only)
// ─────────────────────────────────────────────────────────────
exports.onBookingRequestCreateV2 = (0, firestore_1.onDocumentCreated)({
    region: "europe-west3",
    document: "clinics/{clinicId}/bookingRequests/{requestId}",
    secrets: [BREVO_API_KEY],
}, async (event) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k;
    const clinicId = safeStr(event.params.clinicId);
    const requestId = safeStr(event.params.requestId);
    if (!clinicId || !requestId)
        return;
    const snap = event.data;
    if (!(snap === null || snap === void 0 ? void 0 : snap.exists))
        return;
    const data = ((_a = snap.data()) !== null && _a !== void 0 ? _a : {});
    const status = safeStr(data.status) || "pending";
    logger_1.logger.info("onBookingRequestCreateV2 created", {
        clinicId,
        requestId,
        status,
        hasStartUtc: !!data.startUtc,
        hasEndUtc: !!data.endUtc,
        patientEmail: redactEmail(safeStr((_b = data.patient) === null || _b === void 0 ? void 0 : _b.email)),
        alreadyNotified: !!data.notificationSentAt,
        lock: !!data.notificationLockAt,
    });
    // ✅ Idempotency
    if (data.notificationSentAt)
        return;
    // ✅ Soft lock (best effort)
    const reqRef = db.doc(`clinics/${clinicId}/bookingRequests/${requestId}`);
    try {
        await db.runTransaction(async (tx) => {
            var _a;
            const cur = await tx.get(reqRef);
            const curData = ((_a = cur.data()) !== null && _a !== void 0 ? _a : {});
            if (curData.notificationSentAt)
                return;
            if (curData.notificationLockAt)
                return;
            tx.set(reqRef, { notificationLockAt: admin.firestore.Timestamp.now() }, { merge: true });
        });
    }
    catch (e) {
        logger_1.logger.warn("notification lock transaction failed (continuing)", {
            clinicId,
            requestId,
            err: safeStr(e === null || e === void 0 ? void 0 : e.message) || String(e),
        });
    }
    const afterLock = await reqRef.get();
    const afterData = ((_c = afterLock.data()) !== null && _c !== void 0 ? _c : {});
    if (afterData.notificationSentAt)
        return;
    // Only process pending
    if (status !== "pending")
        return;
    const now = new Date();
    // Validate timestamps early
    let startDt;
    let endDt;
    try {
        startDt = tsToDate(data.startUtc);
        endDt = tsToDate(data.endUtc);
    }
    catch {
        await reqRef.set({
            status: "rejected",
            rejectionReason: "Invalid booking timestamps.",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        return;
    }
    // 30 min cutoff
    if (startDt.getTime() - now.getTime() < 30 * 60 * 1000) {
        await reqRef.set({
            status: "rejected",
            rejectionReason: "Bookings close 30 minutes before the appointment time.",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        return;
    }
    if (endDt <= startDt) {
        await reqRef.set({
            status: "rejected",
            rejectionReason: "Invalid booking time range.",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        return;
    }
    // ✅ Canonical practitioner id
    const practitionerId = safeStr(data.practitionerId) || safeStr(data.clinicianId);
    if (!practitionerId) {
        await reqRef.set({
            status: "rejected",
            rejectionReason: "Missing practitioner id.",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        return;
    }
    const clinicTz = await readClinicTimezone(db, clinicId);
    const branding = await tryGetClinicPublicBranding({ clinicId });
    const clinicName = branding.clinicName || safeStr(data.clinicName) || "Clinic";
    const clinicLogoUrl = branding.logoUrl;
    // Load mirror once and validate allowlist
    let publicMirror = {};
    try {
        publicMirror = await readPublicBookingMirror(clinicId);
        assertPractitionerAllowedOrThrow({ practitionerId, publicMirror });
    }
    catch (e) {
        const msg = e instanceof https_1.HttpsError
            ? e.message
            : safeStr(e === null || e === void 0 ? void 0 : e.message) || "Selected practitioner is not available.";
        await reqRef.set({
            status: "rejected",
            rejectionReason: msg,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        return;
    }
    const resolvedPractitionerName = await resolvePractitionerDisplayName({
        clinicId,
        practitionerId,
        publicMirror,
    });
    // ─────────────────────────────
    // Find or create patient
    // ─────────────────────────────
    const patientsCol = db.collection(`clinics/${clinicId}/patients`);
    const pFirst = safeStr((_d = data.patient) === null || _d === void 0 ? void 0 : _d.firstName);
    const pLast = safeStr((_e = data.patient) === null || _e === void 0 ? void 0 : _e.lastName);
    const pDob = (_f = data.patient) === null || _f === void 0 ? void 0 : _f.dob;
    // ✅ Normalize + validate for matching (prevents “email=23” collisions)
    const pEmailRaw = lowerEmail((_g = data.patient) === null || _g === void 0 ? void 0 : _g.email);
    const pEmailNorm = normalizeEmail(pEmailRaw);
    const pPhoneRaw = safeStr((_h = data.patient) === null || _h === void 0 ? void 0 : _h.phone);
    const pPhoneNorm = normalizePhone(pPhoneRaw);
    const pAddress = safeStr((_j = data.patient) === null || _j === void 0 ? void 0 : _j.address);
    const pConsent = ((_k = data.patient) === null || _k === void 0 ? void 0 : _k.consentToTreatment) === true;
    if (!pFirst || !pLast || !pDob) {
        await reqRef.set({
            status: "rejected",
            rejectionReason: "Missing required patient details (first name, last name, DOB).",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        return;
    }
    const requestedPatientName = buildFullName(pFirst, pLast);
    const fullNameLower = requestedPatientName.toLowerCase();
    const searchTokens = buildSearchTokens([pFirst, pLast, pEmailNorm, pPhoneNorm]);
    let patientId = "";
    if (pEmailNorm)
        patientId = await findPatientByEmailNorm(patientsCol, pEmailNorm);
    if (!patientId && pPhoneNorm)
        patientId = await findPatientByPhoneNorm(patientsCol, pPhoneNorm);
    if (!patientId) {
        const ref = patientsCol.doc();
        patientId = ref.id;
        const doc = buildPatientCreateDoc({
            clinicId,
            firstName: pFirst,
            lastName: pLast,
            fullName: requestedPatientName,
            fullNameLower,
            searchTokens,
            dob: pDob,
            emailRaw: pEmailNorm ? pEmailNorm : "", // store only if valid
            emailNorm: pEmailNorm || "",
            phoneRaw: pPhoneNorm ? pPhoneRaw : "", // store raw only if matchable
            phoneNorm: pPhoneNorm || "",
            address: pAddress,
            consentToTreatment: pConsent,
        });
        await ref.set(doc);
    }
    else {
        const patch = buildPatientUpdatePatch({
            firstName: pFirst,
            lastName: pLast,
            fullName: requestedPatientName,
            fullNameLower,
            searchTokens,
            dob: pDob,
            emailRaw: pEmailNorm ? pEmailNorm : "",
            emailNorm: pEmailNorm || "",
            phoneRaw: pPhoneNorm ? pPhoneRaw : "",
            phoneNorm: pPhoneNorm || "",
        });
        await patientsCol.doc(patientId).set(patch, { merge: true });
    }
    // ─────────────────────────────
    // Create appointment
    // ─────────────────────────────
    const rawKind = safeStr(data.kind).toLowerCase();
    const isFollowUp = rawKind.includes("follow");
    const apptKind = isFollowUp ? "followup" : "new";
    const serviceId = isFollowUp ? "fu" : "np";
    const serviceNameFallback = isFollowUp ? "Follow-up" : "New patient assessment";
    let appointmentId = "";
    try {
        const result = await (0, createAppointmentInternal_1.createAppointmentInternal)(db, {
            clinicId,
            kind: apptKind,
            patientId,
            serviceId,
            practitionerId,
            startDt,
            endDt,
            actorUid: safeStr(data.requesterUid),
            allowClosedOverride: false,
            serviceNameFallback,
        });
        appointmentId = safeStr(result === null || result === void 0 ? void 0 : result.appointmentId);
        if (!appointmentId)
            throw new Error("createAppointmentInternal did not return appointmentId");
        const apptRef = db.doc(`clinics/${clinicId}/appointments/${appointmentId}`);
        await apptRef.set({
            clinicId,
            patientId,
            practitionerId,
            patientName: requestedPatientName,
            patientDisplayName: requestedPatientName,
            patientFirstName: pFirst,
            patientLastName: pLast,
            patientEmail: pEmailNorm || "",
            patientPhone: pPhoneNorm ? pPhoneRaw : "",
            practitionerName: resolvedPractitionerName || null,
            patient: {
                ...(typeof data.patient === "object" ? data.patient : {}),
                firstName: pFirst,
                lastName: pLast,
                email: pEmailNorm || "",
                phone: pPhoneNorm ? pPhoneRaw : "",
            },
            createdFrom: "publicBooking",
            bookingRequestId: requestId,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        // PHI-free public busy block
        await db.doc(`clinics/${clinicId}/public/availability/blocks/${appointmentId}`).set({
            startUtc: data.startUtc,
            endUtc: data.endUtc,
            status: "booked",
            practitionerId,
            source: "public",
            bookingRequestId: requestId,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        await reqRef.set({
            status: "approved",
            appointmentId,
            patientId,
            practitionerId,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    }
    catch (err) {
        const msg = err instanceof https_1.HttpsError
            ? err.message
            : safeStr(err === null || err === void 0 ? void 0 : err.message) || "Booking failed. Check logs.";
        await reqRef.set({
            status: "rejected",
            rejectionReason: msg,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        throw err;
    }
    // Re-read appointment for denormalized names (best effort)
    let apptPatientName = requestedPatientName;
    let apptServiceName = serviceNameFallback;
    let apptPractitionerName = resolvedPractitionerName;
    try {
        const apptSnap = await db.doc(`clinics/${clinicId}/appointments/${appointmentId}`).get();
        const a = apptSnap.exists ? apptSnap.data() : {};
        apptPatientName =
            safeStr(a === null || a === void 0 ? void 0 : a.patientDisplayName) || safeStr(a === null || a === void 0 ? void 0 : a.patientName) || apptPatientName;
        apptServiceName = safeStr(a === null || a === void 0 ? void 0 : a.serviceName) || apptServiceName;
        apptPractitionerName = safeStr(a === null || a === void 0 ? void 0 : a.practitionerName) || apptPractitionerName;
    }
    catch {
        // ignore
    }
    // ─────────────────────────────
    // Create intake invite + URL (function-authoritative)
    // ─────────────────────────────
    let preAssessmentUrl = "";
    try {
        const inv = await createIntakeInvite({
            clinicId,
            appointmentId,
            patientId,
            patientEmailNorm: pEmailNorm ? pEmailNorm : undefined,
            ttlHours: 72,
        });
        const baseUrl = await readPublicBaseUrl(clinicId);
        preAssessmentUrl = buildIntakeStartUrl({
            baseUrl,
            clinicId,
            token: inv.rawToken,
            useHashRouting: true,
        });
        // store on appointment too (useful for clinician view / resend)
        await db.doc(`clinics/${clinicId}/appointments/${appointmentId}`).set({
            preAssessmentUrl,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        logger_1.logger.info("Intake invite created", {
            clinicId,
            requestId,
            appointmentId,
            inviteId: inv.inviteId,
            baseUrl: normalizeBaseUrl(baseUrl),
            hasPreAssessmentUrl: !!preAssessmentUrl,
            hashRouting: true,
        });
    }
    catch (e) {
        logger_1.logger.error("createIntakeInvite failed (continuing without link)", {
            clinicId,
            requestId,
            appointmentId,
            err: safeStr(e === null || e === void 0 ? void 0 : e.message) || String(e),
        });
        preAssessmentUrl = "";
    }
    // ─────────────────────────────
    // Notifications AFTER approval
    // ─────────────────────────────
    try {
        await sendBookingNotificationsBestEffort({
            clinicId,
            appointmentId,
            appointmentPath: `clinics/${clinicId}/appointments/${appointmentId}`,
            clinicTz,
            clinicName: clinicName || "Clinic",
            // ✅ Branding in template params
            clinicLogoUrl,
            footerLogoUrl: DEFAULT_KINETICDX_FOOTER_LOGO_URL, // can be overridden via settings.branding.footerLogoUrl
            patientEmail: pEmailNorm,
            patientName: apptPatientName,
            practitionerId,
            practitionerName: apptPractitionerName || resolvedPractitionerName,
            startDt,
            endDt,
            serviceName: apptServiceName,
            preAssessmentUrl,
            whatsAppUrl: "https://wa.me/+6421707687",
            localeHint: undefined,
        });
    }
    catch (e) {
        logger_1.logger.error("sendBookingNotificationsBestEffort crashed", {
            clinicId,
            requestId,
            appointmentId,
            err: safeStr(e === null || e === void 0 ? void 0 : e.message) || String(e),
        });
    }
    // ✅ Mark sent to prevent duplicates
    await reqRef.set({
        notificationSentAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    logger_1.logger.info("Booking processing complete", {
        clinicId,
        requestId,
        appointmentId,
        notified: true,
        hasPreAssessmentUrl: !!preAssessmentUrl,
    });
});
//# sourceMappingURL=onBookingRequestCreate.js.map