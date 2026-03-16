// functions/src/public/mirrorPublicBooking.ts
// CP-P2: Public mirror includes curated locations, practitioners, appointmentTypes (active + visibility).
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/logger";
import { onDocumentWritten } from "firebase-functions/v2/firestore";

import { buildPublicBookingProjection } from "../clinic/publicProjection";
import { buildPublicQuestionnaireFlow } from "../clinic/questionnaires/questionnaireTemplates";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

type AnyMap = Record<string, any>;

function safeStr(v: unknown): string {
  return typeof v === "string" ? v.trim() : (v ?? "").toString().trim();
}

function asMap(v: unknown): AnyMap {
  return v && typeof v === "object" ? (v as AnyMap) : {};
}

const PUBLIC_PATH_PREFIX = "public/";

/** Asserts all write paths are under clinics/{clinicId}/public/** (projection boundary). */
function assertOnlyPublicWrites(clinicId: string, path: string): void {
  const expectedPrefix = `clinics/${clinicId}/${PUBLIC_PATH_PREFIX}`;
  if (!path.startsWith(expectedPrefix)) {
    throw new Error(
      `runPublicBookingMirrorForClinic may only write under clinics/{clinicId}/public/**. Got: ${path}`
    );
  }
}

const DAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;

/** When private config is deleted, write a safe empty projection (no admin/private fields). */
function buildSafeDefaultPublicProjection(clinicId: string): AnyMap {
  const emptyWeeklyHours = Object.fromEntries(DAY_KEYS.map((k) => [k, []]));
  return {
    timezone: "Europe/London",
    weeklyHours: emptyWeeklyHours,
    slotStepMinutes: 15,
    minNoticeMinutes: 60,
    maxAdvanceDays: 365,
    schemaVersion: 1,
    locations: [],
    practitioners: [],
    appointmentTypes: [],
  };
}

/** Compare payloads for no-op; exclude updatedAt/updatedBy. */
function payloadsEqual(a: AnyMap, b: AnyMap): boolean {
  const strip = (o: AnyMap) => {
    const out = { ...o };
    delete out.updatedAt;
    delete out.updatedBy;
    return out;
  };
  return JSON.stringify(strip(a)) === JSON.stringify(strip(b));
}

/** Recursively remove undefined values so Firestore accepts the document. Leaves Timestamp/FieldValue intact. */
function removeUndefined<T>(val: T): T {
  if (val === undefined) return undefined as T;
  if (val === null || typeof val !== "object") return val;
  if (val instanceof admin.firestore.Timestamp) return val;
  if (Array.isArray(val)) return val.map((item) => removeUndefined(item)) as T;
  // Plain object only; do not recurse into FieldValue or other sentinels
  if (Object.getPrototypeOf(val) !== Object.prototype) return val;
  const out: AnyMap = {};
  for (const [k, v] of Object.entries(val as AnyMap)) {
    if (v === undefined) continue;
    out[k] = removeUndefined(v);
  }
  return out as T;
}

/**
 * CP-P2: Run mirror for a clinic (trigger or callable). Reads settings/publicBooking, locations,
 * practitioners, appointmentTypes; writes public doc only.
 *
 * Main public booking projection: clinics/{clinicId}/public/config/publicBooking/publicBooking.
 * This is the single doc written by onPublicBookingConfigMirror when settings/publicBooking
 * changes; listPublicSlots and public booking UI read from here (no direct client writes).
 */
export async function runPublicBookingMirrorForClinic(clinicId: string): Promise<void> {
  const cid = safeStr(clinicId);
  if (!cid) return;

  const publicDocPath = `clinics/${cid}/public/config/publicBooking/publicBooking`;
  assertOnlyPublicWrites(cid, publicDocPath);

  const publicDocRef = db.doc(publicDocPath);

  const settingsRef = db.doc(`clinics/${cid}/settings/publicBooking`);
  const settingsSnap = await settingsRef.get().catch(() => null);
  if (!settingsSnap?.exists) {
    // Private config deleted: write safe empty projection (do not hard-delete public doc).
    const safeDefaults = buildSafeDefaultPublicProjection(cid);
    const defaultPayload = removeUndefined({
      ...safeDefaults,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: "mirrorPublicBooking-defaults",
    });
    await publicDocRef.set(defaultPayload, { merge: true });
    logger.info("mirrorPublicBooking: source deleted, wrote safe defaults", { clinicId: cid });
    return;
  }

  const publicBookingSettingsDoc = asMap(settingsSnap.data());
  const publicQuestionnaireFlow = await buildPublicQuestionnaireFlow(
    db,
    cid,
    publicBookingSettingsDoc.questionnaireFlow
  );
  const publicBookingSettingsForProjection: AnyMap = {
    ...publicBookingSettingsDoc,
    questionnaireFlow: publicQuestionnaireFlow,
  };

  const clinicRef = db.doc(`clinics/${cid}`);
  const servicesCol = db.collection(`clinics/${cid}/services`);
  const practitionersCol = db.collection(`clinics/${cid}/practitioners`);
  const membersCol = db.collection(`clinics/${cid}/members`);
  const locationsCol = db.collection(`clinics/${cid}/locations`);
  const appointmentTypesCol = db.collection(`clinics/${cid}/appointmentTypes`);
  const staffProfilesCol = db.collection(`clinics/${cid}/staffProfiles`);

  const membershipsCol = db.collection(`clinics/${cid}/memberships`);
  const [clinicSnap, servicesSnap, practitionersSnap, membersSnap, membershipsSnap, locationsSnap, typesSnap, staffProfilesSnap] =
    await Promise.all([
      clinicRef.get().catch(() => null),
      servicesCol.where("active", "==", true).get().catch(() => null),
      practitionersCol.get().catch(() => null),
      membersCol.get().catch(() => null),
      membershipsCol.get().catch(() => null),
      locationsCol.get().catch(() => null),
      appointmentTypesCol.get().catch(() => null),
      staffProfilesCol.get().catch(() => null),
    ]);

  const clinicDoc: AnyMap = clinicSnap?.exists ? asMap(clinicSnap.data()) : {};
  const profile = asMap(clinicDoc.profile);
  const clinicName =
    safeStr(clinicDoc.name) ||
    safeStr(profile.name) ||
    safeStr(clinicDoc.clinicName) ||
    safeStr(clinicDoc.publicName) ||
    "Clinic";
  const logoUrl =
    safeStr(clinicDoc.logoUrl) ||
    safeStr(profile.logoUrl) ||
    safeStr(asMap(clinicDoc.branding).logoUrl) ||
    safeStr(asMap(asMap(clinicDoc.settings).appearance).logoUrl) ||
    "";

  const services =
    servicesSnap?.docs.map((d) => ({ id: d.id, data: asMap(d.data()) })) ?? [];
  // Merge members (canonical) + memberships (legacy); prefer members.
  const memberById = new Map<string, { id: string; data: AnyMap }>();
  for (const d of membersSnap?.docs ?? []) {
    memberById.set(d.id, { id: d.id, data: asMap(d.data()) });
  }
  for (const d of membershipsSnap?.docs ?? []) {
    if (!memberById.has(d.id)) {
      memberById.set(d.id, { id: d.id, data: asMap(d.data()) });
    }
  }
  const memberships = Array.from(memberById.values());

  // Pass all practitioners; buildPublicPractitioners filters (same as settings trigger).
  const practitioners =
    practitionersSnap?.docs.map((d) => ({ id: d.id, data: asMap(d.data()) })) ?? [];

  const staffProfiles =
    staffProfilesSnap?.docs.map((d) => ({ id: d.id, data: asMap(d.data()) })) ?? [];

  const input = {
    clinicId: cid,
    clinicName,
    logoUrl,
    clinicDoc,
    publicBookingSettingsDoc: publicBookingSettingsForProjection,
    services,
    practitioners,
    memberships,
    staffProfiles,
  };

  const projection = buildPublicBookingProjection(input as any);

  // CP-P2: Curated lists for public booking (active + visibility only; no addresses/PII)
  const locationsList =
    locationsSnap?.docs
      ?.filter((d) => {
        const dta = d.data();
        return dta?.active === true && dta?.showInOnlineBooking === true;
      })
      .map((d) => {
        const dta = d.data() || {};
        return { id: d.id, name: safeStr(dta.name) || d.id };
      }) ?? [];

  const practitionersList = (projection as AnyMap).practitioners ?? [];

  const appointmentTypesList =
    typesSnap?.docs
      ?.filter((d) => {
        const dta = d.data();
        return dta?.active === true && dta?.showInOnlineBooking === true;
      })
      .map((d) => {
        const dta = d.data() || {};
        // Backend stores durationMinutes; mirror exposes defaultDurationMinutes for public consumers.
        const durationMinutes =
          typeof dta.durationMinutes === "number" ? dta.durationMinutes : 30;
        const allowedLocs = Array.isArray(dta.allowedLocationIds)
          ? dta.allowedLocationIds.filter((x: any) => typeof x === "string" && x.trim())
          : undefined;
        const allowedPractitioners = Array.isArray(dta.allowedPractitionerIds)
          ? dta.allowedPractitionerIds.filter((x: any) => typeof x === "string" && x.trim())
          : undefined;
        return {
          id: d.id,
          name: safeStr(dta.name) || d.id,
          defaultDurationMinutes: durationMinutes,
          description: safeStr(dta.description) || undefined,
          defaultPrice: typeof dta.defaultPrice === "number" ? dta.defaultPrice : undefined,
          colorHex: safeStr(dta.colorHex) || undefined,
          allowedLocationIds: allowedLocs && allowedLocs.length > 0 ? allowedLocs : undefined,
          telehealth: dta.telehealth === true,
          allowedPractitionerIds: allowedPractitioners && allowedPractitioners.length > 0 ? allowedPractitioners : undefined,
        };
      }) ?? [];

  const practitionersForDoc = practitionersList.map((p: AnyMap) => ({
    id: p.id,
    displayName: p.displayName ?? p.id,
    title: p.title ?? p.designation ?? undefined,
    photoUrl: p.photoUrl ?? undefined,
    bio: p.bio ?? undefined,
    serviceIdsAllowed: Array.isArray(p.serviceIdsAllowed) ? p.serviceIdsAllowed : undefined,
    sortOrder: typeof p.sortOrder === "number" ? p.sortOrder : undefined,
    allowedLocationIds: Array.isArray(p.allowedLocationIds) ? p.allowedLocationIds : undefined,
  }));

  const newPayload: AnyMap = {
    ...projection,
    locations: locationsList,
    practitioners: practitionersForDoc,
    appointmentTypes: appointmentTypesList,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedBy: "mirrorPublicBooking-v2",
  };

  const currentSnap = await publicDocRef.get().catch(() => null);
  if (currentSnap?.exists) {
    const currentData = asMap(currentSnap.data());
    if (payloadsEqual(newPayload, currentData)) {
      logger.info("mirrorPublicBooking: unchanged, skip write", { clinicId: cid });
      return;
    }
  }

  const payloadToWrite = removeUndefined(newPayload);
  await publicDocRef.set(payloadToWrite, { merge: true });

  if (practitionersList.length === 0) {
    const withVisibility = practitionersSnap?.docs?.filter(
      (d) => d.data()?.showInPublicBooking === true && d.data()?.active !== false
    ).length ?? 0;
    const memberByIdLog = new Map<string, AnyMap>();
    for (const m of memberships) {
      memberByIdLog.set(m.id, m.data);
    }
    const whyExcluded: Array<{ id: string; show: boolean; active: boolean; activeForBooking: boolean; memStatus?: string; memActive?: boolean }> = [];
    for (const d of practitionersSnap?.docs ?? []) {
      const dta = d.data() ?? {};
      const show = dta.showInPublicBooking === true;
      if (!show) continue;
      const mem = memberByIdLog.get(d.id);
      const memStatus = mem ? (safeStr(mem.status).toLowerCase() || (mem.active === true ? "active" : "inactive")) : "none";
      const memActive = memStatus === "none" || memStatus === "active";
      whyExcluded.push({
        id: d.id,
        show,
        active: dta.active !== false,
        activeForBooking: dta.activeForBooking !== false,
        memStatus,
        memActive,
      });
    }
    logger.warn("mirrorPublicBooking: 0 practitioners in mirror", {
      clinicId: cid,
      practitionersWithPublicVisibility: withVisibility,
      totalPractitioners: practitionersSnap?.size ?? 0,
      membersCount: membersSnap?.size ?? 0,
      membershipsCount: membershipsSnap?.size ?? 0,
      whyExcluded,
    });
  } else {
    logger.info("mirrorPublicBooking: mirror updated", {
      clinicId: cid,
      locations: locationsList.length,
      practitioners: practitionersList.length,
      appointmentTypes: appointmentTypesList.length,
    });
  }
}

/** When a practitioner doc is written (e.g. showInPublicBooking toggled), refresh the public mirror so public booking sees the change. */
export const onPractitionerWritten = onDocumentWritten(
  {
    region: "europe-west3",
    document: "clinics/{clinicId}/practitioners/{practitionerId}",
  },
  async (event) => {
    const clinicId = safeStr(event.params?.clinicId);
    if (!clinicId) return;
    logger.info("onPractitionerWritten: refreshing public mirror", { clinicId });
    await runPublicBookingMirrorForClinic(clinicId);
  }
);

// Trigger on settings/publicBooking is onPublicBookingConfigMirror (see onPublicBookingConfigMirror.ts).
