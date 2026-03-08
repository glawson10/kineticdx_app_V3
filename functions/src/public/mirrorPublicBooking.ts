// functions/src/public/mirrorPublicBooking.ts
// CP-P2: Public mirror includes curated locations, practitioners, appointmentTypes (active + showInOnlineBooking).
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/logger";
import { onDocumentWritten } from "firebase-functions/v2/firestore";

import { buildPublicBookingProjection } from "../clinic/publicProjection";

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

/** CP-P2: Run mirror for a clinic (trigger or callable). Reads settings/publicBooking, locations, practitioners, appointmentTypes; writes public doc only. */
export async function runPublicBookingMirrorForClinic(clinicId: string): Promise<void> {
  const cid = safeStr(clinicId);
  if (!cid) return;

  const publicDocPath = `clinics/${cid}/public/config/publicBooking/publicBooking`;
  assertOnlyPublicWrites(cid, publicDocPath);

  const publicDocRef = db.doc(publicDocPath);

  const settingsRef = db.doc(`clinics/${cid}/settings/publicBooking`);
  const settingsSnap = await settingsRef.get().catch(() => null);
  if (!settingsSnap?.exists) {
    await publicDocRef.delete().catch(() => {});
    return;
  }

  const publicBookingSettingsDoc = asMap(settingsSnap.data());

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
    publicBookingSettingsDoc,
    services,
    practitioners,
    memberships,
    staffProfiles,
  };

  const projection = buildPublicBookingProjection(input as any);

  // CP-P2: Curated lists for public booking (active + showInOnlineBooking only; no addresses/PII)
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
        return {
          id: d.id,
          name: safeStr(dta.name) || d.id,
          defaultDurationMinutes: durationMinutes,
          description: safeStr(dta.description) || undefined,
          defaultPrice: typeof dta.defaultPrice === "number" ? dta.defaultPrice : undefined,
          colorHex: safeStr(dta.colorHex) || undefined,
          allowedLocationIds: allowedLocs && allowedLocs.length > 0 ? allowedLocs : undefined,
        };
      }) ?? [];

  await publicDocRef.set(
    {
      ...projection,
      locations: locationsList,
      practitioners: practitionersList.map((p: AnyMap) => ({
        id: p.id,
        displayName: p.displayName ?? p.id,
        title: p.title ?? p.designation ?? undefined,
        photoUrl: p.photoUrl ?? undefined,
        bio: p.bio ?? undefined,
        serviceIdsAllowed: Array.isArray(p.serviceIdsAllowed) ? p.serviceIdsAllowed : undefined,
        sortOrder: typeof p.sortOrder === "number" ? p.sortOrder : undefined,
        allowedLocationIds: Array.isArray(p.allowedLocationIds) ? p.allowedLocationIds : undefined,
      })),
      appointmentTypes: appointmentTypesList,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: "mirrorPublicBooking-v2",
    },
    { merge: true }
  );

  if (practitionersList.length === 0) {
    const withVisibility = practitionersSnap?.docs?.filter(
      (d) => d.data()?.showInOnlineBooking === true && d.data()?.active !== false
    ).length ?? 0;
    const memberByIdLog = new Map<string, AnyMap>();
    for (const m of memberships) {
      memberByIdLog.set(m.id, m.data);
    }
    const whyExcluded: Array<{ id: string; show: boolean; active: boolean; activeForBooking: boolean; memStatus?: string; memActive?: boolean }> = [];
    for (const d of practitionersSnap?.docs ?? []) {
      const dta = d.data() ?? {};
      const show = dta.showInOnlineBooking === true;
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
      practitionersWithShowInOnlineBooking: withVisibility,
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

/** When a practitioner doc is written (e.g. showInOnlineBooking toggled), refresh the public mirror so public booking sees the change. */
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

export const onPublicBookingSettingsWrite = onDocumentWritten(
  {
    region: "europe-west3",
    document: "clinics/{clinicId}/settings/publicBooking",
  },
  async (event) => {
    const clinicId = safeStr(event.params?.clinicId);
    if (!clinicId) {
      logger.warn("mirrorPublicBooking: missing clinicId param");
      return;
    }
    const afterSnap = event.data?.after;
    if (!afterSnap?.exists) {
      const publicDocRef = db.doc(
        `clinics/${clinicId}/public/config/publicBooking/publicBooking`
      );
      await publicDocRef.delete().catch(() => {});
      logger.info("mirrorPublicBooking: source deleted, mirror deleted", { clinicId });
      return;
    }
    await runPublicBookingMirrorForClinic(clinicId);
  }
);
