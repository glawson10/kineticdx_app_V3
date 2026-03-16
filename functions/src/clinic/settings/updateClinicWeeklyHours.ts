/**
 * updateClinicWeeklyHoursFn
 * Deprecated write path: do not write to public docs.
 * Thin wrapper: forwards to settings.updatePublicBookingConfig (clinics/{clinicId}/settings/publicBooking).
 * Mirror triggers then update public/config from that source of truth.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { updatePublicBookingConfig } from "./updatePublicBookingConfig";

function safeStr(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

type Input = {
  clinicId?: string;
  weeklyHours?: Record<string, unknown>;
  weeklyHoursMeta?: Record<string, unknown>;
};

/**
 * Writes only to clinics/{clinicId}/settings/publicBooking via settings.updatePublicBookingConfig.
 * Does not write to public docs; triggers handle mirroring.
 */
export const updateClinicWeeklyHoursFn = onCall(
  { region: "europe-west3", cors: true },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const data = (request.data ?? {}) as Partial<Input>;
    const clinicId = safeStr(data.clinicId);
    if (!clinicId) throw new HttpsError("invalid-argument", "clinicId is required.");

    if (!data.weeklyHours || typeof data.weeklyHours !== "object") {
      throw new HttpsError("invalid-argument", "weeklyHours is required.");
    }

    const patch: Record<string, unknown> = { weeklyHours: data.weeklyHours };
    if (data.weeklyHoursMeta && typeof data.weeklyHoursMeta === "object") {
      patch.weeklyHoursMeta = data.weeklyHoursMeta;
    }

    return updatePublicBookingConfig({
      auth: request.auth,
      data: { clinicId, patch },
    });
  }
);
