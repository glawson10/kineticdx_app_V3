import { onRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import crypto from "crypto";

import { createAppointmentInternal } from "./../clinic/appointments/createAppointmentInternal";

/**
 * Public booking entrypoint (NO auth).
 *
 * Alignment with createAppointmentInternal: :contentReference[oaicite:1]{index=1}
 * - For kind !== "admin", internal REQUIRES: patientId, serviceId, practitionerId.
 * - Internal denormalizes patientName from: clinics/{clinicId}/patients/{patientId}.
 * - Internal enforces closures from: clinics/{clinicId}/closures (active, fromAt/toAt).
 *
 * Therefore:
 * - We upsert a minimal patient doc into clinics/{clinicId}/patients/{derivedId}.
 * - We require practitionerId in the request.
 * - We do not re-implement closure checks here (internal does that).
 */

// -------------------------------
// Types
// -------------------------------

type PublicBookingInput = {
  clinicId: string;
  serviceId: string;
  practitionerId: string;

  // epoch millis (required)
  startMs: number;
  endMs: number;

  patient: {
    firstName: string;
    lastName?: string;
    email: string;
    phone?: string;
  };

  // Optional corporate context
  corpSlug?: string;
  corpCode?: string;
};

type PublicBookingSettings = {
  timezone?: string; // e.g. "Europe/Prague"
  minNoticeMinutes?: number;
  maxAdvanceDays?: number;

  weeklyHours?: Record<string, Array<{ start: string; end: string }>>; // mon..sun

  corporatePrograms?: Array<{
    corpSlug: string;
    displayName?: string;
    mode?: "LINK_ONLY" | "CODE_UNLOCK";
    staticCode?: string;
    days?: string[]; // YYYY-MM-DD in clinic TZ
    serviceIdsAllowed?: string[];
    practitionerIdsAllowed?: string[];
  }>;

  // Optional: safe fallback name without reading /services
  publicServiceNames?: Record<string, string>;

  emails?: {
    // Where the email "manage booking" link should land (your web app route)
    // Example: https://yourdomain.com/public/booking/manage
    publicActionBaseUrl?: string;

    brevo?: {
      senderName?: string;
      senderEmail?: string;
      patientTemplateId?: number;
      clinicianTemplateId?: number;

      // Optional: if you have a dedicated Brevo template for "manage your booking"
      manageBookingTemplateId?: number;
    };

    clinicianRecipients?: string[];
  };

  patientCopy?: {
    whatsappLine?: string;
    whatToBring?: string;
    arrivalInfo?: string;
    cancellationPolicy?: string;
    cancellationUrl?: string;
  };
};

// -------------------------------
// Helpers
// -------------------------------

function safeStr(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

function requireNonEmpty(label: string, value: string) {
  if (!value.trim()) throw new HttpsError("invalid-argument", `${label} is required.`);
}

function requireEmail(value: string) {
  const s = value.trim();
  if (!s.includes("@") || s.length < 6) {
    throw new HttpsError("invalid-argument", "patient.email is invalid.");
  }
}

function parseMillis(label: string, ms: unknown): Date {
  if (typeof ms !== "number" || !Number.isFinite(ms) || ms <= 0) {
    throw new HttpsError("invalid-argument", `Invalid ${label}Ms.`);
  }
  const d = new Date(ms);
  if (Number.isNaN(d.getTime())) throw new HttpsError("invalid-argument", `Invalid ${label}Ms.`);
  return d;
}

function sha256Hex(input: string): string {
  return crypto.createHash("sha256").update(input).digest("hex");
}

function randomTokenId(): string {
  // URL-safe-ish token id
  return crypto.randomBytes(24).toString("base64url");
}

function mustBeJson(req: any) {
  const ct = safeStr(req.headers?.["content-type"] ?? req.headers?.["Content-Type"]);
  if (!ct.toLowerCase().includes("application/json")) {
    throw new HttpsError("invalid-argument", "Content-Type must be application/json.");
  }
}

function getTz(settings: PublicBookingSettings): string {
  const tz = safeStr(settings.timezone);
  return tz || "Europe/Prague";
}

function ymdFromDateInTz(d: Date, tz: string): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: tz,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(d);

  const y = parts.find((p) => p.type === "year")?.value ?? "";
  const m = parts.find((p) => p.type === "month")?.value ?? "";
  const day = parts.find((p) => p.type === "day")?.value ?? "";
  return `${y}-${m}-${day}`;
}

function hmFromDateInTz(d: Date, tz: string): string {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: tz,
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(d);

  const hh = parts.find((p) => p.type === "hour")?.value ?? "00";
  const mm = parts.find((p) => p.type === "minute")?.value ?? "00";
  return `${hh}:${mm}`;
}

function hmToMinutes(hm: string): number {
  const m = /^(\d{2}):(\d{2})$/.exec(hm.trim());
  if (!m) return NaN;
  const hh = Number(m[1]);
  const mm = Number(m[2]);
  if (!Number.isFinite(hh) || !Number.isFinite(mm)) return NaN;
  if (hh < 0 || hh > 23 || mm < 0 || mm > 59) return NaN;
  return hh * 60 + mm;
}

function dayKeyFromDateInTz(d: Date, tz: string): "mon" | "tue" | "wed" | "thu" | "fri" | "sat" | "sun" {
  const weekday = new Intl.DateTimeFormat("en-US", { weekday: "short", timeZone: tz }).format(d);
  const w = weekday.toLowerCase();
  if (w.startsWith("mon")) return "mon";
  if (w.startsWith("tue")) return "tue";
  if (w.startsWith("wed")) return "wed";
  if (w.startsWith("thu")) return "thu";
  if (w.startsWith("fri")) return "fri";
  if (w.startsWith("sat")) return "sat";
  return "sun";
}

function ensureNoticeAndHorizonOrThrow(settings: PublicBookingSettings, startDt: Date) {
  const minNotice = typeof settings.minNoticeMinutes === "number" ? settings.minNoticeMinutes : 0;
  const maxDays = typeof settings.maxAdvanceDays === "number" ? settings.maxAdvanceDays : 365;

  const now = Date.now();
  const diffMin = (startDt.getTime() - now) / 60000;
  if (diffMin < minNotice) {
    throw new HttpsError("failed-precondition", `This booking requires at least ${minNotice} minutes notice.`);
  }

  const diffDays = (startDt.getTime() - now) / 86400000;
  if (diffDays > maxDays) {
    throw new HttpsError("failed-precondition", `Bookings are only allowed up to ${maxDays} days in advance.`);
  }
}

function ensureWithinOpenHoursOrThrow(settings: PublicBookingSettings, startDt: Date, endDt: Date) {
  const tz = getTz(settings);

  const weekly = settings.weeklyHours ?? {};
  const dayKey = dayKeyFromDateInTz(startDt, tz);

  const intervals = Array.isArray(weekly[dayKey]) ? weekly[dayKey] : [];
  if (!intervals.length) {
    throw new HttpsError("failed-precondition", "Clinic is closed on that day.");
  }

  const startHm = hmFromDateInTz(startDt, tz);
  const endHm = hmFromDateInTz(endDt, tz);

  const sMin = hmToMinutes(startHm);
  const eMin = hmToMinutes(endHm);
  if (!Number.isFinite(sMin) || !Number.isFinite(eMin)) {
    throw new HttpsError("invalid-argument", "Invalid appointment time in clinic timezone.");
  }

  const ok = intervals.some((it) => {
    const a = hmToMinutes(safeStr(it.start));
    const b = hmToMinutes(safeStr(it.end));
    if (!Number.isFinite(a) || !Number.isFinite(b) || b <= a) return false;
    return sMin >= a && eMin <= b;
  });

  if (!ok) throw new HttpsError("failed-precondition", "Requested time is outside opening hours.");
}

function findCorporateProgram(settings: PublicBookingSettings, corpSlug?: string) {
  const slug = safeStr(corpSlug).toLowerCase();
  if (!slug) return null;

  const list = Array.isArray(settings.corporatePrograms) ? settings.corporatePrograms : [];
  return list.find((p) => safeStr(p?.corpSlug).toLowerCase() === slug) ?? null;
}

function validateCorporateAccessOrThrow(
  settings: PublicBookingSettings,
  startDt: Date,
  serviceId: string,
  practitionerId: string,
  corpSlug?: string,
  corpCode?: string
) {
  if (!corpSlug) return { corp: null as any, unlocked: false };

  const program = findCorporateProgram(settings, corpSlug);
  if (!program) throw new HttpsError("permission-denied", "Invalid corporate link.");

  const tz = getTz(settings);
  const ymd = ymdFromDateInTz(startDt, tz);

  const allowedDays = Array.isArray(program.days) ? program.days : [];
  if (!allowedDays.includes(ymd)) {
    throw new HttpsError("permission-denied", "That date is not available for this corporate program.");
  }

  const allowedServices = Array.isArray(program.serviceIdsAllowed) ? program.serviceIdsAllowed : [];
  if (allowedServices.length && !allowedServices.includes(serviceId)) {
    throw new HttpsError("permission-denied", "This service is not available for the corporate program.");
  }

  const allowedPractitioners = Array.isArray(program.practitionerIdsAllowed) ? program.practitionerIdsAllowed : [];
  if (allowedPractitioners.length && !allowedPractitioners.includes(practitionerId)) {
    throw new HttpsError("permission-denied", "This practitioner is not available for the corporate program.");
  }

  const mode: "LINK_ONLY" | "CODE_UNLOCK" = program.mode === "CODE_UNLOCK" ? "CODE_UNLOCK" : "LINK_ONLY";

  if (mode === "CODE_UNLOCK") {
    const expected = safeStr(program.staticCode);
    const provided = safeStr(corpCode);
    if (!expected || provided !== expected) {
      throw new HttpsError("permission-denied", "Corporate code is incorrect.");
    }
  }

  return { corp: program, unlocked: true };
}

// -------------------------------
// Rate limit helper (Firestore window counter)
// -------------------------------

async function enforceRateLimit(params: {
  db: admin.firestore.Firestore;
  clinicId: string;
  req: any;
  name: string;
  max: number;
  windowSeconds: number;
}) {
  const { db, clinicId, req, name, max, windowSeconds } = params;

  const xf = safeStr(req.headers?.["x-forwarded-for"]);
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
      const d = snap.data() as any;
      count = typeof d.count === "number" ? d.count : 0;
      windowStartMs = typeof d.windowStartMs === "number" ? d.windowStartMs : nowMs;
    }

    if (nowMs - windowStartMs >= windowMs) {
      count = 0;
      windowStartMs = nowMs;
    }

    if (count >= max) {
      throw new HttpsError("resource-exhausted", "Too many requests. Please try again shortly.");
    }

    tx.set(
      ref,
      {
        name,
        clinicId,
        ip,
        count: count + 1,
        windowStartMs,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  });
}

// -------------------------------
// Booking action token (manage link)
// -------------------------------

async function createManageToken(params: {
  db: admin.firestore.Firestore;
  clinicId: string;
  appointmentId: string;
  ttlDays?: number;
}) {
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

// -------------------------------
// Brevo helpers (optional best-effort send)
// -------------------------------

type BrevoSendArgs = {
  apiKey: string;
  senderName: string;
  senderEmail: string;
  to: Array<{ email: string; name?: string }>;
  templateId: number;
  params: Record<string, any>;
};

async function brevoSendTemplateEmail(args: BrevoSendArgs): Promise<{ messageId?: string }> {
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
  let json: any = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    // ignore
  }

  if (!res.ok) {
    logger.error("Brevo send failed", { status: res.status, body: json ?? text });
    throw new Error(`Brevo send failed (${res.status}).`);
  }

  return { messageId: json?.messageId };
}

// -------------------------------
// Main handler (Gen2 onRequest)
// -------------------------------

export const createPublicBooking = onRequest(
  {
    region: "europe-west3",
    cors: true,
    timeoutSeconds: 30,
  },
  async (req, res) => {
    try {
      if (req.method !== "POST") {
        res.status(405).json({ ok: false, error: "method-not-allowed" });
        return;
      }

      mustBeJson(req);
      const data = (req.body ?? {}) as Partial<PublicBookingInput>;

      const clinicId = safeStr(data.clinicId);
      const serviceId = safeStr(data.serviceId);
      const practitionerId = safeStr(data.practitionerId);

      requireNonEmpty("clinicId", clinicId);
      requireNonEmpty("serviceId", serviceId);
      requireNonEmpty("practitionerId", practitionerId);

      const startDt = parseMillis("start", data.startMs);
      const endDt = parseMillis("end", data.endMs);
      if (endDt <= startDt) throw new HttpsError("invalid-argument", "Invalid start/end (end must be after start).");

      const firstName = safeStr(data.patient?.firstName);
      const lastName = safeStr(data.patient?.lastName);
      const email = safeStr(data.patient?.email).toLowerCase();
      const phone = safeStr(data.patient?.phone);

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
        throw new HttpsError("failed-precondition", "Public booking is not configured for this clinic.");
      }
      const settings = (settingsSnap.data() ?? {}) as PublicBookingSettings;

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

      await patientRef.set(
        {
          firstName,
          lastName: lastName || "",
          email,
          phone: phone || "",
          source: "publicBooking",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      // Service fallback (email readability + appointment denormalization)
      const serviceNameFallback = safeStr(settings.publicServiceNames?.[serviceId]) || serviceId;

      // --------------------------
      // Create appointment via canonical internal writer :contentReference[oaicite:4]{index=4}
      // --------------------------
      const apptResult = await createAppointmentInternal(db, {
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

      const appointmentId = safeStr((apptResult as any)?.appointmentId);

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

        const baseUrl = safeStr(settings.emails?.publicActionBaseUrl);
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

      const patientCopy = settings.patientCopy ?? {};
      const brevoCfg = settings.emails?.brevo ?? {};
      const clinicianRecipients = Array.isArray(settings.emails?.clinicianRecipients)
        ? settings.emails!.clinicianRecipients!
        : [];

      const BREVO_API_KEY = safeStr(process.env.BREVO_API_KEY);

      let patientEmailStatus: any = { attempted: false };
      let clinicianEmailStatus: any = { attempted: false };

      const canSend =
        !!BREVO_API_KEY &&
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
            templateId: brevoCfg.patientTemplateId!,
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
              corpName: safeStr(corpCheck.corp?.displayName),

              appointmentId: appointmentId || "",
              manageUrl: manage.manageUrl || "",
            },
          });
          patientEmailStatus.ok = true;
          patientEmailStatus.messageId = out.messageId ?? null;
        } catch (e: any) {
          patientEmailStatus.ok = false;
          patientEmailStatus.error = e?.message ?? String(e);
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
                templateId: brevoCfg.clinicianTemplateId!,
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
                  corpName: safeStr(corpCheck.corp?.displayName),

                  appointmentId: appointmentId || "",
                },
              });
              clinicianEmailStatus.ok = true;
              clinicianEmailStatus.messageId = out.messageId ?? null;
            } else {
              clinicianEmailStatus.ok = false;
              clinicianEmailStatus.error = "No valid clinicianRecipients configured.";
            }
          } catch (e: any) {
            clinicianEmailStatus.ok = false;
            clinicianEmailStatus.error = e?.message ?? String(e);
          }
        }
      } else {
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
              displayName: safeStr(corpCheck.corp?.displayName) || null,
              mode: corpCheck.corp?.mode ?? "LINK_ONLY",
            }
          : null,
        appointment: apptResult,
        manage,
        emails: {
          patient: patientEmailStatus,
          clinician: clinicianEmailStatus,
        },
      });
    } catch (err: any) {
      logger.error("createPublicBooking failed", {
        err: err?.message ?? String(err),
        stack: err?.stack,
        code: err?.code,
        details: err?.details,
      });

      if (err instanceof HttpsError) {
        const status =
          err.code === "invalid-argument"
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
          details: err.details ?? null,
        });
        return;
      }

      res.status(500).json({
        ok: false,
        error: "internal",
        message: "createPublicBooking crashed. Check function logs.",
        details: { original: err?.message ?? String(err) },
      });
    }
  }
);
