"use strict";
/**
 * Paths for projection targets (public mirror docs).
 * Private sources are in clinic/paths.ts (e.g. settingsPublicBooking).
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.publicBookingConfigDocPath = publicBookingConfigDocPath;
/**
 * Minimal public booking config doc (Commit 16 schema v1).
 * Written by projection trigger only; clients read-only.
 */
function publicBookingConfigDocPath(clinicId) {
    return `clinics/${clinicId}/public/config/publicBooking/config`;
}
//# sourceMappingURL=paths.js.map