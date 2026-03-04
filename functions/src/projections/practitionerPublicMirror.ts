import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions/logger";
import * as admin from "firebase-admin";

import { writePublicBookingMirror } from "../clinic/writePublicBookingMirror";

if (!admin.apps.length) {
  admin.initializeApp();
}
const db = admin.firestore();

/**
 * When a practitioner doc is written, rebuild the canonical public booking mirror
 * at clinics/{clinicId}/public/config/publicBooking/publicBooking so the
 * practitioner list is always up to date.
 */
export const mirrorPractitionerToPublic = onDocumentWritten(
  {
    document: "clinics/{clinicId}/practitioners/{practitionerId}",
    region: "europe-west3",
  },
  async (event) => {
    const { clinicId, practitionerId } = event.params;

    logger.info("mirrorPractitionerToPublic fired", { clinicId, practitionerId });

    try {
      const settingsSnap = await db
        .doc(`clinics/${clinicId}/settings/publicBooking`)
        .get();

      if (!settingsSnap.exists) {
        logger.info(
          "mirrorPractitionerToPublic: no settings/publicBooking — skipping mirror rebuild",
          { clinicId }
        );
        return;
      }

      const settings = (settingsSnap.data() ?? {}) as Record<string, any>;

      const projection = await writePublicBookingMirror(clinicId, settings);

      logger.info("mirrorPractitionerToPublic: mirror rebuilt", {
        clinicId,
        practitionerId,
        practitionerCount: projection?.practitioners?.length ?? 0,
      });
    } catch (err: any) {
      logger.error("mirrorPractitionerToPublic FAILED", {
        clinicId,
        practitionerId,
        err: err?.message ?? String(err),
      });
      throw err;
    }
  }
);
