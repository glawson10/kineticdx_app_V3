// functions/src/clinic/createClinic.ts
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

import {
  seedDefaultRoles,
  seedDefaultLocation,
  seedStarterServices,
} from "./seedDefaults";
import { ownerRolePermissions } from "./roleTemplates";
import { seedDefaultAssessmentPacks } from "../clinic/seedAssessmentPacks";

// ✅ SINGLE BRIDGE writer (the only code that writes /public/config/**)
import { writePublicBookingMirror } from "./writePublicBookingMirror";

type CreateClinicInput = {
  name: string;
  timezone?: string;
  defaultLanguage?: string;
};

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

function normEmail(v: unknown): string {
  return (v ?? "").toString().trim().toLowerCase();
}

function pickDisplayNameFromAuthToken(token: any, emailLower: string): string {
  const candidates = [
    token?.name,
    token?.display_name,
    token?.displayName,
    token?.["display_name"],
    token?.["displayName"],
  ];
  for (const c of candidates) {
    const s = safeStr(c);
    if (s) return s;
  }
  // fallback: email local part
  const local = emailLower.split("@")[0] ?? "";
  return local ? local : "Owner";
}

// ✅ Option D allowlist (platform-scoped)
// /platformAuthAllowlist/{emailLower} { enabled: true, ... }
const ALLOWLIST_COLLECTION = "platformAuthAllowlist";

/**
 * Canonical weeklyHours shape (authoritative settings doc):
 * weeklyHours: { mon:[{start,end}], tue:[{start,end}], ... sun:[] }
 */
function defaultWeeklyHours() {
  return {
    mon: [{ start: "08:00", end: "18:00" }],
    tue: [{ start: "08:00", end: "18:00" }],
    wed: [{ start: "08:00", end: "18:00" }],
    thu: [{ start: "08:00", end: "18:00" }],
    fri: [{ start: "08:00", end: "16:00" }],
    sat: [],
    sun: [],
  };
}

/**
 * Optional legacy clinic-internal openingHours.days format.
 * (Kept only for older internal readers; NOT used for public availability.)
 */
function defaultOpeningHoursDays() {
  return [
    { day: "mon", intervals: [{ start: "08:00", end: "18:00" }] },
    { day: "tue", intervals: [{ start: "08:00", end: "18:00" }] },
    { day: "wed", intervals: [{ start: "08:00", end: "18:00" }] },
    { day: "thu", intervals: [{ start: "08:00", end: "18:00" }] },
    { day: "fri", intervals: [{ start: "08:00", end: "16:00" }] },
    { day: "sat", intervals: [] },
    { day: "sun", intervals: [] },
  ];
}

/**
 * createClinic seeds:
 * - clinics/{clinicId} (clinic root doc)
 * - clinics/{clinicId}/settings/publicBooking (canonical, writeable)
 * - clinics/{clinicId}/memberships/{uid} (canonical membership)
 * - users/{uid}/memberships/{clinicId} (index mirror)
 *
 * Public mirror is written by the SINGLE BRIDGE:
 * - clinics/{clinicId}/public/config/publicBooking/publicBooking (read-only)
 */
export async function createClinic(req: CallableRequest<CreateClinicInput>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const db = admin.firestore();
  const uid = req.auth.uid;

  // ✅ Option D: allowlist gate for clinic creation
  const email = normEmail(req.auth.token.email);
  if (!email) {
    throw new HttpsError("failed-precondition", "User email not available.");
  }

  const allowSnap = await db.collection(ALLOWLIST_COLLECTION).doc(email).get();
  if (!allowSnap.exists || allowSnap.data()?.enabled !== true) {
    throw new HttpsError(
      "permission-denied",
      "Clinic creation is restricted. Contact support to be enabled."
    );
  }

  const displayName = pickDisplayNameFromAuthToken(req.auth.token, email);

  const name = safeStr(req.data?.name);
  const timezone = safeStr(req.data?.timezone) || "Europe/Prague";
  const defaultLanguage = safeStr(req.data?.defaultLanguage) || "en";

  if (!name) throw new HttpsError("invalid-argument", "Clinic name is required.");
  if (name.length > 120)
    throw new HttpsError("invalid-argument", "Clinic name too long.");

  const clinicRef = db.collection("clinics").doc(); // auto ID
  const clinicId = clinicRef.id;

  const now = admin.firestore.FieldValue.serverTimestamp();

  // ─────────────────────────────────────────────────────────────
  // Clinic root doc (legacy / internal)
  // ─────────────────────────────────────────────────────────────
  const clinicDoc = {
    // ✅ creator identity (needed for owner bootstrapping + audits)
    createdByUid: uid,
    createdByEmail: email,
    createdByName: displayName,

    profile: {
      name,
      logoUrl: "",
      address: "",
      phone: "",
      email: "",
      timezone,
      defaultLanguage,
    },
    settings: {
      openingHours: {
        weekStart: "mon",
        daysOrder: "mon",
        days: defaultOpeningHoursDays(),
      },
      bookingRules: {
        maxDaysInAdvance: 90,
        minNoticeMinutes: 120,
        cancelNoPenaltyHours: 24,
        patientsCanReschedule: false,
        allowGroupOverbook: true,
        allowOverlapWithAssistant: true,
        preventResourceDoubleBooking: true,
      },
      bookingStructure: {
        defaultSlotMinutes: 20,
        adminGridMinutes: 15,
        publicSlotMinutes: 60,
        slotMinutesByType: {},
        bufferBeforeFirst: 0,
        bufferBetween: 5,
        bufferAfterLast: 0,
      },
      appearance: {
        bookedColor: 0xFF3B82F6,
        attendedColor: 0xFF10B981,
        cancelledColor: 0xFFF59E0B,
        noShowColor: 0xFFEF4444,
        nowLineColor: 0xFF111827,
        slotHeight: 48,
        showWeekends: true,
      },
      billing: {
        defaultFee: 0.0,
        vatPercent: 0.0,
        invoicePrefix: "",
      },
      communicationDefaults: {
        senderName: name,
        senderEmail: "",
      },
      security: {
        allowNewPatients: true,
        requireConsent: true,
      },
      notes: {
        defaults: {
          initialTemplate: "standard",
          followupTemplate: "standard",
        },
        objective: {
          enabledTestIdsByRegion: {},
          enabledOutcomeMeasureIds: [],
        },
      },
    },
    status: {
      active: true,
      plan: "free",
      createdAt: now,
      updatedAt: now,
    },
    ownerUid: uid,
    schemaVersion: 3,
  };

  // ─────────────────────────────────────────────────────────────
  // Membership docs (canonical + user index)
  // ─────────────────────────────────────────────────────────────
  const membershipRef = clinicRef.collection("memberships").doc(uid);

  // Optional: keep legacy doc for old clients during migration window
  const legacyMemberRef = clinicRef.collection("members").doc(uid);

  const userMembershipRef = db
    .collection("users")
    .doc(uid)
    .collection("memberships")
    .doc(clinicId);

  const membershipDoc = {
    role: "owner",
    roleId: "owner", // back-compat
    displayName, // ✅ so staff list shows name
    invitedEmail: email, // ✅ helpful for staff UI + debugging
    permissions: ownerRolePermissions(),
    status: "active",
    active: true, // back-compat
    createdAt: now,
    updatedAt: now,
    createdByUid: uid,
    updatedByUid: uid,
  };

  const userMembershipDoc = {
    clinicNameCache: name,
    role: "owner",
    roleId: "owner",
    status: "active",
    active: true,
    createdAt: now,
  };

  // ─────────────────────────────────────────────────────────────
  // Starter data
  // ─────────────────────────────────────────────────────────────
  const roles = seedDefaultRoles();
  const location = seedDefaultLocation();
  const services = seedStarterServices();
  const packs = seedDefaultAssessmentPacks();

  // ─────────────────────────────────────────────────────────────
  // Canonical settings doc (clinic-editable)
  // clinics/{clinicId}/settings/publicBooking
  // ─────────────────────────────────────────────────────────────
  const publicBookingSettingsDefaults = {
    timezone,

    // Keep these top-level fields if clients already use them
    minNoticeMinutes: clinicDoc.settings.bookingRules.minNoticeMinutes,
    maxAdvanceDays: clinicDoc.settings.bookingRules.maxDaysInAdvance,
    slotStepMinutes: 15,

    // ✅ Canonical availability used by projection (and should be edited by UI)
    weeklyHours: defaultWeeklyHours(),

    // ✅ Keep booking rules/structure inside settings too (projection reads these)
    bookingRules: clinicDoc.settings.bookingRules,
    bookingStructure: clinicDoc.settings.bookingStructure,

    corporatePrograms: [],
    publicServiceNames: {},

    // Private email config (stays PRIVATE; projection must never expose this)
    emails: {
      publicActionBaseUrl: "https://example.com/public/booking/manage",
      brevo: {
        senderName: name,
        senderEmail: "",
        patientTemplateId: null,
        clinicianTemplateId: null,
        manageBookingTemplateId: null,
      },
      clinicianRecipients: [],
    },

    // Safe patient copy (projection may include)
    patientCopy: {
      whatsappLine: "",
      whatToBring: "",
      arrivalInfo: "",
      cancellationPolicy: "",
      cancellationUrl: "",
    },

    schemaVersion: 1,
    createdAt: now,
    createdByUid: uid,
    updatedAt: now,
    updatedByUid: uid,
  };

  const publicBookingSettingsRef = clinicRef
    .collection("settings")
    .doc("publicBooking");

  // ─────────────────────────────────────────────────────────────
  // Batch write (seed clinic + canonical settings + starter data)
  // ─────────────────────────────────────────────────────────────
  const batch = db.batch();

  // Core clinic + memberships
  batch.set(clinicRef, clinicDoc);

  // ✅ Canonical membership (required)
  batch.set(membershipRef, membershipDoc);

  // ✅ Legacy membership (optional during migration)
  batch.set(legacyMemberRef, {
    roleId: "owner",
    displayName, // ✅ keep consistent
    invitedEmail: email, // ✅ keep consistent
    permissions: ownerRolePermissions(),
    active: true,
    createdAt: now,
    updatedAt: now,
    createdByUid: uid,
    updatedByUid: uid,
  });

  // User index
  batch.set(userMembershipRef, userMembershipDoc);

  // Seed canonical settings/publicBooking (truth)
  batch.set(publicBookingSettingsRef, publicBookingSettingsDefaults);

  // Seed roles
  for (const r of roles) {
    batch.set(clinicRef.collection("roles").doc(r.id), r.data);
  }

  // Seed location
  batch.set(clinicRef.collection("locations").doc(location.id), {
    ...location.data,
    createdAt: now,
    updatedAt: now,
  });

  // Seed services
  for (const s of services) {
    batch.set(clinicRef.collection("services").doc(s.id), {
      ...s.data,
      createdAt: now,
      updatedAt: now,
    });
  }

  // Seed assessment packs
  for (const p of packs) {
    const data = { ...p.data } as any;
    if (data.createdAt === "SERVER_TIMESTAMP") data.createdAt = now;
    if (data.updatedAt === "SERVER_TIMESTAMP") data.updatedAt = now;
    batch.set(clinicRef.collection("assessmentPacks").doc(p.id), data);
  }

  await batch.commit();

  // ─────────────────────────────────────────────────────────────
  // ✅ SINGLE BRIDGE: write the public mirror
  // clinics/{clinicId}/public/config/publicBooking/publicBooking
  // ─────────────────────────────────────────────────────────────
  await writePublicBookingMirror(clinicId, publicBookingSettingsDefaults);

  return { clinicId };
}
