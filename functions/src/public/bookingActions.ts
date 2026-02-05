import { onRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { enforceRateLimit } from "./rateLimit";

function safeStr(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

function mustBeJson(req: any) {
  const ct = safeStr(req.headers?.["content-type"] ?? req.headers?.["Content-Type"]);
  if (!ct.toLowerCase().includes("application/json")) {
    throw new HttpsError("invalid-argument", "Content-Type must be application/json.");
  }
}

function parseMillis(label: string, ms: unknown): admin.firestore.Timestamp {
  if (typeof ms !== "number" || !Number.isFinite(ms) || ms <= 0) {
    throw new HttpsError("invalid-argument", `Invalid ${label}Ms.`);
  }
  const d = new Date(ms);
  if (Number.isNaN(d.getTime())) throw new HttpsError("invalid-argument", `Invalid ${label}Ms.`);
  return admin.firestore.Timestamp.fromDate(d);
}

function isObj(v: unknown): v is Record<string, any> {
  return !!v && typeof v === "object" && !Array.isArray(v);
}

const DAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;

function weekdayKeyForMillis(ms: number, tz: string): (typeof DAY_KEYS)[number] {
  // Uses runtime tz conversion (Node supports Intl with timeZone)
  const short = new Intl.DateTimeFormat("en-US", { weekday: "short", timeZone: tz }).format(new Date(ms));
  const k = short.toLowerCase().slice(0, 3);
  if (DAY_KEYS.includes(k as any)) return k as any;
  // Fallback: assume UTC mapping (worst-case)
  const wd = new Date(ms).getUTCDay(); // 0=Sun..6=Sat
  const map: Record<number, (typeof DAY_KEYS)[number]> = { 0: "sun", 1: "mon", 2: "tue", 3: "wed", 4: "thu", 5: "fri", 6: "sat" };
  return map[wd] ?? "mon";
}

function settingsRef(db: admin.firestore.Firestore, clinicId: string) {
  return db.doc(`clinics/${clinicId}/settings/publicBooking`);
}

/**
 * Timezone source:
 * - Canonical is clinics/{clinicId}/settings/publicBooking.timezone
 * - Fallback to Europe/Prague if missing
 */
async function readClinicTimezone(db: admin.firestore.Firestore, clinicId: string): Promise<string> {
  const snap = await settingsRef(db, clinicId).get();
  const d = snap.exists ? (snap.data() as any) : {};
  return safeStr(d?.timezone) || "Europe/Prague";
}

function formatStartTimeLocal(params: {
  startAt: admin.firestore.Timestamp;
  clinicTz: string;
  locale?: string; // e.g. "en-US"
}): string {
  const d = params.startAt.toDate();
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
  return fmt.format(d);
}

function fmtGoogleUtc(ts: admin.firestore.Timestamp): string {
  // Google expects UTC format: YYYYMMDDTHHmmssZ
  return ts
    .toDate()
    .toISOString()
    .replace(/[-:]/g, "")
    .replace(/\.\d{3}Z$/, "Z");
}

function buildGoogleCalendarUrl(params: {
  title: string;
  startAt: admin.firestore.Timestamp;
  endAt: admin.firestore.Timestamp;
  details?: string;
  location?: string;
}): string {
  const qs = new URLSearchParams({
    action: "TEMPLATE",
    text: params.title,
    dates: `${fmtGoogleUtc(params.startAt)}/${fmtGoogleUtc(params.endAt)}`,
    details: params.details ?? "",
    location: params.location ?? "",
  });

  return `https://www.google.com/calendar/render?${qs.toString()}`;
}

/**
 * Read corporate-only rules for a specific weekday from canonical settings.
 * We support a few shapes:
 * - openingHours.days[] where index 0..6 = Mon..Sun, or each item has day/dayKey
 * - openingHours.{mon..sun} where each has corporateOnly/corporateCode (rare)
 */
function getCorporateRuleForDay(settingsData: any, dayKey: string) {
  const openingHours = settingsData?.openingHours;

  let corporateOnly = false;
  let corporateCode = "";

  // Shape A: openingHours.days[]
  const days = openingHours?.days;
  if (Array.isArray(days) && days.length >= 7) {
    // Try by explicit key first
    const match = days.find((d: any) => safeStr(d?.day).toLowerCase() === dayKey || safeStr(d?.dayKey).toLowerCase() === dayKey);
    const row = match ?? days[DAY_KEYS.indexOf(dayKey as any)];
    if (row) {
      corporateOnly = row?.corporateOnly === true;
      corporateCode = safeStr(row?.corporateCode);
      return { corporateOnly, corporateCode };
    }
  }

  // Shape B: openingHours.{mon..sun}
  if (isObj(openingHours) && isObj((openingHours as any)[dayKey])) {
    const row = (openingHours as any)[dayKey];
    corporateOnly = row?.corporateOnly === true;
    corporateCode = safeStr(row?.corporateCode);
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
function assertCorporateRescheduleAllowed(params: {
  clinicTz: string;
  settingsData: any;
  newStartAt: admin.firestore.Timestamp;
  appointmentData: any;
}) {
  const { clinicTz, settingsData, newStartAt, appointmentData } = params;

  const dayKey = weekdayKeyForMillis(newStartAt.toMillis(), clinicTz);
  const rule = getCorporateRuleForDay(settingsData, dayKey);

  if (!rule.corporateOnly) return;

  const apptCorporateOnly =
    appointmentData?.corporate?.corporateOnly === true ||
    appointmentData?.corporateOnly === true;

  // If the day is corporate-only, the appointment must be corporate-authorized.
  if (!apptSnapCorporateAllowed(apptCorporateOnly)) {
    throw new HttpsError("permission-denied", "This day is reserved for corporate bookings.");
  }

  const used =
    safeStr(appointmentData?.corporate?.corporateCodeUsed) ||
    safeStr(appointmentData?.corporateCodeUsed) ||
    safeStr(appointmentData?.corporateCode);

  const required = safeStr(rule.corporateCode);

  // If settings require a code, enforce exact (case-insensitive) match.
  if (required) {
    if (!used) {
      throw new HttpsError("permission-denied", "A corporate booking code is required for this day.");
    }
    if (used.toLowerCase() !== required.toLowerCase()) {
      throw new HttpsError("permission-denied", "Invalid corporate booking code for this day.");
    }
  }
}

function apptSnapCorporateAllowed(apptCorporateOnly: boolean) {
  return apptCorporateOnly === true;
}

async function assertNoClosureOverlap(params: {
  db: admin.firestore.Firestore;
  clinicId: string;
  startAt: admin.firestore.Timestamp;
  endAt: admin.firestore.Timestamp;
}) {
  const { db, clinicId, startAt, endAt } = params;

  const snap = await db
    .collection(`clinics/${clinicId}/closures`)
    .where("active", "==", true)
    .where("fromAt", "<", endAt)
    .get();

  for (const doc of snap.docs) {
    const data = doc.data() as any;
    const fromAt = data?.fromAt as admin.firestore.Timestamp | undefined;
    const toAt = data?.toAt as admin.firestore.Timestamp | undefined;
    if (!fromAt || !toAt) continue;

    const overlaps = startAt.toMillis() < toAt.toMillis() && endAt.toMillis() > fromAt.toMillis();
    if (overlaps) {
      throw new HttpsError("failed-precondition", "Requested time overlaps a clinic closure.", {
        closureId: doc.id,
      });
    }
  }
}

async function assertNoApptOverlap(params: {
  db: admin.firestore.Firestore;
  clinicId: string;
  practitionerId: string;
  startAt: admin.firestore.Timestamp;
  endAt: admin.firestore.Timestamp;
  excludeAppointmentId: string;
}) {
  const { db, clinicId, practitionerId, startAt, endAt, excludeAppointmentId } = params;

  const snap = await db
    .collection(`clinics/${clinicId}/appointments`)
    .where("practitionerId", "==", practitionerId)
    .where("status", "==", "booked")
    .where("startAt", "<", endAt)
    .get();

  for (const doc of snap.docs) {
    if (doc.id === excludeAppointmentId) continue;
    const d = doc.data() as any;
    const s = d?.startAt as admin.firestore.Timestamp | undefined;
    const e = d?.endAt as admin.firestore.Timestamp | undefined;
    if (!s || !e) continue;

    const overlaps = startAt.toMillis() < e.toMillis() && endAt.toMillis() > s.toMillis();
    if (overlaps) throw new HttpsError("failed-precondition", "Requested time overlaps an existing booking.");
  }
}

async function readValidToken(db: admin.firestore.Firestore, clinicId: string, tokenId: string) {
  const ref = db.collection("clinics").doc(clinicId).collection("bookingActions").doc(tokenId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("permission-denied", "Invalid or expired link.");

  const d = snap.data() as any;
  const expiresAt = d?.expiresAt as admin.firestore.Timestamp | undefined;

  if (!expiresAt || expiresAt.toMillis() <= Date.now()) {
    throw new HttpsError("permission-denied", "This link has expired.");
  }

  const appointmentId = safeStr(d?.appointmentId);
  if (!appointmentId) throw new HttpsError("permission-denied", "Invalid or expired link.");

  return { ref, token: d, appointmentId };
}

function busyBlockRef(db: admin.firestore.Firestore, clinicId: string, appointmentId: string) {
  return db.doc(`clinics/${clinicId}/public/availability/blocks/${appointmentId}`);
}

// WhatsApp contact link (clinic-specific later if you want)
const DEFAULT_WHATSAPP_URL = "https://wa.me/+6421707687";

export const getManageContext = onRequest(
  { region: "europe-west3", cors: true, timeoutSeconds: 30 },
  async (req, res) => {
    try {
      if (req.method !== "POST") return void res.status(405).json({ ok: false, error: "method-not-allowed" });
      mustBeJson(req);

      const clinicId = safeStr(req.body?.clinicId);
      const tokenId = safeStr(req.body?.tokenId);
      if (!clinicId || !tokenId) throw new HttpsError("invalid-argument", "clinicId and tokenId required.");

      const db = admin.firestore();
      await enforceRateLimit({ db, clinicId, req, cfg: { name: "getManageContext", max: 60, windowSeconds: 60 } });

      const { appointmentId } = await readValidToken(db, clinicId, tokenId);

      const apptRef = db.collection("clinics").doc(clinicId).collection("appointments").doc(appointmentId);
      const apptSnap = await apptRef.get();
      if (!apptSnap.exists) throw new HttpsError("failed-precondition", "Booking not found.");

      const a = apptSnap.data() as any;

      const startAt = a?.startAt as admin.firestore.Timestamp | undefined;
      const endAt = a?.endAt as admin.firestore.Timestamp | undefined;

      const clinicTz = await readClinicTimezone(db, clinicId);

      const startTimeLocal =
        startAt ? formatStartTimeLocal({ startAt, clinicTz, locale: "en-US" }) : "";

      const clinicName = safeStr(a?.clinicName) || safeStr(req.body?.clinicName) || "";
      const serviceName = safeStr(a?.serviceName);
      const practitionerName = safeStr(a?.practitionerName);
      const locationName = safeStr(a?.locationName) || safeStr(a?.location) || "";

      const googleCalendarUrl =
        startAt && endAt
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
          status: a?.status ?? "",
          startMs: a?.startAt?.toMillis?.() ?? null,
          endMs: a?.endAt?.toMillis?.() ?? null,
          startTimeLocal,
          googleCalendarUrl,
          whatsAppUrl: DEFAULT_WHATSAPP_URL,
          patientName: a?.patientName ?? "",
          serviceName,
          practitionerName,
          practitionerId: a?.practitionerId ?? "",
          locationName,
          // Optional visibility for UI
          corporateOnly: a?.corporate?.corporateOnly ?? a?.corporateOnly ?? false,
          corporateCodeUsed: a?.corporate?.corporateCodeUsed ?? a?.corporateCodeUsed ?? null,
        },
      });
    } catch (err: any) {
      logger.error("getManageContext failed", { err: err?.message ?? String(err), code: err?.code, stack: err?.stack });
      if (err instanceof HttpsError) {
        const status =
          err.code === "invalid-argument"
            ? 400
            : err.code === "permission-denied"
              ? 403
              : err.code === "resource-exhausted"
                ? 429
                : 409;
        return void res.status(status).json({ ok: false, error: err.code, message: err.message, details: err.details ?? null });
      }
      res.status(500).json({ ok: false, error: "internal", message: "getManageContext crashed." });
    }
  }
);

export const cancelBookingWithToken = onRequest(
  { region: "europe-west3", cors: true, timeoutSeconds: 30 },
  async (req, res) => {
    try {
      if (req.method !== "POST") return void res.status(405).json({ ok: false, error: "method-not-allowed" });
      mustBeJson(req);

      const clinicId = safeStr(req.body?.clinicId);
      const tokenId = safeStr(req.body?.tokenId);
      if (!clinicId || !tokenId) throw new HttpsError("invalid-argument", "clinicId and tokenId required.");

      const db = admin.firestore();
      await enforceRateLimit({ db, clinicId, req, cfg: { name: "cancelBookingWithToken", max: 30, windowSeconds: 60 } });

      const { appointmentId } = await readValidToken(db, clinicId, tokenId);

      const apptRef = db.collection("clinics").doc(clinicId).collection("appointments").doc(appointmentId);
      const blockRef = busyBlockRef(db, clinicId, appointmentId);

      await db.runTransaction(async (tx) => {
        const apptSnap = await tx.get(apptRef);
        if (!apptSnap.exists) throw new HttpsError("failed-precondition", "Booking not found.");

        const a = apptSnap.data() as any;
        if (a?.status !== "booked") throw new HttpsError("failed-precondition", "Booking cannot be cancelled.");

        tx.update(apptRef, {
          status: "cancelled",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedByUid: "public-link",
        });

        // ✅ Keep public availability mirror consistent
        tx.set(
          blockRef,
          {
            status: "cancelled",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      });

      res.status(200).json({ ok: true, clinicId, appointmentId });
    } catch (err: any) {
      logger.error("cancelBookingWithToken failed", { err: err?.message ?? String(err), code: err?.code, stack: err?.stack });
      if (err instanceof HttpsError) {
        const status =
          err.code === "invalid-argument"
            ? 400
            : err.code === "permission-denied"
              ? 403
              : err.code === "resource-exhausted"
                ? 429
                : 409;
        return void res.status(status).json({ ok: false, error: err.code, message: err.message, details: err.details ?? null });
      }
      res.status(500).json({ ok: false, error: "internal", message: "cancelBookingWithToken crashed." });
    }
  }
);

export const rescheduleBookingWithToken = onRequest(
  { region: "europe-west3", cors: true, timeoutSeconds: 30 },
  async (req, res) => {
    try {
      if (req.method !== "POST") return void res.status(405).json({ ok: false, error: "method-not-allowed" });
      mustBeJson(req);

      const clinicId = safeStr(req.body?.clinicId);
      const tokenId = safeStr(req.body?.tokenId);
      if (!clinicId || !tokenId) throw new HttpsError("invalid-argument", "clinicId and tokenId required.");

      const newStartAt = parseMillis("newStart", req.body?.newStartMs);
      const newEndAt = parseMillis("newEnd", req.body?.newEndMs);
      if (newEndAt.toMillis() <= newStartAt.toMillis()) throw new HttpsError("invalid-argument", "Invalid start/end.");

      const db = admin.firestore();
      await enforceRateLimit({ db, clinicId, req, cfg: { name: "rescheduleBookingWithToken", max: 30, windowSeconds: 60 } });

      const { appointmentId } = await readValidToken(db, clinicId, tokenId);

      const apptRef = db.collection("clinics").doc(clinicId).collection("appointments").doc(appointmentId);
      const blockRef = busyBlockRef(db, clinicId, appointmentId);

      // We'll read canonical settings inside the transaction to apply corporate rules consistently.
      const canonRef = settingsRef(db, clinicId);

      await db.runTransaction(async (tx) => {
        const apptSnap = await tx.get(apptRef);
        if (!apptSnap.exists) throw new HttpsError("failed-precondition", "Booking not found.");

        const a = apptSnap.data() as any;
        if (a?.status !== "booked") throw new HttpsError("failed-precondition", "Booking cannot be rescheduled.");

        const practitionerId = safeStr(a?.practitionerId);
        if (!practitionerId) throw new HttpsError("failed-precondition", "Booking has no practitioner.");

        // ✅ Corporate-only enforcement (server-side)
        const canonSnap = await tx.get(canonRef);
        const canon = canonSnap.exists ? (canonSnap.data() as any) : {};
        const clinicTz = safeStr(canon?.timezone) || "Europe/Prague";
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
        tx.set(
  blockRef,
  {
    startUtc: newStartAt,
    endUtc: newEndAt,
    status: "booked",

    // ✅ Canonical field used by listPublicSlots.ts
    practitionerId,

    // ✅ Optional legacy field (safe to keep during migration)
    clinicianId: practitionerId,

    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  },
  { merge: true }
);

      });

      res.status(200).json({
        ok: true,
        clinicId,
        appointmentId,
        newStartMs: newStartAt.toMillis(),
        newEndMs: newEndAt.toMillis(),
      });
    } catch (err: any) {
      logger.error("rescheduleBookingWithToken failed", { err: err?.message ?? String(err), code: err?.code, stack: err?.stack });
      if (err instanceof HttpsError) {
        const status =
          err.code === "invalid-argument"
            ? 400
            : err.code === "permission-denied"
              ? 403
              : err.code === "resource-exhausted"
                ? 429
                : 409;
        return void res.status(status).json({ ok: false, error: err.code, message: err.message, details: err.details ?? null });
      }
      res.status(500).json({ ok: false, error: "internal", message: "rescheduleBookingWithToken crashed." });
    }
  }
);
