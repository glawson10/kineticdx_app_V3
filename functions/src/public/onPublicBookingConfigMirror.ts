/**
 * Trigger: clinics/{clinicId}/settings/publicBooking (create/update/delete).
 * Rebuilds the public booking projection by calling runPublicBookingMirrorForClinic.
 * Single source of truth: private settings → public mirror only; no write back to /settings/**.
 */

import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions/logger";
import { runPublicBookingMirrorForClinic } from "./mirrorPublicBooking";

function safeStr(v: unknown): string {
  return typeof v === "string" ? v.trim() : (v ?? "").toString().trim();
}

export const onPublicBookingConfigMirror = onDocumentWritten(
  {
    region: "europe-west3",
    document: "clinics/{clinicId}/settings/publicBooking",
  },
  async (event) => {
    const clinicId = safeStr(event.params?.clinicId);
    if (!clinicId) {
      logger.warn("onPublicBookingConfigMirror: missing clinicId");
      return;
    }
    logger.info("onPublicBookingConfigMirror: rebuilding public projection", { clinicId });
    await runPublicBookingMirrorForClinic(clinicId);
  }
);
