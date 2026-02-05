// functions/src/clinic/booking/onBookingRequestCreate.ts
import * as admin from "firebase-admin";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions/logger";
import * as crypto from "crypto";

import { createAppointmentInternal } from "./../appointments/createAppointmentInternal";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const BREVO_API_KEY = defineSecret("BREVO_API_KEY");
const DEFAULT_PUBLIC_APP_BASE_URL = "https://kineticdx-app-v3.web.app";

type BookingRequest = {
  practitionerId?: string;
  clinicianId?: string;

  startUtc: admin.firestore.Timestamp;
  endUtc: admin.firestore.Timestamp;

  tz?: string;
  kind?: string;

  locationName?: string;
  clinicName?: string;
  preAssessmentUrl?: string;

  // ✅ client-side can pass bookingRequestId into preassessment; server will link later,
  // but we store bookingRequestId anyway as it exists in path.
  // (No additional field needed here.)

  patient: {
    firstName: string;
    lastName: string;
    dob?: admin.firestore.Timestamp;
    phone?: string;
    email?: string;
    address?: string;
    consentToTreatment?: boolean;
  };

  appointment: {
    minutes: number;
    label?: string;
    priceText?: string;
    description?: string;
  };

  requesterUid: string;
  status: string;

  corporate?: {
    corporateOnly?: boolean;
    corporateCodeUsed?: string;
    locationLabel?: string;
  };

  notificationSentAt?: admin.firestore.Timestamp;
  notificationLockAt?: admin.firestore.Timestamp;
};

type PublicPractitioner = {
  id: string;
  displayName?: string;
  serviceIdsAllowed?: string[];
  sortOrder?: number;
};

type AnyMap = Record<string, any>;

function tsToDate(t: unknown): Date {
  if (t && typeof (t as any).toDate === "function") return (t as any).toDate();
  throw new Error("Invalid timestamp");
}

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

function lowerEmail(v: unknown): string {
  return safeStr(v).toLowerCase();
}

function normalizeEmail(v: unknown): string {
  return lowerEmail(v);
}

function normalizePhone(v: unknown): string {
  const s = safeStr(v);
  if (!s) return "";
  const cleaned = s.replace(/[^\d+]/g, "");
  if (cleaned.startsWith("+")) {
    return "+" + cleaned.slice(1).replace(/\+/g, "");
  }
  return cleaned.replace(/\+/g, "");
}

function buildSearchTokens(parts: string[]): string[] {
  const tokens = new Set<string>();
  for (const p of parts) {
    const s = safeStr(p).toLowerCase();
    if (!s) continue;
    for (const t of s.split(/\s+/)) {
      const tt = t.trim();
      if (tt.length >= 2) tokens.add(tt);
    }
  }
  return Array.from(tokens);
}

function buildFullName(first: string, last: string): string {
  return [safeStr(first), safeStr(last)].filter(Boolean).join(" ").trim();
}

// ─────────────────────────────────────────────────────────────
// ✅ Public app URL resolution + deep link builder
// ─────────────────────────────────────────────────────────────

async function readPublicBaseUrl(clinicId: string): Promise<string> {
  const snap = await db.doc(`clinics/${clinicId}/settings/publicBooking`).get();
  const d = snap.exists ? (snap.data() as any) : {};
  const url = safeStr(d?.publicBaseUrl);
  return url || DEFAULT_PUBLIC_APP_BASE_URL;
}

function normalizeBaseUrl(url: string): string {
  let u = safeStr(url);
  if (!u) return DEFAULT_PUBLIC_APP_BASE_URL;
  if (u.endsWith("/")) u = u.slice(0, -1);
  return u;
}

function buildIntakeStartUrl(params: {
  baseUrl: string;
  clinicId: string;
  token: string;
  useHashRouting?: boolean;
}): string {
  const base = normalizeBaseUrl(params.baseUrl);
  const c = encodeURIComponent(params.clinicId);
  const t = encodeURIComponent(params.token);

  const useHash = params.useHashRouting !== false;
  return useHash
    ? `${base}/#/intake/start?c=${c}&t=${t}`
    : `${base}/intake/start?c=${c}&t=${t}`;
}

// ─────────────────────────────────────────────────────────────
// ✅ Intake invite helpers (token + hash + invite doc)
// ─────────────────────────────────────────────────────────────

function randomToken(bytes = 32): string {
  return crypto.randomBytes(bytes).toString("base64url");
}

function sha256Base64Url(s: string): string {
  return crypto.createHash("sha256").update(s).digest("base64url");
}

/**
 * ✅ UPDATED:
 * Invite now also stores intakeSessionId so /intake/start can resolve to a real session
 */
async function createIntakeInvite(params: {
  clinicId: string;
  appointmentId: string;
  intakeSessionId: string;
  patientId?: string;
  patientEmailNorm?: string;
  ttlHours?: number;
}): Promise<{
  inviteId: string;
  rawToken: string;
  expiresAt: admin.firestore.Timestamp;
}> {
  const ttlHours = params.ttlHours ?? 72;
  const rawToken = randomToken(32);
  const tokenHash = sha256Base64Url(rawToken);

  const inviteRef = db
    .collection(`clinics/${params.clinicId}/intakeInvites`)
    .doc();

  const expiresAt = admin.firestore.Timestamp.fromMillis(
    Date.now() + ttlHours * 60 * 60 * 1000
  );

  await inviteRef.set({
    schemaVersion: 2,
    clinicId: params.clinicId,
    appointmentId: params.appointmentId,
    intakeSessionId: params.intakeSessionId,
    patientId: params.patientId ?? null,
    patientEmailNorm: params.patientEmailNorm ?? null,
    tokenHash,
    expiresAt,
    usedAt: null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { inviteId: inviteRef.id, rawToken, expiresAt };
}

/**
 * ✅ NEW:
 * Create a real intake session immediately when the public booking is approved.
 */
async function createIntakeSessionForAppointment(params: {
  clinicId: string;
  appointmentId: string;
  patientId: string;
  practitionerId: string;
  flowId?: string;
}): Promise<string> {
  const flowId = safeStr(params.flowId) || "ankle";

  const ref = db.collection(`clinics/${params.clinicId}/intakeSessions`).doc();
  await ref.set({
    schemaVersion: 1,
    clinicId: params.clinicId,
    appointmentId: params.appointmentId,
    patientId: params.patientId,
    practitionerId: params.practitionerId,

    status: "draft",
    flow: { flowId, version: "v1" },
    answers: {},

    createdFrom: "publicBooking",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return ref.id;
}

// ─────────────────────────────────────────────────────────────
// Timezone helpers + Google Calendar link
// ─────────────────────────────────────────────────────────────

function formatStartTimeLocal(params: {
  startDt: Date;
  clinicTz: string;
  locale?: string;
}): string {
  const fmt = new Intl.DateTimeFormat(params.locale ?? "en-US", {
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

function fmtGoogleUtc(d: Date): string {
  return d.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
}

function buildGoogleCalendarUrl(params: {
  title: string;
  startDt: Date;
  endDt: Date;
  details?: string;
  location?: string;
}): string {
  const qs = new URLSearchParams({
    action: "TEMPLATE",
    text: params.title,
    dates: `${fmtGoogleUtc(params.startDt)}/${fmtGoogleUtc(params.endDt)}`,
    details: params.details ?? "",
    location: params.location ?? "",
  });

  return `https://www.google.com/calendar/render?${qs.toString()}`;
}

async function readClinicTimezone(
  dbi: admin.firestore.Firestore,
  clinicId: string
): Promise<string> {
  const snap = await dbi.doc(`clinics/${clinicId}/settings/publicBooking`).get();
  const d = snap.exists ? (snap.data() as any) : {};
  return safeStr(d?.timezone) || "Europe/Prague";
}

async function readPublicBookingMirror(clinicId: string): Promise<any> {
  const snap = await db
    .doc(`clinics/${clinicId}/public/config/publicBooking/publicBooking`)
    .get();
  return snap.exists ? (snap.data() as any) : {};
}

async function tryGetClinicPublicBranding(params: {
  clinicId: string;
}): Promise<{ clinicName: string; logoUrl: string }> {
  const d = await readPublicBookingMirror(params.clinicId);
  return {
    clinicName: safeStr(d?.clinicName),
    logoUrl: safeStr(d?.logoUrl),
  };
}

function extractPublicPractitioners(mirrorDoc: any): PublicPractitioner[] {
  const raw =
    (Array.isArray(mirrorDoc?.practitioners) ? mirrorDoc.practitioners : null) ??
    (Array.isArray(mirrorDoc?.publicBooking?.practitioners)
      ? mirrorDoc.publicBooking.practitioners
      : null) ??
    [];

  const out: PublicPractitioner[] = [];

  for (const x of raw) {
    if (x && typeof x === "object") {
      const id = safeStr((x as any).id);
      if (!id) continue;

      out.push({
        id,
        displayName: safeStr((x as any).displayName) || undefined,
        serviceIdsAllowed: Array.isArray((x as any).serviceIdsAllowed)
          ? (x as any).serviceIdsAllowed
              .map((v: any) => safeStr(v))
              .filter(Boolean)
          : undefined,
        sortOrder:
          typeof (x as any).sortOrder === "number"
            ? (x as any).sortOrder
            : undefined,
      });
      continue;
    }

    if (typeof x === "string") {
      const idMatch = x.match(/id:\s*"?([^"]+)"?/i);
      const nameMatch = x.match(/displayName:\s*"?([^"]+)"?/i);
      const id = safeStr(idMatch?.[1]);
      if (!id) continue;

      out.push({
        id,
        displayName: safeStr(nameMatch?.[1]) || undefined,
      });
    }
  }

  const byId = new Map<string, PublicPractitioner>();
  for (const p of out) if (!byId.has(p.id)) byId.set(p.id, p);
  return Array.from(byId.values());
}

function assertPractitionerAllowedOrThrow(params: {
  practitionerId: string;
  publicMirror: any;
}) {
  const practitionerId = safeStr(params.practitionerId);
  if (!practitionerId) {
    throw new HttpsError("failed-precondition", "Missing practitioner id.");
  }

  const practitioners = extractPublicPractitioners(params.publicMirror);

  if (!practitioners.length) {
    throw new HttpsError(
      "failed-precondition",
      "Public booking practitioners are not configured."
    );
  }

  const ok = practitioners.some((p) => p.id === practitionerId);
  if (!ok) {
    throw new HttpsError(
      "failed-precondition",
      "Selected practitioner is not available for public booking."
    );
  }
}

function tryGetPractitionerNameFromPublicMirror(params: {
  practitionerId: string;
  publicMirror: any;
}): string {
  const pid = safeStr(params.practitionerId);
  if (!pid) return "";
  const list = extractPublicPractitioners(params.publicMirror);
  const hit = list.find((p) => p.id === pid);
  return safeStr(hit?.displayName);
}

async function tryGetPractitionerNameFromFirestore(params: {
  clinicId: string;
  practitionerId: string;
}): Promise<string> {
  const clinicId = safeStr(params.clinicId);
  const practitionerId = safeStr(params.practitionerId);
  if (!clinicId || !practitionerId) return "";

  const candidates = [
    `clinics/${clinicId}/members/${practitionerId}`,
    `clinics/${clinicId}/staff/${practitionerId}`,
    `clinics/${clinicId}/practitioners/${practitionerId}`,
    `clinics/${clinicId}/memberships/${practitionerId}`,
    `users/${practitionerId}`,
  ];

  for (const path of candidates) {
    const snap = await db.doc(path).get();
    if (!snap.exists) continue;
    const d = snap.data() ?? {};
    const name =
      safeStr((d as any).displayName) ||
      safeStr((d as any).name) ||
      buildFullName(safeStr((d as any).firstName), safeStr((d as any).lastName));
    if (name) return name;
  }
  return "";
}

async function resolvePractitionerDisplayName(params: {
  clinicId: string;
  practitionerId: string;
  publicMirror?: any;
}): Promise<string> {
  const fromMirror = params.publicMirror
    ? tryGetPractitionerNameFromPublicMirror({
        practitionerId: params.practitionerId,
        publicMirror: params.publicMirror,
      })
    : "";
  if (fromMirror) return fromMirror;

  const fromDb = await tryGetPractitionerNameFromFirestore({
    clinicId: params.clinicId,
    practitionerId: params.practitionerId,
  });
  if (fromDb) return fromDb;

  return "";
}

// ─────────────────────────────────────────────────────────────
// Notifications (Brevo) — unchanged
// ─────────────────────────────────────────────────────────────

type NotificationEventKey =
  | "booking.created.patientConfirmation"
  | "booking.created.clinicianNotification";

type NotificationSettings = {
  schemaVersion?: number;
  defaultLocale?: string;
  brevo?: {
    senderId?: number;
    replyToEmail?: string;
  };
  events?: Record<
    string,
    {
      enabled?: boolean;
      templateIdByLocale?: Record<string, number>;
      recipientPolicy?: {
        mode?: "practitionerOnAppointment" | "clinicInbox" | "both";
      };
    }
  >;
};

async function getClinicNotificationSettings(
  clinicId: string
): Promise<NotificationSettings> {
  const docRef = db.doc(`clinics/${clinicId}/settings/notifications`);
  const docSnap = await docRef.get();
  if (!docSnap.exists) return {};
  return (docSnap.data() as NotificationSettings) ?? {};
}

function resolveTemplateId(
  settings: NotificationSettings,
  eventId: NotificationEventKey,
  localeHint?: string
): number | null {
  const ev = settings.events?.[eventId];
  if (!ev?.enabled) return null;

  const locale = (localeHint || settings.defaultLocale || "en").toLowerCase();
  const byLoc = ev.templateIdByLocale ?? {};
  return byLoc[locale] ?? byLoc["en"] ?? null;
}

function redactEmail(email: string): string {
  const e = safeStr(email);
  const at = e.indexOf("@");
  if (at <= 1) return "***";
  return `${e[0]}***${e.slice(at - 1)}`;
}

async function writeNotificationLog(params: {
  clinicId: string;
  eventId: NotificationEventKey;
  appointmentPath: string;
  toEmail: string;
  status: "accepted" | "skipped" | "error";
  messageId?: string;
  errorMessage?: string;
}) {
  await db.collection(`clinics/${params.clinicId}/notificationLogs`).add({
    eventId: params.eventId,
    appointmentPath: params.appointmentPath,
    to: redactEmail(params.toEmail),
    provider: "brevo",
    messageId: params.messageId ?? null,
    status: params.status,
    errorMessage: params.errorMessage ?? null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function brevoSendTemplateEmail(input: {
  apiKey: string;
  senderId?: number;
  replyToEmail?: string;
  to: { email: string; name?: string }[];
  templateId: number;
  params?: Record<string, unknown>;
}): Promise<{ messageId?: string }> {
  const fetchAny: any = (globalThis as any).fetch;
  if (typeof fetchAny !== "function") {
    throw new Error(
      "Global fetch is not available. Ensure Node.js 18+ runtime for Cloud Functions."
    );
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
      params: input.params ?? {},
    }),
  });

  const text = await res.text();
  if (!res.ok) {
    throw new Error(`Brevo send failed: ${res.status} ${text.slice(0, 400)}`);
  }

  const data = JSON.parse(text) as { messageId?: string };
  return { messageId: data.messageId };
}

async function tryGetClinicianEmail(
  clinicId: string,
  practitionerId: string
): Promise<string | null> {
  const candidates = [
    `clinics/${clinicId}/members/${practitionerId}`,
    `clinics/${clinicId}/staff/${practitionerId}`,
    `clinics/${clinicId}/practitioners/${practitionerId}`,
    `clinics/${clinicId}/memberships/${practitionerId}`,
  ];

  for (const path of candidates) {
    const snap = await db.doc(path).get();
    if (!snap.exists) continue;
    const data = snap.data() ?? {};
    const email = lowerEmail((data as any).email);
    if (email) return email;
  }
  return null;
}

async function tryGetClinicInboxEmail(clinicId: string): Promise<string | null> {
  const candidates = [
    `clinics/${clinicId}`,
    `clinics/${clinicId}/settings/profile`,
    `clinics/${clinicId}/settings/clinicProfile`,
  ];

  for (const path of candidates) {
    const snap = await db.doc(path).get();
    if (!snap.exists) continue;
    const data = snap.data() ?? {};
    const email =
      lowerEmail((data as any).email) ||
      lowerEmail((data as any).inboxEmail) ||
      lowerEmail((data as any).supportEmail);
    if (email) return email;
  }
  return null;
}

async function sendBookingNotificationsBestEffort(args: {
  clinicId: string;
  appointmentId: string;
  appointmentPath: string;

  clinicTz: string;
  clinicName: string;
  logoUrl?: string;

  patientEmail?: string;
  patientName: string;

  practitionerId: string;
  practitionerName?: string;

  startDt: Date;
  endDt: Date;

  serviceName: string;

  preAssessmentUrl?: string;
  whatsAppUrl?: string;

  localeHint?: string;
}) {
  const patientEmail = lowerEmail(args.patientEmail);
  if (!patientEmail) {
    logger.info("No patient email supplied; skipping email send.", {
      clinicId: args.clinicId,
      appointmentId: args.appointmentId,
    });
    return;
  }

  const settings = await getClinicNotificationSettings(args.clinicId);

  if (!Object.keys(settings ?? {}).length) {
    logger.warn("Notification settings doc missing", {
      clinicId: args.clinicId,
      expectedPath: `clinics/${args.clinicId}/settings/notifications`,
    });
  }

  const apiKey = BREVO_API_KEY.value();
  const senderId = settings.brevo?.senderId;
  const replyToEmail = settings.brevo?.replyToEmail;

  const startTimeLocal = formatStartTimeLocal({
    startDt: args.startDt,
    clinicTz: args.clinicTz,
    locale: "en-US",
  });

  const googleCalendarUrl = buildGoogleCalendarUrl({
    title: `Appointment at ${args.clinicName || "Clinic"}`,
    startDt: args.startDt,
    endDt: args.endDt,
    details: `${args.serviceName}${
      args.practitionerName ? ` with ${args.practitionerName}` : ""
    }`.trim(),
  });

  const friendlyPractitionerName =
    safeStr(args.practitionerName) || "Your clinician";

  const paramsForBrevo: Record<string, unknown> = {
    clinicName: args.clinicName,
    patientName: args.patientName,
    startTimeLocal,

    practitionerName: friendlyPractitionerName,
    clinicianName: friendlyPractitionerName,

    whatsAppUrl: safeStr(args.whatsAppUrl) || "https://wa.me/+6421707687",
    googleCalendarUrl,

    preAssessmentUrl: safeStr(args.preAssessmentUrl),
    logoUrl: safeStr(args.logoUrl),

    clinicId: args.clinicId,
    appointmentId: args.appointmentId,
    practitionerId: args.practitionerId,
    serviceName: args.serviceName,
    timezone: args.clinicTz,
  };

  const patientTemplateId = resolveTemplateId(
    settings,
    "booking.created.patientConfirmation",
    args.localeHint
  );

  if (!patientTemplateId) {
    await writeNotificationLog({
      clinicId: args.clinicId,
      eventId: "booking.created.patientConfirmation",
      appointmentPath: args.appointmentPath,
      toEmail: patientEmail,
      status: "skipped",
      errorMessage:
        "Template not configured or event disabled (booking.created.patientConfirmation).",
    });
  } else {
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
    } catch (e: any) {
      await writeNotificationLog({
        clinicId: args.clinicId,
        eventId: "booking.created.patientConfirmation",
        appointmentPath: args.appointmentPath,
        toEmail: patientEmail,
        status: "error",
        errorMessage: safeStr(e?.message).slice(0, 500) || "Unknown send error",
      });
    }
  }

  const clinicianTemplateId = resolveTemplateId(
    settings,
    "booking.created.clinicianNotification",
    args.localeHint
  );

  if (!clinicianTemplateId) return;

  const mode =
    settings.events?.["booking.created.clinicianNotification"]?.recipientPolicy
      ?.mode ?? "practitionerOnAppointment";

  const clinicianEmail = await tryGetClinicianEmail(
    args.clinicId,
    args.practitionerId
  );
  const clinicInboxEmail = await tryGetClinicInboxEmail(args.clinicId);

  const recipients: { email: string; name?: string }[] = [];
  if (
    (mode === "practitionerOnAppointment" || mode === "both") &&
    clinicianEmail
  ) {
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
      errorMessage:
        "No clinician or clinic inbox email found for recipientPolicy.",
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
  } catch (e: any) {
    await writeNotificationLog({
      clinicId: args.clinicId,
      eventId: "booking.created.clinicianNotification",
      appointmentPath: args.appointmentPath,
      toEmail: recipients[0].email,
      status: "error",
      errorMessage: safeStr(e?.message).slice(0, 500) || "Unknown send error",
    });
  }
}

// ─────────────────────────────────────────────────────────────
// Patient helpers
// ─────────────────────────────────────────────────────────────

async function findPatientByEmailNorm(
  patientsCol: FirebaseFirestore.CollectionReference,
  emailNorm: string
): Promise<string> {
  if (!emailNorm) return "";

  let q = await patientsCol
    .where("contact.emailNorm", "==", emailNorm)
    .limit(1)
    .get();
  if (!q.empty) return q.docs[0].id;

  q = await patientsCol.where("emailNorm", "==", emailNorm).limit(1).get();
  if (!q.empty) return q.docs[0].id;

  q = await patientsCol.where("contact.email", "==", emailNorm).limit(1).get();
  if (!q.empty) return q.docs[0].id;

  q = await patientsCol.where("email", "==", emailNorm).limit(1).get();
  if (!q.empty) return q.docs[0].id;

  return "";
}

async function findPatientByPhoneNorm(
  patientsCol: FirebaseFirestore.CollectionReference,
  phoneNorm: string
): Promise<string> {
  if (!phoneNorm) return "";

  let q = await patientsCol
    .where("contact.phoneNorm", "==", phoneNorm)
    .limit(1)
    .get();
  if (!q.empty) return q.docs[0].id;

  q = await patientsCol.where("phoneNorm", "==", phoneNorm).limit(1).get();
  if (!q.empty) return q.docs[0].id;

  q = await patientsCol.where("contact.phone", "==", phoneNorm).limit(1).get();
  if (!q.empty) return q.docs[0].id;

  q = await patientsCol.where("phone", "==", phoneNorm).limit(1).get();
  if (!q.empty) return q.docs[0].id;

  return "";
}

function buildPatientCreateDoc(params: {
  clinicId: string;
  firstName: string;
  lastName: string;
  fullName: string;
  fullNameLower: string;
  searchTokens: string[];
  dob: admin.firestore.Timestamp;
  emailRaw: string;
  emailNorm: string;
  phoneRaw: string;
  phoneNorm: string;
  address: string;
  consentToTreatment: boolean;
}): AnyMap {
  const now = admin.firestore.FieldValue.serverTimestamp();

  const nested: AnyMap = {
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
      retentionUntil: admin.firestore.Timestamp.fromMillis(
        Date.now() + 1000 * 60 * 60 * 24 * 365 * 7
      ),
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

function buildPatientUpdatePatch(params: {
  firstName: string;
  lastName: string;
  fullName: string;
  fullNameLower: string;
  searchTokens: string[];
  dob?: admin.firestore.Timestamp;
  emailRaw: string;
  emailNorm: string;
  phoneRaw: string;
  phoneNorm: string;
}): AnyMap {
  const patch: AnyMap = {
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

export const onBookingRequestCreateV2 = onDocumentCreated(
  {
    region: "europe-west3",
    document: "clinics/{clinicId}/bookingRequests/{requestId}",
    secrets: [BREVO_API_KEY],
  },
  async (event) => {
    const clinicId = safeStr(event.params.clinicId);
    const requestId = safeStr(event.params.requestId);
    if (!clinicId || !requestId) return;

    const snap = event.data;
    if (!snap?.exists) return;

    const data = (snap.data() ?? {}) as Partial<BookingRequest>;
    const status = safeStr(data.status) || "pending";

    logger.info("onBookingRequestCreateV2 created", {
      clinicId,
      requestId,
      status,
      hasStartUtc: !!data.startUtc,
      hasEndUtc: !!data.endUtc,
      patientEmail: redactEmail(safeStr(data.patient?.email)),
      alreadyNotified: !!(data as any).notificationSentAt,
      lock: !!(data as any).notificationLockAt,
    });

    if ((data as any).notificationSentAt) return;

    const reqRef = db.doc(`clinics/${clinicId}/bookingRequests/${requestId}`);

    // ✅ Lock so multiple creates / retries don't double-send
    try {
      await db.runTransaction(async (tx) => {
        const cur = await tx.get(reqRef);
        const curData = (cur.data() ?? {}) as any;
        if (curData.notificationSentAt) return;
        if (curData.notificationLockAt) return;
        tx.set(
          reqRef,
          { notificationLockAt: admin.firestore.Timestamp.now() },
          { merge: true }
        );
      });
    } catch (e: any) {
      logger.warn("notification lock transaction failed (continuing)", {
        clinicId,
        requestId,
        err: safeStr(e?.message) || String(e),
      });
    }

    const afterLock = await reqRef.get();
    const afterData = (afterLock.data() ?? {}) as any;
    if (afterData.notificationSentAt) return;

    if (status !== "pending") return;

    const now = new Date();

    let startDt: Date;
    let endDt: Date;
    try {
      startDt = tsToDate(data.startUtc);
      endDt = tsToDate(data.endUtc);
    } catch {
      await reqRef.set(
        {
          status: "rejected",
          rejectionReason: "Invalid booking timestamps.",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      return;
    }

    if (startDt.getTime() - now.getTime() < 30 * 60 * 1000) {
      await reqRef.set(
        {
          status: "rejected",
          rejectionReason:
            "Bookings close 30 minutes before the appointment time.",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      return;
    }

    if (endDt <= startDt) {
      await reqRef.set(
        {
          status: "rejected",
          rejectionReason: "Invalid booking time range.",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      return;
    }

    const practitionerId =
      safeStr((data as any).practitionerId) || safeStr((data as any).clinicianId);

    if (!practitionerId) {
      await reqRef.set(
        {
          status: "rejected",
          rejectionReason: "Missing practitioner id.",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      return;
    }

    const clinicTz = await readClinicTimezone(db, clinicId);

    const branding = await tryGetClinicPublicBranding({ clinicId });
    const clinicName = branding.clinicName || safeStr((data as any).clinicName) || "";
    const logoUrl = branding.logoUrl;

    let publicMirror: any = {};
    try {
      publicMirror = await readPublicBookingMirror(clinicId);
      assertPractitionerAllowedOrThrow({ practitionerId, publicMirror });
    } catch (e: any) {
      const msg =
        e instanceof HttpsError
          ? e.message
          : safeStr(e?.message) || "Selected practitioner is not available.";
      await reqRef.set(
        {
          status: "rejected",
          rejectionReason: msg,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
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

const pFirst = safeStr(data.patient?.firstName);
const pLast = safeStr(data.patient?.lastName);
const pDob = data.patient?.dob;
const pEmailRaw = lowerEmail(data.patient?.email);
const pPhoneRaw = safeStr(data.patient?.phone);

const pPhoneNorm = normalizePhone(pPhoneRaw);
const pEmailNorm = normalizeEmail(pEmailRaw);

const pAddress = safeStr(data.patient?.address);
const pConsent = data.patient?.consentToTreatment === true;

if (!pFirst || !pLast || !pDob) {
  await reqRef.set(
    {
      status: "rejected",
      rejectionReason:
        "Missing required patient details (first name, last name, DOB).",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  return;
}

const requestedPatientName = buildFullName(pFirst, pLast);
const fullNameLower = requestedPatientName.toLowerCase();
const searchTokens = buildSearchTokens([pFirst, pLast, pEmailRaw, pPhoneRaw]);

let patientId = "";

// First pass: try to find by email/phone (as before)
if (pEmailNorm) {
  patientId = await findPatientByEmailNorm(patientsCol as any, pEmailNorm);
}
if (!patientId && pPhoneNorm) {
  patientId = await findPatientByPhoneNorm(patientsCol as any, pPhoneNorm);
}

// Second pass: if we "matched", verify DOB; if mismatch, treat as no match
if (patientId) {
  try {
    const existingSnap = await patientsCol.doc(patientId).get();
    const existing = (existingSnap.data() ?? {}) as AnyMap;

    // Prefer canonical nested DOB, fall back to legacy mirrors
    const nestedDob = existing.identity?.dateOfBirth as
      | admin.firestore.Timestamp
      | undefined;
    const flatDob = (existing.dob ??
      existing.dateOfBirth) as admin.firestore.Timestamp | undefined;

    const existingDobTs = nestedDob || flatDob;
    const dobMatches =
      existingDobTs &&
      existingDobTs.toMillis() === (pDob as admin.firestore.Timestamp).toMillis();

    if (!dobMatches) {
      logger.info("Public booking: email/phone match failed DOB check, creating new patient", {
        clinicId,
        candidatePatientId: patientId,
      });
      patientId = "";
    }
  } catch (e: any) {
    logger.warn("Public booking: failed to verify matched patient DOB, creating new patient", {
      clinicId,
      candidatePatientId: patientId,
      err: safeStr(e?.message) || String(e),
    });
    patientId = "";
  }
}

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
    emailRaw: pEmailRaw || "",
    emailNorm: pEmailNorm || "",
    phoneRaw: pPhoneRaw || "",
    phoneNorm: pPhoneNorm || "",
    address: pAddress,
    consentToTreatment: pConsent,
  });

  await ref.set(doc);
} else {
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

    // ─────────────────────────────
    // Create appointment
    // ─────────────────────────────
    const rawKind = safeStr(data.kind).toLowerCase();
    const isFollowUp = rawKind.includes("follow");
    const apptKind: "new" | "followup" = isFollowUp ? "followup" : "new";
    const serviceId = isFollowUp ? "fu" : "np";
    const serviceNameFallback = isFollowUp ? "Follow-up" : "New patient assessment";

    let appointmentId = "";

    try {
      const result = await createAppointmentInternal(db, {
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

      appointmentId = safeStr((result as any)?.appointmentId);
      if (!appointmentId) {
        throw new Error("createAppointmentInternal did not return appointmentId");
      }

      const apptRef = db.doc(`clinics/${clinicId}/appointments/${appointmentId}`);

// Let createAppointmentInternal own patientName / serviceName / practitionerName.
// We only add public-booking metadata and an optional patient blob for auditing.
await apptRef.set(
  {
    practitionerName: resolvedPractitionerName || null,

    patient: {
      ...(typeof (data as any).patient === "object" ? (data as any).patient : {}),
      firstName: pFirst,
      lastName: pLast,
      email: pEmailRaw || "",
      phone: pPhoneRaw || "",
    },

    createdFrom: "publicBooking",
    bookingRequestId: requestId,

    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  },
  { merge: true }
);
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

      await reqRef.set(
        {
          status: "approved",
          appointmentId,
          patientId,
          practitionerId,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    } catch (err: any) {
      const msg =
        err instanceof HttpsError
          ? err.message
          : safeStr(err?.message) || "Booking failed. Check logs.";

      await reqRef.set(
        {
          status: "rejected",
          rejectionReason: msg,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

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
      const a = apptSnap.exists ? (apptSnap.data() as any) : {};

      apptPatientName =
        safeStr(a?.patientDisplayName) ||
        safeStr(a?.patientName) ||
        apptPatientName;

      apptServiceName = safeStr(a?.serviceName) || apptServiceName;
      apptPractitionerName =
        safeStr(a?.practitionerName) || apptPractitionerName;
    } catch {}

    // ─────────────────────────────
    // ✅ Create intakeSession + invite + persist + link on booking request
    // ─────────────────────────────
    let intakeSessionId = "";
    let inviteId = "";
    let preAssessmentUrl = "";
    let inviteExpiresAt: admin.firestore.Timestamp | null = null;

    try {
      intakeSessionId = await createIntakeSessionForAppointment({
        clinicId,
        appointmentId,
        patientId,
        practitionerId,
        flowId: "ankle",
      });

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

      const baseUrl = await readPublicBaseUrl(clinicId);
      preAssessmentUrl = buildIntakeStartUrl({
        baseUrl,
        clinicId,
        token: inv.rawToken,
        useHashRouting: true,
      });

      // Persist on appointment + booking request
      await db
        .doc(`clinics/${clinicId}/appointments/${appointmentId}`)
        .set(
          {
            intakeSessionId,
            intakeInviteId: inviteId,
            intakeInviteExpiresAt: inviteExpiresAt,
            preAssessmentUrl,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

      await reqRef.set(
        {
          intakeSessionId,
          intakeInviteId: inviteId,
          intakeInviteExpiresAt: inviteExpiresAt,
          preAssessmentUrl,

          // ✅ optional "preassessment" status stub for UI
          preassessment: {
            status: "invited",
            invitedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        },
        { merge: true }
      );

      logger.info("Intake session + invite created", {
        clinicId,
        requestId,
        appointmentId,
        intakeSessionId,
        inviteId,
        baseUrl: normalizeBaseUrl(await readPublicBaseUrl(clinicId)),
        hasPreAssessmentUrl: !!preAssessmentUrl,
      });
    } catch (e: any) {
      logger.error("Intake session/invite creation failed (continuing)", {
        clinicId,
        requestId,
        appointmentId,
        err: safeStr(e?.message) || String(e),
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
        logoUrl,

        patientEmail: pEmailRaw,
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
    } catch (e: any) {
      logger.error("sendBookingNotificationsBestEffort crashed", {
        clinicId,
        requestId,
        appointmentId,
        err: safeStr(e?.message) || String(e),
      });
    }

    await reqRef.set(
      {
        notificationSentAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    logger.info("Booking processing complete", {
      clinicId,
      requestId,
      appointmentId,
      patientId,
      intakeSessionId: intakeSessionId || null,
      notified: true,
      hasPreAssessmentUrl: !!preAssessmentUrl,
    });
  }
);
