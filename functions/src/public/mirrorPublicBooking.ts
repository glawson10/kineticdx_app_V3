// functions/src/public/mirrorPublicBooking.ts
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

    // ✅ Canonical public mirror doc path (matches listPublicSlotsFn)
    const publicDocRef = db.doc(
      `clinics/${clinicId}/public/config/publicBooking/publicBooking`
    );

    const afterSnap = event.data?.after;
    const beforeSnap = event.data?.before;

    // If deleted, delete mirror too (optional)
    if (!afterSnap?.exists) {
      await publicDocRef.delete().catch(() => {});
      logger.info("mirrorPublicBooking: source deleted, mirror deleted", {
        clinicId,
        hadBefore: !!beforeSnap?.exists,
      });
      return;
    }

    const publicBookingSettingsDoc = asMap(afterSnap.data());

    // Read clinic root + services + members (for practitioners + memberships)
    const clinicRef = db.doc(`clinics/${clinicId}`);
    const servicesCol = db.collection(`clinics/${clinicId}/services`);
    const membersCol = db.collection(`clinics/${clinicId}/members`);

    const [clinicSnap, servicesSnap, membersSnap] = await Promise.all([
      clinicRef.get().catch(() => null),
      servicesCol.where("active", "==", true).get().catch(() => null),
      // Single-field query only; no composite needed
      membersCol.where("active", "==", true).get().catch(() => null),
    ]);

    const clinicDoc: AnyMap = clinicSnap?.exists ? asMap(clinicSnap.data()) : {};

    // Prefer root keys (new schema), fall back to legacy profile map
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
      servicesSnap?.docs.map((d) => ({
        id: d.id,
        data: asMap(d.data()),
      })) ?? [];

    const memberships =
      membersSnap?.docs.map((d) => ({
        id: d.id,
        data: asMap(d.data()),
      })) ?? [];

    // Practitioners: best-effort filter from memberships.
    // Adjust these heuristics to match your membership schema.
    const practitioners = memberships
      .filter((m) => {
        const md = asMap(m.data);
        if (md.active !== true) return false;

        const role = safeStr(md.role).toLowerCase();
        const kind = safeStr(md.kind).toLowerCase();
        const isPractitioner = md.isPractitioner === true;

        // common patterns: role/kind flags or explicit boolean
        if (isPractitioner) return true;
        if (role.includes("practitioner") || role.includes("clinician"))
          return true;
        if (kind.includes("practitioner") || kind.includes("clinician"))
          return true;

        return false;
      })
      .map((m) => ({
        id: safeStr(m.id), // usually uid
        data: m.data,
      }));

    // NOTE: buildPublicBookingProjection in your project expects these keys:
    // - clinicId, clinicName, logoUrl
    // - clinicDoc? (optional)
    // - publicBookingSettingsDoc
    // - services
    // - practitioners
    // - memberships
    const input = {
      clinicId,
      clinicName,
      logoUrl,
      clinicDoc,
      publicBookingSettingsDoc,
      services,
      practitioners,
      memberships,
    };

    const projection = buildPublicBookingProjection(input as any);

    await publicDocRef.set(
      {
        ...projection,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: "mirrorPublicBooking-v2",
      },
      { merge: true }
    );

    logger.info("mirrorPublicBooking: mirror updated", {
      clinicId,
      services: services.length,
      memberships: memberships.length,
      practitioners: practitioners.length,
    });
  }
);
