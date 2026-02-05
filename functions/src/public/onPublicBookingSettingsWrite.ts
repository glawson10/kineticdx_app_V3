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

    const [servicesSnap, practitionersSnap, membershipsSnap] = await Promise.all([
      db.collection(`clinics/${clinicId}/services`).get(),
      db.collection(`clinics/${clinicId}/practitioners`).get(),
      db.collection(`clinics/${clinicId}/memberships`).get(),
    ]);

    logger.info("collection counts", {
      clinicId,
      services: servicesSnap.size,
      practitioners: practitionersSnap.size,
      memberships: membershipsSnap.size,
    });

    const services = servicesSnap.docs.map((d) => ({ id: d.id, data: (d.data() ?? {}) as AnyMap }));
    const practitioners = practitionersSnap.docs.map((d) => ({
      id: d.id,
      data: (d.data() ?? {}) as AnyMap,
    }));
    const memberships = membershipsSnap.docs.map((d) => ({
      id: d.id,
      data: (d.data() ?? {}) as AnyMap,
    }));

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

    logger.info("projection practitioners", {
      clinicId,
      count: projection.practitioners?.length ?? 0,
      sample: projection.practitioners?.[0] ?? null,
    });

    await publicDocRef.set(
      {
        ...projection,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: "onPublicBookingSettingsWrite-gen2",
      },
      { merge: true }
    );

    logger.info("wrote public mirror", { path: publicDocRef.path });
  }
);
