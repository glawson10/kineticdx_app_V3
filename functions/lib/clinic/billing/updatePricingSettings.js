"use strict";
/**
 * Phase 6A: Update clinic-level pricing settings (default fallback + duration rounding).
 * Does not touch practitioner/client/appointment-type overrides; those are separate endpoints or batched here later.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.updatePricingSettings = updatePricingSettings;
const https_1 = require("firebase-functions/v2/https");
const common_1 = require("./common");
const RATE_MAX = 1000000;
const DURATION_ROUNDING_MINUTES_MAX = 480; // 8 hours
async function updatePricingSettings(request) {
    var _a;
    const uid = (0, common_1.requireAuthUid)(request);
    const data = (0, common_1.asObject)(request.data);
    const clinicId = (0, common_1.requireString)(data.clinicId, "clinicId", 2, 120);
    await (0, common_1.requireBillingWrite)(clinicId, uid);
    const patch = (0, common_1.asObject)(data.patch);
    const update = { updatedAt: common_1.FV.serverTimestamp(), updatedByUid: uid };
    if (patch.defaultHourlyRate !== undefined) {
        const v = patch.defaultHourlyRate;
        if (v !== null && (typeof v !== "number" || !Number.isFinite(v) || v < 0 || v > RATE_MAX)) {
            throw new https_1.HttpsError("invalid-argument", "defaultHourlyRate must be a non-negative number or null.");
        }
        update.defaultHourlyRate = v === null ? null : (typeof v === "number" ? Math.round(v * 100) / 100 : Number(v));
    }
    if (patch.defaultFixedRate !== undefined) {
        const v = patch.defaultFixedRate;
        if (v !== null && (typeof v !== "number" || !Number.isFinite(v) || v < 0 || v > RATE_MAX)) {
            throw new https_1.HttpsError("invalid-argument", "defaultFixedRate must be a non-negative number or null.");
        }
        update.defaultFixedRate = v === null ? null : (typeof v === "number" ? Math.round(v * 100) / 100 : Number(v));
    }
    const policies = ["actual", "scheduled", "roundUpTo", "minimumBillable"];
    if (patch.durationRoundingPolicy !== undefined) {
        const v = String((_a = patch.durationRoundingPolicy) !== null && _a !== void 0 ? _a : "").trim();
        if (v && !policies.includes(v)) {
            throw new https_1.HttpsError("invalid-argument", "durationRoundingPolicy must be actual, scheduled, roundUpTo, or minimumBillable.");
        }
        update.durationRoundingPolicy = v || "actual";
    }
    if (patch.durationRoundingMinutes !== undefined) {
        const v = Number(patch.durationRoundingMinutes);
        if (!Number.isInteger(v) || v < 1 || v > DURATION_ROUNDING_MINUTES_MAX) {
            throw new https_1.HttpsError("invalid-argument", "durationRoundingMinutes must be an integer between 1 and 480.");
        }
        update.durationRoundingMinutes = v;
    }
    if (patch.minimumBillableMinutes !== undefined) {
        const v = Number(patch.minimumBillableMinutes);
        if (!Number.isInteger(v) || v < 0 || v > DURATION_ROUNDING_MINUTES_MAX) {
            throw new https_1.HttpsError("invalid-argument", "minimumBillableMinutes must be an integer between 0 and 480.");
        }
        update.minimumBillableMinutes = v;
    }
    if (Object.keys(update).length <= 2) {
        throw new https_1.HttpsError("invalid-argument", "No valid pricing patch fields.");
    }
    const ref = (0, common_1.billingPricingSettingsRef)(clinicId);
    await ref.set(update, { merge: true });
    return { ok: true };
}
//# sourceMappingURL=updatePricingSettings.js.map