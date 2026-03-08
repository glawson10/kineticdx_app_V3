import * as admin from "firebase-admin";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions/logger";
import { buildPublicBookingProjection } from "../clinic/publicProjection";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

type AnyMap = Record<string, any>;

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

/**
 * SINGLE BRIDGE WRITER (trigger)
 * Canonical settings (writeable):
 *   clinics/{clinicId}/settings/publicBooking
 *
 * Public mirror (read-only):
 *   clinics/{clinicId}/public/config/publicBooking/publicBooking
 */
export const onPublicBookingSettingsWrite = onDocumentWritten(
  {
    region: "europe-west3",
    document: "clinics/{clinicId}/settings/publicBooking",
  },
  async (event) => {
    const clinicId = safeStr(event.params.clinicId);
    if (!clinicId) return;

    logger.info("onPublicBookingSettingsWrite EXECUTED", { clinicId, ts: Date.now() });

    const publicDocRef = db.doc(
      `clinics/${clinicId}/public/config/publicBooking/publicBooking`
    );

    const afterSnap = event.data?.after;

    // If deleted, delete mirror too (best-effort)
    if (!afterSnap || !afterSnap.exists) {
      logger.warn("settings deleted -> deleting mirror", { clinicId });
      await publicDocRef.delete().catch(() => {});
      return;
    }

    const settings = (afterSnap.data() ?? {}) as AnyMap;

    const clinicSnap = await db.doc(`clinics/${clinicId}`).get();
    const clinicDoc: AnyMap = clinicSnap.exists ? ((clinicSnap.data() ?? {}) as AnyMap) : {};

    const clinicName =
      safeStr(clinicDoc?.profile?.name) ||
      safeStr(clinicDoc?.name) ||
      safeStr(clinicDoc?.clinicName) ||
      "Clinic";

    const logoUrl =
      safeStr(clinicDoc?.profile?.logoUrl) ||
      safeStr(clinicDoc?.logoUrl) ||
      safeStr(clinicDoc?.branding?.logoUrl) ||
      "";

    const [servicesSnap, practitionersSnap, membersSnap, membershipsSnap, locationsSnap, typesSnap] =
      await Promise.all([
        db.collection(`clinics/${clinicId}/services`).get(),
        db.collection(`clinics/${clinicId}/practitioners`).get(),
        db.collection(`clinics/${clinicId}/members`).get(),
        db.collection(`clinics/${clinicId}/memberships`).get(),
        db.collection(`clinics/${clinicId}/locations`).get(),
        db.collection(`clinics/${clinicId}/appointmentTypes`).get(),
      ]);

    logger.info("collection counts", {
      clinicId,
      services: servicesSnap.size,
      practitioners: practitionersSnap.size,
      members: membersSnap.size,
      memberships: membershipsSnap.size,
      locations: locationsSnap.size,
      appointmentTypes: typesSnap.size,
    });

    const services = servicesSnap.docs.map((d) => ({ id: d.id, data: (d.data() ?? {}) as AnyMap }));
    const practitioners = practitionersSnap.docs.map((d) => ({
      id: d.id,
      data: (d.data() ?? {}) as AnyMap,
    }));
    // Merge members (canonical) + memberships (legacy) so projection has membership data for all; prefer members.
    const memberById = new Map<string, { id: string; data: AnyMap }>();
    for (const d of membersSnap.docs) {
      memberById.set(d.id, { id: d.id, data: (d.data() ?? {}) as AnyMap });
    }
    for (const d of membershipsSnap.docs) {
      if (!memberById.has(d.id)) {
        memberById.set(d.id, { id: d.id, data: (d.data() ?? {}) as AnyMap });
      }
    }
    const memberships = Array.from(memberById.values());

    const projection = buildPublicBookingProjection({
      clinicId,
      clinicName,
      logoUrl,
      clinicDoc,
      publicBookingSettingsDoc: settings,
      services,
      practitioners,
      memberships,
    });

    // Curated lists for public booking: locations and appointmentTypes (active + showInOnlineBooking)
    const locationsList =
      locationsSnap.docs
        .filter((d) => {
          const dta = d.data() as AnyMap;
          return dta?.active === true && dta?.showInOnlineBooking === true;
        })
        .map((d) => {
          const dta = d.data() as AnyMap;
          return { id: d.id, name: safeStr(dta?.name) || d.id };
        });

    const appointmentTypesList =
      typesSnap.docs
        .filter((d) => {
          const dta = d.data() as AnyMap;
          return dta?.active === true && dta?.showInOnlineBooking === true;
        })
        .map((d) => {
          const dta = d.data() as AnyMap;
          const durationMinutes =
            typeof dta?.durationMinutes === "number" ? dta.durationMinutes : 30;
          return {
            id: d.id,
            name: safeStr(dta?.name) || d.id,
            defaultDurationMinutes: durationMinutes,
            description: safeStr(dta?.description) || undefined,
            defaultPrice: typeof dta?.defaultPrice === "number" ? dta.defaultPrice : undefined,
            colorHex: safeStr(dta?.colorHex) || undefined,
          };
        });

    // Practitioners in mirror must include allowedLocationIds for location filtering
    const practitionersList = (projection.practitioners ?? []).map((p) => ({
      id: p.id,
      displayName: p.displayName ?? p.id,
      ...(Array.isArray(p.allowedLocationIds) && p.allowedLocationIds.length > 0
        ? { allowedLocationIds: p.allowedLocationIds }
        : {}),
    }));

    logger.info("projection practitioners", {
      clinicId,
      count: practitionersList.length,
      locationsCount: locationsList.length,
    });

    await publicDocRef.set(
      {
        ...projection,
        locations: locationsList,
        practitioners: practitionersList,
        appointmentTypes: appointmentTypesList,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: "onPublicBookingSettingsWrite-gen2",
      },
      { merge: true }
    );

    logger.info("wrote public mirror", { path: publicDocRef.path, locations: locationsList.length });
  }
);
