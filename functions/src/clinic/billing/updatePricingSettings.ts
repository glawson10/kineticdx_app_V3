/**
 * Phase 6A: Update clinic-level pricing settings (default fallback + duration rounding).
 * Does not touch practitioner/client/appointment-type overrides; those are separate endpoints or batched here later.
 */

import { HttpsError } from "firebase-functions/v2/https";
import { FV, asObject, billingPricingSettingsRef, requireAuthUid, requireBillingWrite, requireString } from "./common";
import type { DurationRoundingPolicy } from "./pricingResolution";

const RATE_MAX = 1_000_000;
const DURATION_ROUNDING_MINUTES_MAX = 480; // 8 hours

export async function updatePricingSettings(request: { auth?: { uid?: string }; data?: unknown }) {
  const uid = requireAuthUid(request);
  const data = asObject(request.data);
  const clinicId = requireString(data.clinicId, "clinicId", 2, 120);
  await requireBillingWrite(clinicId, uid);

  const patch = asObject(data.patch);
  const update: Record<string, unknown> = { updatedAt: FV.serverTimestamp(), updatedByUid: uid };

  if (patch.defaultHourlyRate !== undefined) {
    const v = patch.defaultHourlyRate;
    if (v !== null && (typeof v !== "number" || !Number.isFinite(v) || v < 0 || v > RATE_MAX)) {
      throw new HttpsError("invalid-argument", "defaultHourlyRate must be a non-negative number or null.");
    }
    update.defaultHourlyRate = v === null ? null : (typeof v === "number" ? Math.round(v * 100) / 100 : Number(v));
  }
  if (patch.defaultFixedRate !== undefined) {
    const v = patch.defaultFixedRate;
    if (v !== null && (typeof v !== "number" || !Number.isFinite(v) || v < 0 || v > RATE_MAX)) {
      throw new HttpsError("invalid-argument", "defaultFixedRate must be a non-negative number or null.");
    }
    update.defaultFixedRate = v === null ? null : (typeof v === "number" ? Math.round(v * 100) / 100 : Number(v));
  }
  const policies: DurationRoundingPolicy[] = ["actual", "scheduled", "roundUpTo", "minimumBillable"];
  if (patch.durationRoundingPolicy !== undefined) {
    const v = String(patch.durationRoundingPolicy ?? "").trim();
    if (v && !policies.includes(v as DurationRoundingPolicy)) {
      throw new HttpsError("invalid-argument", "durationRoundingPolicy must be actual, scheduled, roundUpTo, or minimumBillable.");
    }
    update.durationRoundingPolicy = v || "actual";
  }
  if (patch.durationRoundingMinutes !== undefined) {
    const v = Number(patch.durationRoundingMinutes);
    if (!Number.isInteger(v) || v < 1 || v > DURATION_ROUNDING_MINUTES_MAX) {
      throw new HttpsError("invalid-argument", "durationRoundingMinutes must be an integer between 1 and 480.");
    }
    update.durationRoundingMinutes = v;
  }
  if (patch.minimumBillableMinutes !== undefined) {
    const v = Number(patch.minimumBillableMinutes);
    if (!Number.isInteger(v) || v < 0 || v > DURATION_ROUNDING_MINUTES_MAX) {
      throw new HttpsError("invalid-argument", "minimumBillableMinutes must be an integer between 0 and 480.");
    }
    update.minimumBillableMinutes = v;
  }

  if (Object.keys(update).length <= 2) {
    throw new HttpsError("invalid-argument", "No valid pricing patch fields.");
  }

  const ref = billingPricingSettingsRef(clinicId);
  await ref.set(update, { merge: true });
  return { ok: true };
}
