"use strict";
/**
 * Trigger: clinics/{clinicId}/settings/publicBooking (create/update/delete).
 * Rebuilds the public booking projection by calling runPublicBookingMirrorForClinic.
 * Single source of truth: private settings → public mirror only; no write back to /settings/**.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.onPublicBookingConfigMirror = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const logger_1 = require("firebase-functions/logger");
const mirrorPublicBooking_1 = require("./mirrorPublicBooking");
function safeStr(v) {
    return typeof v === "string" ? v.trim() : (v !== null && v !== void 0 ? v : "").toString().trim();
}
exports.onPublicBookingConfigMirror = (0, firestore_1.onDocumentWritten)({
    region: "europe-west3",
    document: "clinics/{clinicId}/settings/publicBooking",
}, async (event) => {
    var _a;
    const clinicId = safeStr((_a = event.params) === null || _a === void 0 ? void 0 : _a.clinicId);
    if (!clinicId) {
        logger_1.logger.warn("onPublicBookingConfigMirror: missing clinicId");
        return;
    }
    logger_1.logger.info("onPublicBookingConfigMirror: rebuilding public projection", { clinicId });
    await (0, mirrorPublicBooking_1.runPublicBookingMirrorForClinic)(clinicId);
});
//# sourceMappingURL=onPublicBookingConfigMirror.js.map