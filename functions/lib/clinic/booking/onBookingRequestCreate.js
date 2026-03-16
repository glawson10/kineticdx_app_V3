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
const bookingConfig_1 = require("../../public/bookingConfig");
const listPublicSlots_1 = require("../../public/listPublicSlots");
const flowRegistry_1 = require("../intake/flowRegistry");
const questionnaireTemplates_1 = require("../questionnaires/questionnaireTemplates");
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
const BREVO_API_KEY = (0, params_1.defineSecret)("BREVO_API_KEY");
const DEFAULT_PUBLIC_APP_BASE_URL = "https://kineticdx-app-v3.web.app";
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
function normalizeEmail(v) {
    return lowerEmail(v);
}
function normalizePhone(v) {
    const s = safeStr(v);
    if (!s)
        return "";
    const cleaned = s.replace(/[^\d+]/g, "");
    if (cleaned.startsWith("+")) {
        return "+" + cleaned.slice(1).replace(/\+/g, "");
    }
    return cleaned.replace(/\+/g, "");
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
// ─────────────────────────────────────────────────────────────
// ✅ Public app URL resolution + deep link builder
// ─────────────────────────────────────────────────────────────
async function readPublicBaseUrl(clinicId) {
    const snap = await db.doc(`clinics/${clinicId}/settings/publicBooking`).get();
    const d = snap.exists ? snap.data() : {};
    const url = safeStr(d === null || d === void 0 ? void 0 : d.publicBaseUrl);
    return url || DEFAULT_PUBLIC_APP_BASE_URL;
}
function normalizeBaseUrl(url) {
    let u = safeStr(url);
    if (!u)
        return DEFAULT_PUBLIC_APP_BASE_URL;
    if (u.endsWith("/"))
        u = u.slice(0, -1);
    return u;
}
function buildIntakeStartUrl(params) {
    const base = normalizeBaseUrl(params.baseUrl);
    const c = encodeURIComponent(params.clinicId);
    const t = encodeURIComponent(params.token);
    const useHash = params.useHashRouting !== false;
    return useHash
        ? `${base}/#/intake/start?c=${c}&t=${t}`
        : `${base}/intake/start?c=${c}&t=${t}`;
}
function buildGeneralQuestionnaireUrl(params) {
    const base = normalizeBaseUrl(params.baseUrl);
    const t = encodeURIComponent(params.token);
    const useHash = params.useHashRouting !== false;
    return useHash ? `${base}/#/q/general/${t}` : `${base}/q/general/${t}`;
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
/**
 * ✅ UPDATED:
 * Invite now also stores intakeSessionId so /intake/start can resolve to a real session
 */
async function createIntakeInvite(params) {
    var _a, _b, _c;
    const ttlHours = (_a = params.ttlHours) !== null && _a !== void 0 ? _a : 72;
    const rawToken = randomToken(32);
    const tokenHash = sha256Base64Url(rawToken);
    const inviteRef = db
        .collection(`clinics/${params.clinicId}/intakeInvites`)
        .doc();
    const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + ttlHours * 60 * 60 * 1000);
    await inviteRef.set({
        schemaVersion: 2,
        clinicId: params.clinicId,
        appointmentId: params.appointmentId,
        intakeSessionId: params.intakeSessionId,
        patientId: (_b = params.patientId) !== null && _b !== void 0 ? _b : null,
        patientEmailNorm: (_c = params.patientEmailNorm) !== null && _c !== void 0 ? _c : null,
        tokenHash,
        expiresAt,
        usedAt: null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { inviteId: inviteRef.id, rawToken, expiresAt };
}
/**
 * ✅ Create a general questionnaire link (similar to intake invite)
 */
async function createGeneralQuestionnaireLink(params) {
    var _a, _b, _c;
    const ttlDays = (_a = params.ttlDays) !== null && _a !== void 0 ? _a : 7;
    const rawToken = randomToken(32);
    const tokenHash = sha256Base64Url(rawToken);
    const linkRef = db
        .collection(`clinics/${params.clinicId}/intakeLinks`)
        .doc();
    const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + ttlDays * 24 * 60 * 60 * 1000);
    await linkRef.set({
        schemaVersion: 1,
        clinicId: params.clinicId,
        kind: "general",
        tokenHash,
        status: "active",
        expiresAt,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        usedAt: null,
        intakeSessionId: null,
        // Optional linkage
        patientId: (_b = params.patientId) !== null && _b !== void 0 ? _b : null,
        patientEmailNorm: (_c = params.patientEmailNorm) !== null && _c !== void 0 ? _c : null,
        createdByUid: null, // System-created
    });
    return { linkId: linkRef.id, rawToken, expiresAt };
}
/**
 * Create a real intake session when the public booking is approved.
 * PA-P3.1: Template-driven; resolves flowDefinitionId/clinicalProfileId from template.
 * Legacy fallback only when template has no registry ids (LEGACY_BOOKING_DEFAULT_FLOW_ID).
 */
async function createIntakeSessionForAppointment(params) {
    var _a, _b;
    const templateId = safeStr(params.templateId) || questionnaireTemplates_1.BUILTIN_PREASSESSMENT_BOOKING_TEMPLATE_ID;
    const template = await (0, questionnaireTemplates_1.loadQuestionnaireTemplateById)(db, params.clinicId, templateId);
    const flowDefinitionId = (_a = template === null || template === void 0 ? void 0 : template.flowDefinitionId) !== null && _a !== void 0 ? _a : null;
    const clinicalProfileId = (_b = template === null || template === void 0 ? void 0 : template.clinicalProfileId) !== null && _b !== void 0 ? _b : null;
    const hasRegistryIds = flowDefinitionId && clinicalProfileId && flowDefinitionId.trim() !== "" && clinicalProfileId.trim() !== "";
    const snapshot = hasRegistryIds
        ? (0, flowRegistry_1.resolveIntakeSnapshot)({ templateId, flowDefinitionId, clinicalProfileId })
        : (0, flowRegistry_1.resolveIntakeSnapshot)({
            templateId,
            flowId: questionnaireTemplates_1.LEGACY_BOOKING_DEFAULT_FLOW_ID,
            flowVersion: 1,
        });
    const ref = db.collection(`clinics/${params.clinicId}/intakeSessions`).doc();
    await ref.set({
        schemaVersion: 1,
        clinicId: params.clinicId,
        appointmentId: params.appointmentId,
        patientId: params.patientId,
        practitionerId: params.practitionerId,
        status: "draft",
        flow: { flowId: snapshot.flowId, flowVersion: snapshot.flowVersion },
        flowId: snapshot.flowId,
        flowVersion: snapshot.flowVersion,
        flowCategory: "region",
        flowDefinitionId: snapshot.flowDefinitionId,
        clinicalProfileId: snapshot.clinicalProfileId,
        templateId,
        summaryEngine: snapshot.summaryEngine,
        decisionSupportProfile: snapshot.decisionSupportProfile,
        supportsDifferentialHypothesis: snapshot.supportsDifferentialHypothesis,
        answers: {},
        createdFrom: "publicBooking",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return ref.id;
}
/**
 * PA-P3.1: Backward compatibility — when true, create both preassessment and general questionnaire links.
 * When false, link creation is template-driven (launchKind).
 */
function shouldCreateDualLinksForBooking(_clinicId, _templateId) {
    return true;
}
/**
 * PA-P3.1: Legacy path — creates both intake invite (preassessment URL) and general questionnaire link unconditionally.
 * Use only when shouldCreateDualLinksForBooking is true.
 */
async function createLegacyDualBookingLinks(params) {
    const baseUrl = await readPublicBaseUrl(params.clinicId);
    const inv = await createIntakeInvite({
        clinicId: params.clinicId,
        appointmentId: params.appointmentId,
        intakeSessionId: params.intakeSessionId,
        patientId: params.patientId,
        patientEmailNorm: params.patientEmailNorm,
        ttlHours: 72,
    });
    const preAssessmentUrl = buildIntakeStartUrl({
        baseUrl,
        clinicId: params.clinicId,
        token: inv.rawToken,
        useHashRouting: true,
    });
    let generalQuestionnaireUrl = "";
    try {
        const genQLink = await createGeneralQuestionnaireLink({
            clinicId: params.clinicId,
            appointmentId: params.appointmentId,
            patientId: params.patientId,
            patientEmailNorm: params.patientEmailNorm,
            ttlDays: 7,
        });
        generalQuestionnaireUrl = buildGeneralQuestionnaireUrl({
            baseUrl,
            token: genQLink.rawToken,
            useHashRouting: true,
        });
    }
    catch (genQErr) {
        logger_1.logger.warn("General questionnaire link creation failed (legacy dual-link)", {
            clinicId: params.clinicId,
            err: safeStr(genQErr === null || genQErr === void 0 ? void 0 : genQErr.message) || String(genQErr),
        });
    }
    return {
        inviteId: inv.inviteId,
        inviteExpiresAt: inv.expiresAt,
        preAssessmentUrl,
        generalQuestionnaireUrl,
    };
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
/** Format a date as YYYY-MM-DD in the given IANA timezone (for maxAdvanceDays in clinic TZ). */
function ymdInTz(d, tz) {
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
                    ? x.serviceIdsAllowed
                        .map((v) => safeStr(v))
                        .filter(Boolean)
                    : undefined,
                sortOrder: typeof x.sortOrder === "number"
                    ? x.sortOrder
                    : undefined,
                allowedLocationIds: Array.isArray(x.allowedLocationIds)
                    ? x.allowedLocationIds
                        .map((v) => safeStr(v))
                        .filter(Boolean)
                    : undefined,
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
    if (!practitionerId) {
        throw new https_1.HttpsError("failed-precondition", "Missing practitioner id.");
    }
    const practitioners = extractPublicPractitioners(params.publicMirror);
    if (!practitioners.length) {
        throw new https_1.HttpsError("failed-precondition", "Public booking practitioners are not configured.");
    }
    const pract = practitioners.find((p) => p.id === practitionerId);
    if (!pract) {
        throw new https_1.HttpsError("failed-precondition", "Selected practitioner is not available for public booking.");
    }
    const locationId = safeStr(params.locationId);
    if (locationId) {
        const allowed = pract.allowedLocationIds;
        if (Array.isArray(allowed) && allowed.length > 0 && !allowed.includes(locationId)) {
            throw new https_1.HttpsError("failed-precondition", "Selected practitioner is not available at this location.");
        }
    }
    const appointmentTypeId = safeStr(params.appointmentTypeId);
    if (appointmentTypeId) {
        const allowed = pract.serviceIdsAllowed;
        if (Array.isArray(allowed) && allowed.length > 0 && !allowed.includes(appointmentTypeId)) {
            throw new https_1.HttpsError("failed-precondition", "Selected practitioner does not offer this appointment type.");
        }
    }
}
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
        `clinics/${clinicId}/members/${practitionerId}`,
        `clinics/${clinicId}/staff/${practitionerId}`,
        `clinics/${clinicId}/practitioners/${practitionerId}`,
        `clinics/${clinicId}/memberships/${practitionerId}`,
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
function redactEmail(email) {
    const e = safeStr(email);
    const at = e.indexOf("@");
    if (at <= 1)
        return "***";
    return `${e[0]}***${e.slice(at - 1)}`;
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
        throw new Error("Global fetch is not available. Ensure Node.js 18+ runtime for Cloud Functions.");
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
    if (!res.ok) {
        throw new Error(`Brevo send failed: ${res.status} ${text.slice(0, 400)}`);
    }
    const data = JSON.parse(text);
    return { messageId: data.messageId };
}
async function tryGetClinicianEmail(clinicId, practitionerId) {
    var _a;
    const candidates = [
        `clinics/${clinicId}/members/${practitionerId}`,
        `clinics/${clinicId}/staff/${practitionerId}`,
        `clinics/${clinicId}/practitioners/${practitionerId}`,
        `clinics/${clinicId}/memberships/${practitionerId}`,
    ];
    for (const path of candidates) {
        const snap = await db.doc(path).get();
        if (!snap.exists)
            continue;
        const data = (_a = snap.data()) !== null && _a !== void 0 ? _a : {};
        const email = lowerEmail(data.email);
        if (email)
            return email;
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
        const email = lowerEmail(data.email) ||
            lowerEmail(data.inboxEmail) ||
            lowerEmail(data.supportEmail);
        if (email)
            return email;
    }
    return null;
}
async function sendBookingNotificationsBestEffort(args) {
    var _a, _b, _c, _d, _e, _f;
    const patientEmail = lowerEmail(args.patientEmail);
    if (!patientEmail) {
        logger_1.logger.info("No patient email supplied; skipping email send.", {
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
    const paramsForBrevo = {
        clinicName: args.clinicName,
        patientName: args.patientName,
        startTimeLocal,
        practitionerName: friendlyPractitionerName,
        clinicianName: friendlyPractitionerName,
        whatsAppUrl: safeStr(args.whatsAppUrl) || "https://wa.me/+6421707687",
        googleCalendarUrl,
        preAssessmentUrl: safeStr(args.preAssessmentUrl),
        generalQuestionnaireUrl: safeStr(args.generalQuestionnaireUrl),
        logoUrl: safeStr(args.logoUrl),
        clinicId: args.clinicId,
        appointmentId: args.appointmentId,
        practitionerId: args.practitionerId,
        serviceName: args.serviceName,
        timezone: args.clinicTz,
    };
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
    const clinicianTemplateId = resolveTemplateId(settings, "booking.created.clinicianNotification", args.localeHint);
    if (!clinicianTemplateId)
        return;
    const mode = (_f = (_e = (_d = (_c = settings.events) === null || _c === void 0 ? void 0 : _c["booking.created.clinicianNotification"]) === null || _d === void 0 ? void 0 : _d.recipientPolicy) === null || _e === void 0 ? void 0 : _e.mode) !== null && _f !== void 0 ? _f : "practitionerOnAppointment";
    const clinicianEmail = await tryGetClinicianEmail(args.clinicId, args.practitionerId);
    const clinicInboxEmail = await tryGetClinicInboxEmail(args.clinicId);
    const recipients = [];
    if ((mode === "practitionerOnAppointment" || mode === "both") &&
        clinicianEmail) {
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
// Patient helpers
// ─────────────────────────────────────────────────────────────
async function findPatientByEmailNorm(patientsCol, emailNorm) {
    if (!emailNorm)
        return "";
    let q = await patientsCol
        .where("contact.emailNorm", "==", emailNorm)
        .limit(1)
        .get();
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
    let q = await patientsCol
        .where("contact.phoneNorm", "==", phoneNorm)
        .limit(1)
        .get();
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
                ? {
                    line1: params.address,
                    line2: null,
                    city: null,
                    postcode: null,
                    country: null,
                }
                : {
                    line1: null,
                    line2: null,
                    city: null,
                    postcode: null,
                    country: null,
                },
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
        status: {
            active: true,
            archived: false,
            archivedAt: null,
        },
        retention: {
            policy: "7y",
            retentionUntil: admin.firestore.Timestamp.fromMillis(Date.now() + 1000 * 60 * 60 * 24 * 365 * 7),
        },
        createdFrom: "publicBooking",
        createdAt: now,
        updatedAt: now,
    };
    nested.fullName = params.fullName;
    nested.fullNameLower = params.fullNameLower;
    nested.searchTokens = params.searchTokens;
    nested.firstName = params.firstName;
    nested.lastName = params.lastName;
    nested.dob = params.dob;
    nested.email = params.emailRaw || "";
    nested.emailNorm = params.emailNorm || "";
    nested.phone = params.phoneRaw || "";
    nested.phoneNorm = params.phoneNorm || "";
    nested.address = params.address;
    nested.active = true;
    nested.archived = false;
    nested.archivedAt = null;
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
// Firestore trigger
// ─────────────────────────────────────────────────────────────
exports.onBookingRequestCreateV2 = (0, firestore_1.onDocumentCreated)({
    region: "europe-west3",
    document: "clinics/{clinicId}/bookingRequests/{requestId}",
    secrets: [BREVO_API_KEY],
}, async (event) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q;
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
    if (data.notificationSentAt)
        return;
    const reqRef = db.doc(`clinics/${clinicId}/bookingRequests/${requestId}`);
    // ✅ Lock so multiple creates / retries don't double-send
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
    if (status !== "pending")
        return;
    const now = new Date();
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
    const bookingRules = await (0, bookingConfig_1.loadPublicBookingRules)(db, clinicId);
    const minNoticeMs = bookingRules.minNoticeMinutes * 60 * 1000;
    if (startDt.getTime() - now.getTime() < minNoticeMs) {
        await reqRef.set({
            status: "rejected",
            rejectionReason: "booking_min_notice_violation",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        return;
    }
    const slotYmd = ymdInTz(startDt, bookingRules.timezone);
    const todayYmd = ymdInTz(now, bookingRules.timezone);
    const slotDayMs = new Date(slotYmd + "T12:00:00Z").getTime();
    const todayDayMs = new Date(todayYmd + "T12:00:00Z").getTime();
    const daysAhead = Math.floor((slotDayMs - todayDayMs) / 86400000);
    if (daysAhead > bookingRules.maxAdvanceDays) {
        await reqRef.set({
            status: "rejected",
            rejectionReason: "booking_max_advance_violation",
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
    const clinicName = branding.clinicName || safeStr(data.clinicName) || "";
    const logoUrl = branding.logoUrl;
    let publicMirror = {};
    try {
        publicMirror = await readPublicBookingMirror(clinicId);
        assertPractitionerAllowedOrThrow({
            practitionerId,
            publicMirror,
            locationId: safeStr(data.locationId) || undefined,
            appointmentTypeId: safeStr(data.appointmentTypeId) || undefined,
        });
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
    if (bookingRules.requireEmail && !safeStr(lowerEmail((_d = data.patient) === null || _d === void 0 ? void 0 : _d.email))) {
        await reqRef.set({
            status: "rejected",
            rejectionReason: "booking_email_required",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        return;
    }
    if (bookingRules.requirePhone && !safeStr((_e = data.patient) === null || _e === void 0 ? void 0 : _e.phone)) {
        await reqRef.set({
            status: "rejected",
            rejectionReason: "booking_phone_required",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        return;
    }
    // ─────────────────────────────
    // Find or create patient
    // ─────────────────────────────
    const patientsCol = db.collection(`clinics/${clinicId}/patients`);
    const pFirst = safeStr((_f = data.patient) === null || _f === void 0 ? void 0 : _f.firstName);
    const pLast = safeStr((_g = data.patient) === null || _g === void 0 ? void 0 : _g.lastName);
    const pDob = (_h = data.patient) === null || _h === void 0 ? void 0 : _h.dob;
    const pEmailRaw = lowerEmail((_j = data.patient) === null || _j === void 0 ? void 0 : _j.email);
    const pPhoneRaw = safeStr((_k = data.patient) === null || _k === void 0 ? void 0 : _k.phone);
    const pPhoneNorm = normalizePhone(pPhoneRaw);
    const pEmailNorm = normalizeEmail(pEmailRaw);
    const pAddress = safeStr((_l = data.patient) === null || _l === void 0 ? void 0 : _l.address);
    const pConsent = ((_m = data.patient) === null || _m === void 0 ? void 0 : _m.consentToTreatment) === true;
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
    const searchTokens = buildSearchTokens([pFirst, pLast, pEmailRaw, pPhoneRaw]);
    let patientId = "";
    let patientWasCreated = false;
    // First pass: try to find by email/phone (as before)
    if (pEmailNorm) {
        patientId = await findPatientByEmailNorm(patientsCol, pEmailNorm);
    }
    if (!patientId && pPhoneNorm) {
        patientId = await findPatientByPhoneNorm(patientsCol, pPhoneNorm);
    }
    // Second pass: if we "matched", verify DOB; if mismatch, treat as no match
    if (patientId) {
        try {
            const existingSnap = await patientsCol.doc(patientId).get();
            const existing = ((_o = existingSnap.data()) !== null && _o !== void 0 ? _o : {});
            // Prefer canonical nested DOB, fall back to legacy mirrors
            const nestedDob = (_p = existing.identity) === null || _p === void 0 ? void 0 : _p.dateOfBirth;
            const flatDob = ((_q = existing.dob) !== null && _q !== void 0 ? _q : existing.dateOfBirth);
            const existingDobTs = nestedDob || flatDob;
            const dobMatches = existingDobTs &&
                existingDobTs.toMillis() === pDob.toMillis();
            if (!dobMatches) {
                logger_1.logger.info("Public booking: email/phone match failed DOB check, creating new patient", {
                    clinicId,
                    candidatePatientId: patientId,
                });
                patientId = "";
            }
        }
        catch (e) {
            logger_1.logger.warn("Public booking: failed to verify matched patient DOB, creating new patient", {
                clinicId,
                candidatePatientId: patientId,
                err: safeStr(e === null || e === void 0 ? void 0 : e.message) || String(e),
            });
            patientId = "";
        }
    }
    if (!patientId) {
        patientWasCreated = true;
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
            emailRaw: pEmailRaw || "",
            emailNorm: pEmailNorm || "",
            phoneRaw: pPhoneRaw || "",
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
            emailRaw: pEmailRaw || "",
            emailNorm: pEmailNorm || "",
            phoneRaw: pPhoneRaw || "",
            phoneNorm: pPhoneNorm || "",
        });
        await patientsCol.doc(patientId).set(patch, { merge: true });
    }
    if (patientWasCreated && !bookingRules.allowNewPatients) {
        await reqRef.set({
            status: "rejected",
            rejectionReason: "booking_new_patients_not_allowed",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        return;
    }
    // ─────────────────────────────
    // Create appointment
    // ─────────────────────────────
    const rawKind = safeStr(data.kind).toLowerCase();
    const isFollowUp = rawKind.includes("follow");
    const apptKind = isFollowUp ? "followup" : "new";
    const explicitTypeId = safeStr(data.appointmentTypeId);
    const serviceId = explicitTypeId || (isFollowUp ? "fu" : "np");
    const serviceNameFallback = isFollowUp ? "Follow-up" : "New patient assessment";
    let appointmentId = "";
    try {
        const reqLocationId = safeStr(data.locationId);
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
            ...(reqLocationId ? { locationId: reqLocationId } : {}),
        });
        appointmentId = safeStr(result === null || result === void 0 ? void 0 : result.appointmentId);
        if (!appointmentId) {
            throw new Error("createAppointmentInternal did not return appointmentId");
        }
        const apptRef = db.doc(`clinics/${clinicId}/appointments/${appointmentId}`);
        // Let createAppointmentInternal own patientName / serviceName / practitionerName.
        // We only add public-booking metadata and an optional patient blob for auditing.
        await apptRef.set({
            practitionerName: resolvedPractitionerName || null,
            patient: {
                ...(typeof data.patient === "object" ? data.patient : {}),
                firstName: pFirst,
                lastName: pLast,
                email: pEmailRaw || "",
                phone: pPhoneRaw || "",
            },
            createdFrom: "publicBooking",
            bookingRequestId: requestId,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        await db
            .doc(`clinics/${clinicId}/public/availability/blocks/${appointmentId}`)
            .set({
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
        try {
            const dateYmd = ymdInTz(startDt, bookingRules.timezone);
            (0, listPublicSlots_1.invalidateSlotCacheForBooking)(clinicId, practitionerId, dateYmd);
        }
        catch (invErr) {
            logger_1.logger.warn("Slot cache invalidation failed (non-fatal)", {
                clinicId,
                practitionerId,
                err: safeStr(invErr === null || invErr === void 0 ? void 0 : invErr.message) || String(invErr),
            });
        }
    }
    catch (err) {
        const msg = err instanceof https_1.HttpsError
            ? err.message
            : safeStr(err === null || err === void 0 ? void 0 : err.message) || "Booking failed. Check logs.";
        const rejectionReason = msg === "slot_no_longer_available"
            ? "That time is no longer available."
            : msg;
        await reqRef.set({
            status: "rejected",
            rejectionReason,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        throw err;
    }
    // Read appointment doc for denormalized names
    let apptPatientName = requestedPatientName;
    let apptServiceName = serviceNameFallback;
    let apptPractitionerName = resolvedPractitionerName;
    try {
        const apptSnap = await db
            .doc(`clinics/${clinicId}/appointments/${appointmentId}`)
            .get();
        const a = apptSnap.exists ? apptSnap.data() : {};
        apptPatientName =
            safeStr(a === null || a === void 0 ? void 0 : a.patientDisplayName) ||
                safeStr(a === null || a === void 0 ? void 0 : a.patientName) ||
                apptPatientName;
        apptServiceName = safeStr(a === null || a === void 0 ? void 0 : a.serviceName) || apptServiceName;
        apptPractitionerName =
            safeStr(a === null || a === void 0 ? void 0 : a.practitionerName) || apptPractitionerName;
    }
    catch { }
    // ─────────────────────────────
    // ✅ Create intakeSession + invite + persist + link on booking request
    // ─────────────────────────────
    let intakeSessionId = "";
    let inviteId = "";
    let preAssessmentUrl = "";
    let inviteExpiresAt = null;
    let generalQuestionnaireUrl = "";
    try {
        const templateId = questionnaireTemplates_1.BUILTIN_PREASSESSMENT_BOOKING_TEMPLATE_ID;
        const template = await (0, questionnaireTemplates_1.loadQuestionnaireTemplateById)(db, clinicId, templateId);
        intakeSessionId = await createIntakeSessionForAppointment({
            clinicId,
            appointmentId,
            patientId,
            practitionerId,
            templateId,
        });
        if (shouldCreateDualLinksForBooking(clinicId, templateId)) {
            const legacy = await createLegacyDualBookingLinks({
                clinicId,
                appointmentId,
                intakeSessionId,
                patientId,
                patientEmailNorm: pEmailNorm ? pEmailNorm : undefined,
            });
            inviteId = legacy.inviteId;
            inviteExpiresAt = legacy.inviteExpiresAt;
            preAssessmentUrl = legacy.preAssessmentUrl;
            generalQuestionnaireUrl = legacy.generalQuestionnaireUrl;
        }
        else {
            const baseUrl = await readPublicBaseUrl(clinicId);
            if ((template === null || template === void 0 ? void 0 : template.launchKind) === questionnaireTemplates_1.QUESTIONNAIRE_LAUNCH_KIND_BOOKING_PREASSESSMENT) {
                const inv = await createIntakeInvite({
                    clinicId,
                    appointmentId,
                    intakeSessionId,
                    patientId,
                    patientEmailNorm: pEmailNorm ? pEmailNorm : undefined,
                    ttlHours: 72,
                });
                inviteId = inv.inviteId;
                inviteExpiresAt = inv.expiresAt;
                preAssessmentUrl = buildIntakeStartUrl({
                    baseUrl,
                    clinicId,
                    token: inv.rawToken,
                    useHashRouting: true,
                });
            }
            if ((template === null || template === void 0 ? void 0 : template.launchKind) === questionnaireTemplates_1.QUESTIONNAIRE_LAUNCH_KIND_INTAKE_LINK) {
                try {
                    const genQLink = await createGeneralQuestionnaireLink({
                        clinicId,
                        appointmentId,
                        patientId,
                        patientEmailNorm: pEmailNorm ? pEmailNorm : undefined,
                        ttlDays: 7,
                    });
                    generalQuestionnaireUrl = buildGeneralQuestionnaireUrl({
                        baseUrl: await readPublicBaseUrl(clinicId),
                        token: genQLink.rawToken,
                        useHashRouting: true,
                    });
                }
                catch (genQErr) {
                    logger_1.logger.warn("General questionnaire link creation failed", {
                        clinicId,
                        requestId,
                        err: safeStr(genQErr === null || genQErr === void 0 ? void 0 : genQErr.message) || String(genQErr),
                    });
                }
            }
        }
        // Persist on appointment + booking request
        await db
            .doc(`clinics/${clinicId}/appointments/${appointmentId}`)
            .set({
            intakeSessionId,
            intakeInviteId: inviteId,
            intakeInviteExpiresAt: inviteExpiresAt,
            preAssessmentUrl,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        await reqRef.set({
            intakeSessionId,
            intakeInviteId: inviteId,
            intakeInviteExpiresAt: inviteExpiresAt,
            preAssessmentUrl,
            // ✅ optional "preassessment" status stub for UI
            preassessment: {
                status: "invited",
                invitedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
        }, { merge: true });
        logger_1.logger.info("Intake session + invite created", {
            clinicId,
            requestId,
            appointmentId,
            intakeSessionId,
            inviteId,
            baseUrl: normalizeBaseUrl(await readPublicBaseUrl(clinicId)),
            hasPreAssessmentUrl: !!preAssessmentUrl,
            hasGeneralQuestionnaireUrl: !!generalQuestionnaireUrl,
        });
    }
    catch (e) {
        logger_1.logger.error("Intake session/invite creation failed (continuing)", {
            clinicId,
            requestId,
            appointmentId,
            err: safeStr(e === null || e === void 0 ? void 0 : e.message) || String(e),
        });
        preAssessmentUrl = "";
        generalQuestionnaireUrl = "";
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
            logoUrl,
            patientEmail: pEmailRaw,
            patientName: apptPatientName,
            practitionerId,
            practitionerName: apptPractitionerName || resolvedPractitionerName,
            startDt,
            endDt,
            serviceName: apptServiceName,
            preAssessmentUrl,
            generalQuestionnaireUrl,
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
    await reqRef.set({
        notificationSentAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    logger_1.logger.info("Booking processing complete", {
        clinicId,
        requestId,
        appointmentId,
        patientId,
        intakeSessionId: intakeSessionId || null,
        notified: true,
        hasPreAssessmentUrl: !!preAssessmentUrl,
    });
});
//# sourceMappingURL=onBookingRequestCreate.js.map