import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { writePublicBookingMirror } from "./writePublicBookingMirror";

type BootstrapPublicBookingSettingsInput = {
  clinicId: string;
  publicActionBaseUrl?: string;
};

function safeStr(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

function asString(v: unknown, maxLen: number): string | undefined {
  if (typeof v !== "string") return undefined;
  const s = v.trim();
  if (!s) return undefined;
  return s.length > maxLen ? s.slice(0, maxLen) : s;
}

async function getMembershipData(
  db: FirebaseFirestore.Firestore,
  clinicId: string,
  uid: string
): Promise<FirebaseFirestore.DocumentData | null> {
  const canonical = db.doc(`clinics/${clinicId}/memberships/${uid}`);
  const legacy = db.doc(`clinics/${clinicId}/members/${uid}`);

  const c = await canonical.get();
  if (c.exists) return c.data() ?? {};

  const l = await legacy.get();
  if (l.exists) return l.data() ?? {};

  return null;
}

function isActiveMember(data: FirebaseFirestore.DocumentData): boolean {
  const status = (data.status ?? "").toString().toLowerCase().trim();
  if (status === "suspended" || status === "invited") return false;
  if (!("active" in data)) return true; // back-compat
  return data.active === true;
}

export async function bootstrapPublicBookingSettings(
  req: CallableRequest<BootstrapPublicBookingSettingsInput>
) {
  if (!req.auth?.uid) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = safeStr(req.data?.clinicId);
  if (!clinicId) throw new HttpsError("invalid-argument", "clinicId is required.");

  const overrideBaseUrl = asString(req.data?.publicActionBaseUrl, 500);

  const db = admin.firestore();
  const uid = req.auth.uid;

  // ─────────────────────────────
  // Membership + permission gate
  // ─────────────────────────────
  const member = await getMembershipData(db, clinicId, uid);
  if (!member || !isActiveMember(member)) {
    throw new HttpsError("permission-denied", "Inactive or missing membership.");
  }

  if (member.permissions?.["settings.write"] !== true) {
    throw new HttpsError("permission-denied", "Missing settings.write permission.");
  }

  // ─────────────────────────────
  // Clinic existence + metadata
  // ─────────────────────────────
  const clinicRef = db.doc(`clinics/${clinicId}`);
  const clinicSnap = await clinicRef.get();
  if (!clinicSnap.exists) throw new HttpsError("not-found", "Clinic not found.");

  const clinic = (clinicSnap.data() ?? {}) as any;

  const clinicName =
    safeStr(clinic?.profile?.name) ||
    safeStr(clinic?.clinicName) ||
    safeStr(clinic?.name) ||
    "";

  const logoUrl =
    safeStr(clinic?.profile?.logoUrl) ||
    safeStr(clinic?.logoUrl) ||
    "";

  const tzFromClinic =
    safeStr(clinic?.profile?.timezone) ||
    safeStr(clinic?.settings?.timezone) ||
    "Europe/Prague";

  const minNoticeFromClinic =
    typeof clinic?.settings?.bookingRules?.minNoticeMinutes === "number"
      ? clinic.settings.bookingRules.minNoticeMinutes
      : 0;

  const maxAdvanceFromClinic =
    typeof clinic?.settings?.bookingRules?.maxDaysInAdvance === "number"
      ? clinic.settings.bookingRules.maxDaysInAdvance
      : 90;

  // ─────────────────────────────
  // Canonical defaults
  // ─────────────────────────────
  const defaults: any = {
    timezone: tzFromClinic,
    minNoticeMinutes: minNoticeFromClinic,
    maxAdvanceDays: maxAdvanceFromClinic,
    slotStepMinutes: 15,

    weeklyHours: {
      mon: [{ start: "08:00", end: "18:00" }],
      tue: [{ start: "08:00", end: "18:00" }],
      wed: [{ start: "08:00", end: "18:00" }],
      thu: [{ start: "08:00", end: "18:00" }],
      fri: [{ start: "08:00", end: "16:00" }],
      sat: [],
      sun: [],
    },

    corporatePrograms: [],
    publicServiceNames: {},

    // PRIVATE (not mirrored)
    emails: {
      publicActionBaseUrl:
        overrideBaseUrl ?? "https://example.com/public/booking/manage",
      brevo: {
        senderName: clinicName,
        senderEmail: "",
        patientTemplateId: null,
        clinicianTemplateId: null,
        manageBookingTemplateId: null,
      },
      clinicianRecipients: [],
    },

    // SAFE (mirrored)
    patientCopy: {
      whatsappLine: "",
      whatToBring: "",
      arrivalInfo: "",
      cancellationPolicy: "",
      cancellationUrl: "",
    },

    bookingStructure: {
      publicSlotMinutes: 60,
    },

    schemaVersion: 1,
  };

  const settingsRef = db
    .collection("clinics")
    .doc(clinicId)
    .collection("settings")
    .doc("publicBooking");

  const settingsSnap = await settingsRef.get();
  const now = admin.firestore.FieldValue.serverTimestamp();

  // ─────────────────────────────
  // CREATE
  // ─────────────────────────────
  if (!settingsSnap.exists) {
    await settingsRef.set({
      ...defaults,
      createdAt: now,
      createdByUid: uid,
      updatedAt: now,
      updatedByUid: uid,
    });

    await writePublicBookingMirror(clinicId, defaults);

    return {
      ok: true,
      created: true,
      merged: false,
      path: settingsRef.path,
      publicPath: `clinics/${clinicId}/public/config/publicBooking/publicBooking`,
    };
  }

  // ─────────────────────────────
  // MERGE MISSING FIELDS
  // ─────────────────────────────
  const cur = (settingsSnap.data() ?? {}) as any;
  const patch: any = {};

  if (cur.timezone == null) patch.timezone = defaults.timezone;
  if (cur.minNoticeMinutes == null) patch.minNoticeMinutes = defaults.minNoticeMinutes;
  if (cur.maxAdvanceDays == null) patch.maxAdvanceDays = defaults.maxAdvanceDays;
  if (cur.slotStepMinutes == null) patch.slotStepMinutes = defaults.slotStepMinutes;

  if (cur.weeklyHours == null) {
    patch.weeklyHours = defaults.weeklyHours;
  } else {
    const whPatch: any = {};
    for (const d of ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]) {
      if (cur.weeklyHours[d] == null) whPatch[d] = defaults.weeklyHours[d];
    }
    if (Object.keys(whPatch).length) {
      patch.weeklyHours = { ...cur.weeklyHours, ...whPatch };
    }
  }

  if (cur.corporatePrograms == null) patch.corporatePrograms = [];
  if (cur.publicServiceNames == null) patch.publicServiceNames = {};

  if (cur.bookingStructure == null) {
    patch.bookingStructure = defaults.bookingStructure;
  } else if (cur.bookingStructure.publicSlotMinutes == null) {
    patch.bookingStructure = {
      ...cur.bookingStructure,
      publicSlotMinutes: 60,
    };
  }

  if (cur.emails == null) patch.emails = defaults.emails;
  if (cur.patientCopy == null) patch.patientCopy = defaults.patientCopy;

  patch.schemaVersion = cur.schemaVersion ?? 1;
  patch.updatedAt = now;
  patch.updatedByUid = uid;

  const meaningful = Object.keys(patch).filter(
    (k) => !["schemaVersion", "updatedAt", "updatedByUid"].includes(k)
  );

  if (meaningful.length) {
    await settingsRef.set(patch, { merge: true });
  }

  const latestSnap = await settingsRef.get();
  await writePublicBookingMirror(clinicId, latestSnap.data() ?? {});

  return {
    ok: true,
    created: false,
    merged: meaningful.length > 0,
    path: settingsRef.path,
    publicPath: `clinics/${clinicId}/public/config/publicBooking/publicBooking`,
  };
}
