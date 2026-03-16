"use strict";
/**
 * updateClinicWeeklyHoursFn
 * Deprecated write path: do not write to public docs.
 * Thin wrapper: forwards to settings.updatePublicBookingConfig (clinics/{clinicId}/settings/publicBooking).
 * Mirror triggers then update public/config from that source of truth.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.updateClinicWeeklyHoursFn = void 0;
const https_1 = require("firebase-functions/v2/https");
const updatePublicBookingConfig_1 = require("./updatePublicBookingConfig");
function safeStr(v) {
    return typeof v === "string" ? v.trim() : "";
}
/**
 * Writes only to clinics/{clinicId}/settings/publicBooking via settings.updatePublicBookingConfig.
 * Does not write to public docs; triggers handle mirroring.
 */
exports.updateClinicWeeklyHoursFn = (0, https_1.onCall)({ region: "europe-west3", cors: true }, async (request) => {
    var _a, _b;
    const uid = (_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const data = ((_b = request.data) !== null && _b !== void 0 ? _b : {});
    const clinicId = safeStr(data.clinicId);
    if (!clinicId)
        throw new https_1.HttpsError("invalid-argument", "clinicId is required.");
    if (!data.weeklyHours || typeof data.weeklyHours !== "object") {
        throw new https_1.HttpsError("invalid-argument", "weeklyHours is required.");
    }
    const patch = { weeklyHours: data.weeklyHours };
    if (data.weeklyHoursMeta && typeof data.weeklyHoursMeta === "object") {
        patch.weeklyHoursMeta = data.weeklyHoursMeta;
    }
    return (0, updatePublicBookingConfig_1.updatePublicBookingConfig)({
        auth: request.auth,
        data: { clinicId, patch },
    });
});
//# sourceMappingURL=updateClinicWeeklyHours.js.map