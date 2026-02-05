import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/logger";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

type CreateBookingRequestInput = {
  clinicId: string;

  // allow either (we’ll normalize to practitionerId)
  practitionerId?: string;
  clinicianId?: string;

  startUtcMs: number; // epoch millis
  endUtcMs: number;   // epoch millis

  tz?: string;        // e.g. "Europe/Prague"
  kind?: string;      // "new" | "followup" | etc

  patient: {
    firstName: string;
    lastName: string;
    dobMs: number; // epoch millis (required)
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
};

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

function lowerEmail(v: unknown): string {
  return safeStr(v).toLowerCase();
}

function toTsFromMs(ms: number): admin.firestore.Timestamp {
  if (!Number.isFinite(ms) || ms <= 0) throw new Error("Invalid ms timestamp");
  return admin.firestore.Timestamp.fromMillis(ms);
}

function normalizePhone(v: unknown): string {
  const s = safeStr(v);
  if (!s) return "";
  const cleaned = s.replace(/[^\d+]/g, "");
  if (cleaned.startsWith("+")) return "+" + cleaned.slice(1).replace(/\+/g, "");
  return cleaned.replace(/\+/g, "");
}

function requireAuthed(context: any) {
  // Option 1 typically means: require auth (anonymous auth is fine too)
  if (!context.auth?.uid) {
    throw new HttpsError("unauthenticated", "You must be signed in to book.");
  }
  return context.auth.uid as string;
}

export const createBookingRequestFn = onCall(
  { region: "europe-west3" },
  async (req) => {
    const uid = requireAuthed(req);

    const input = (req.data ?? {}) as Partial<CreateBookingRequestInput>;

    const clinicId = safeStr(input.clinicId);
    if (!clinicId) throw new HttpsError("invalid-argument", "Missing clinicId.");

    const practitionerId = safeStr(input.practitionerId) || safeStr(input.clinicianId);
    if (!practitionerId) {
      throw new HttpsError("invalid-argument", "Missing practitionerId/clinicianId.");
    }

    // times
    let startUtc: admin.firestore.Timestamp;
    let endUtc: admin.firestore.Timestamp;
    try {
      startUtc = toTsFromMs(Number(input.startUtcMs));
      endUtc = toTsFromMs(Number(input.endUtcMs));
    } catch {
      throw new HttpsError("invalid-argument", "Invalid start/end times.");
    }

    const startDt = startUtc.toDate();
    const endDt = endUtc.toDate();
    if (!(endDt.getTime() > startDt.getTime())) {
      throw new HttpsError("invalid-argument", "End time must be after start time.");
    }

    // patient
    const p = input.patient ?? ({} as any);
    const firstName = safeStr(p.firstName);
    const lastName = safeStr(p.lastName);

    let dob: admin.firestore.Timestamp;
    try {
      dob = toTsFromMs(Number(p.dobMs));
    } catch {
      throw new HttpsError("invalid-argument", "Missing/invalid patient DOB.");
    }

    if (!firstName || !lastName) {
      throw new HttpsError("invalid-argument", "Missing patient first/last name.");
    }

    // appointment
    const a = input.appointment ?? ({} as any);
    const minutes = Number(a.minutes);
    if (!Number.isFinite(minutes) || minutes <= 0 || minutes > 240) {
      throw new HttpsError("invalid-argument", "Invalid appointment minutes.");
    }

    const tz = safeStr(input.tz) || "Europe/Prague";
    const kind = safeStr(input.kind) || "new";

    const email = lowerEmail(p.email);
    const phoneRaw = safeStr(p.phone);
    const phoneNorm = normalizePhone(phoneRaw);

    const requestDoc: Record<string, any> = {
      clinicId,
      practitionerId, // canonical field going forward
      clinicianId: safeStr(input.clinicianId) || null, // optional legacy

      startUtc,
      endUtc,
      tz,
      kind,

      patient: {
        firstName,
        lastName,
        dob,
        email: email || "",
        phone: phoneRaw || "",
        phoneNorm: phoneNorm || "",
        address: safeStr(p.address) || "",
        consentToTreatment: p.consentToTreatment === true,
      },

      appointment: {
        minutes,
        label: safeStr(a.label) || "",
        priceText: safeStr(a.priceText) || "",
        description: safeStr(a.description) || "",
      },

      requesterUid: uid,
      status: "pending",

      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      source: "publicBookingCallable",
    };

    const ref = db.collection(`clinics/${clinicId}/bookingRequests`).doc();

    await ref.set(requestDoc);

    logger.info("BookingRequest created via callable", {
      clinicId,
      requestId: ref.id,
      uid,
      practitionerId,
      startUtcMs: startDt.getTime(),
    });

    return {
      bookingRequestId: ref.id,
      path: ref.path,
      status: "pending",
    };
  }
);
