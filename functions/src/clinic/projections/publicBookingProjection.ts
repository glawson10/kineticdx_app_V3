/**
 * Commit 16: Projection builder (private → public mirror).
 * Writes clinics/{clinicId}/public/config/publicBooking/config from
 * clinics/{clinicId}/settings/publicBooking and clinic doc.
 * Event-driven (trigger); no callables write /public/** except optional manual rebuild.
 */

import * as admin from "firebase-admin";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onCall } from "firebase-functions/v2/https";
import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/logger";
import { requireClinicPermission } from "../permissions";
import { sha256Hex } from "./hash";
import { publicBookingConfigDocPath } from "./paths";
import { buildPublicQuestionnaireFlow } from "../questionnaires/questionnaireTemplates";

type AnyMap = Record<string, unknown>;

const DAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;

const BOOKING_RULES_DEFAULTS: Record<string, number | boolean> = {
  slotStepMinutes: 15,
  minNoticeMinutes: 0,
  maxAdvanceDays: 90,
  allowNewPatients: true,
  requireEmail: true,
  requirePhone: false,
  cancellationPolicyHours: 24,
  onlineBookingEnabled: true,
};

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

function safeNum(v: unknown, fallback: number): number {
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? n : fallback;
}

function isObj(v: unknown): v is AnyMap {
  return !!v && typeof v === "object" && !Array.isArray(v);
}

function takeIntervals(list: unknown): Array<{ start: string; end: string }> {
  const out: Array<{ start: string; end: string }> = [];
  if (!Array.isArray(list)) return out;
  for (const it of list) {
    if (!isObj(it)) continue;
    const start = safeStr(it.start);
    const end = safeStr(it.end);
    if (start && end) out.push({ start, end });
  }
  return out;
}

function normalizeWeeklyHours(settings: AnyMap): Record<string, Array<{ start: string; end: string }>> {
  const out: Record<string, Array<{ start: string; end: string }>> = {
    mon: [], tue: [], wed: [], thu: [], fri: [], sat: [], sun: [],
  };
  const wh = settings.weeklyHours;
  if (!isObj(wh)) return out;
  for (const day of DAY_KEYS) {
    const v = wh[day];
    out[day] = Array.isArray(v) ? takeIntervals(v) : [];
  }
  return out;
}

function buildBookingRules(settings: AnyMap): AnyMap {
  const r: AnyMap = { ...BOOKING_RULES_DEFAULTS };
  if (safeNum(settings.slotStepMinutes, NaN) >= 0) r.slotStepMinutes = Number(settings.slotStepMinutes);
  if (safeNum(settings.minNoticeMinutes, NaN) >= 0) r.minNoticeMinutes = Number(settings.minNoticeMinutes);
  if (safeNum(settings.maxAdvanceDays, NaN) >= 0) r.maxAdvanceDays = Number(settings.maxAdvanceDays);
  if (settings.allowNewPatients === true || settings.allowNewPatients === false) r.allowNewPatients = settings.allowNewPatients;
  if (settings.requireEmail === true || settings.requireEmail === false) r.requireEmail = settings.requireEmail;
  if (settings.requirePhone === true || settings.requirePhone === false) r.requirePhone = settings.requirePhone;
  if (safeNum(settings.cancellationPolicyHours, NaN) >= 0) r.cancellationPolicyHours = Number(settings.cancellationPolicyHours);
  if (settings.onlineBookingEnabled === true || settings.onlineBookingEnabled === false) r.onlineBookingEnabled = settings.onlineBookingEnabled;
  return r;
}

/** Per-location opening hours (same shape as clinic weeklyHours). Missing or empty = no extra restriction. */
export type LocationOpeningHoursMap = Record<string, Record<string, Array<{ start: string; end: string }>>>;

export type PublicBookingPublicConfigV1 = {
  schemaVersion: 1;
  clinicId: string;
  updatedAt: admin.firestore.FieldValue;
  source: {
    publicBookingUpdatedAt: admin.firestore.Timestamp | null;
    openingHoursUpdatedAt: admin.firestore.Timestamp | null;
    clinicUpdatedAt: admin.firestore.Timestamp | null;
  };
  jurisdiction: { timezone: string; currencyCode: string };
  bookingRules: AnyMap;
  weeklyHours: Record<string, Array<{ start: string; end: string }>>;
  /** Location-specific opening hours. Key = locationId. Empty/missing = use clinic hours only for that location. */
  locationOpeningHours: LocationOpeningHoursMap;
  hash: string;
};

/**
 * Build the v1 public config payload (no PII). Caller sets updatedAt when writing.
 */
function normalizeLocationOpeningHours(locations: Array<{ id: string; data: AnyMap }>): LocationOpeningHoursMap {
  const out: LocationOpeningHoursMap = {};
  for (const loc of locations) {
    const wh = loc.data?.weeklyHours;
    if (!isObj(wh)) continue;
    const normalized: Record<string, Array<{ start: string; end: string }>> = {};
    for (const day of DAY_KEYS) {
      const v = wh[day];
      normalized[day] = Array.isArray(v) ? takeIntervals(v) : [];
    }
    const hasAny = DAY_KEYS.some((d) => (normalized[d]?.length ?? 0) > 0);
    if (hasAny) out[loc.id] = normalized;
  }
  return out;
}

export function buildPublicBookingConfigV1(args: {
  clinicId: string;
  settingsDoc: AnyMap | null;
  settingsUpdatedAt: admin.firestore.Timestamp | null;
  clinicDoc: AnyMap | null;
  clinicUpdatedAt: admin.firestore.Timestamp | null;
  questionnaireFlow: AnyMap;
  locationOpeningHours?: LocationOpeningHoursMap;
}): Omit<PublicBookingPublicConfigV1, "updatedAt"> & { updatedAt: admin.firestore.FieldValue } {
  const settings = isObj(args.settingsDoc) ? args.settingsDoc : {};
  const clinic = isObj(args.clinicDoc) ? args.clinicDoc : {};

  const timezone = safeStr(clinic.timezone ?? (clinic.profile as AnyMap)?.timezone) || "UTC";
  const currencyCode = safeStr(clinic.currencyCode ?? (clinic.profile as AnyMap)?.currencyCode) || "EUR";

  const bookingRules = buildBookingRules(settings);
  bookingRules.questionnaireFlow = args.questionnaireFlow;
  const weeklyHours = normalizeWeeklyHours(settings);
  const locationOpeningHours = args.locationOpeningHours ?? {};

  const payloadForHash = {
    schemaVersion: 1 as const,
    clinicId: args.clinicId,
    source: {
      publicBookingUpdatedAt: args.settingsUpdatedAt,
      openingHoursUpdatedAt: args.settingsUpdatedAt,
      clinicUpdatedAt: args.clinicUpdatedAt,
    },
    jurisdiction: { timezone, currencyCode },
    bookingRules,
    weeklyHours,
    locationOpeningHours,
  };
  const hash = sha256Hex(payloadForHash);

  return {
    schemaVersion: 1,
    clinicId: args.clinicId,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    source: {
      publicBookingUpdatedAt: args.settingsUpdatedAt,
      openingHoursUpdatedAt: args.settingsUpdatedAt,
      clinicUpdatedAt: args.clinicUpdatedAt,
    },
    jurisdiction: { timezone, currencyCode },
    bookingRules,
    weeklyHours,
    locationOpeningHours,
    hash,
  };
}

/**
 * Write the minimal config doc. Idempotent: same inputs → same hash → same content.
 * Reads all locations for the clinic and includes locationOpeningHours in the config.
 */
export async function writePublicBookingConfigProjection(
  clinicId: string,
  settingsSnap: admin.firestore.DocumentSnapshot | null,
  clinicSnap: admin.firestore.DocumentSnapshot | null
): Promise<void> {
  const db = admin.firestore();
  const settingsData = settingsSnap?.exists ? (settingsSnap.data() ?? {}) as AnyMap : {};
  const settingsUpdatedAt = settingsSnap?.exists && settingsSnap?.get("updatedAt")
    ? (settingsSnap.get("updatedAt") as admin.firestore.Timestamp)
    : null;
  const clinicData = clinicSnap?.exists ? (clinicSnap.data() ?? {}) as AnyMap : {};
  const clinicUpdatedAt = clinicSnap?.exists && clinicSnap?.get("updatedAt")
    ? (clinicSnap.get("updatedAt") as admin.firestore.Timestamp)
    : null;

  const locationsSnap = await db.collection(`clinics/${clinicId}/locations`).get();
  const locations = locationsSnap.docs.map((d) => ({ id: d.id, data: (d.data() ?? {}) as AnyMap }));
  const locationOpeningHours = normalizeLocationOpeningHours(locations);

  const questionnaireFlow = await buildPublicQuestionnaireFlow(
    db,
    clinicId,
    settingsData.questionnaireFlow
  );

  const payload = buildPublicBookingConfigV1({
    clinicId,
    settingsDoc: settingsData,
    settingsUpdatedAt,
    clinicDoc: clinicData,
    clinicUpdatedAt,
    questionnaireFlow,
    locationOpeningHours,
  });

  const ref = db.doc(publicBookingConfigDocPath(clinicId));
  await ref.set(payload, { merge: true });

  logger.info("[projection/publicBooking] wrote config", {
    clinicId,
    hash: payload.hash,
    locationCount: Object.keys(locationOpeningHours).length,
    source: {
      publicBookingUpdatedAt: settingsUpdatedAt?.toMillis?.() ?? null,
      clinicUpdatedAt: clinicUpdatedAt?.toMillis?.() ?? null,
    },
  });
}

/**
 * Trigger: on write to clinics/{clinicId}/settings/publicBooking.
 * Writes minimal public config to .../public/config/publicBooking/config.
 * On delete: write defaults with source.publicBookingUpdatedAt = null.
 *
 * Data flow (opening hours correlation):
 * - Opening hours UI saves via settings.updatePublicBookingConfig (or updateClinicWeeklyHoursFn wrapper) → settings/publicBooking.
 * - This trigger runs and writes weeklyHours (and booking rules) to public/config/publicBooking/config.
 * - listPublicSlotsFn and clinician calendar read only from that config; public booking slots use it too.
 * - Flutter may also call projectionsRebuildPublicBookingConfig after save for immediate sync.
 */
export const onPublicBookingSettingsWriteProjection = onDocumentWritten(
  {
    region: "europe-west3",
    document: "clinics/{clinicId}/settings/publicBooking",
  },
  async (event) => {
    const clinicId = safeStr(event.params?.clinicId);
    if (!clinicId) return;

    const afterSnap = event.data?.after;
    const settingsSnap = afterSnap && afterSnap.exists ? afterSnap : null;
    const settingsData = settingsSnap ? (settingsSnap.data() ?? {}) as AnyMap : {};

    const db = admin.firestore();
    const clinicSnap = await db.doc(`clinics/${clinicId}`).get();

    if (!settingsSnap && afterSnap && !afterSnap.exists) {
      await writePublicBookingConfigProjection(clinicId, null, clinicSnap);
      logger.info("[projection/publicBooking] settings deleted, wrote defaults", { clinicId });
      return;
    }

    await writePublicBookingConfigProjection(clinicId, settingsSnap ?? null, clinicSnap);
  }
);

/**
 * Manual rebuild callable. Permission: settings.write.
 * Runs the same projection once (reads settings + clinic + locations, writes public config).
 */
export const projectionsRebuildPublicBookingConfig = onCall(
  { region: "europe-west3" },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const clinicId = safeStr((request.data as AnyMap)?.clinicId);
    if (!clinicId) {
      throw new HttpsError("invalid-argument", "clinicId is required.");
    }

    const db = admin.firestore();
    await requireClinicPermission(db, clinicId, request.auth.uid, "settings.write");
    const [settingsSnap, clinicSnap] = await Promise.all([
      db.doc(`clinics/${clinicId}/settings/publicBooking`).get(),
      db.doc(`clinics/${clinicId}`).get(),
    ]);

    await writePublicBookingConfigProjection(clinicId, settingsSnap, clinicSnap);

    return { ok: true, clinicId };
  }
);

/**
 * Trigger: on write to clinics/{clinicId}/locations/{locationId}.
 * Re-runs the public booking config projection so locationOpeningHours in the mirror stays in sync.
 */
export const onLocationWritePublicBookingConfigProjection = onDocumentWritten(
  {
    region: "europe-west3",
    document: "clinics/{clinicId}/locations/{locationId}",
  },
  async (event) => {
    const clinicId = safeStr(event.params?.clinicId);
    if (!clinicId) return;

    const db = admin.firestore();
    const [settingsSnap, clinicSnap] = await Promise.all([
      db.doc(`clinics/${clinicId}/settings/publicBooking`).get(),
      db.doc(`clinics/${clinicId}`).get(),
    ]);

    await writePublicBookingConfigProjection(clinicId, settingsSnap, clinicSnap);
    logger.info("[projection/publicBooking] location write, refreshed config", { clinicId });
  }
);
