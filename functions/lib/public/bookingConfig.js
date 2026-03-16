"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.normalizeBookingRulesFromConfigDoc = normalizeBookingRulesFromConfigDoc;
exports.loadPublicBookingRules = loadPublicBookingRules;
function safeStr(v) {
    return typeof v === "string" ? v.trim() : "";
}
const DEFAULT_RULES = {
    timezone: "Europe/Prague",
    minNoticeMinutes: 0,
    maxAdvanceDays: 90,
    requireEmail: true,
    requirePhone: false,
    allowNewPatients: true,
};
/**
 * Normalize booking rules from a config doc data object (so listPublicSlots
 * can pass doc.data() and reuse the same logic).
 */
function normalizeBookingRulesFromConfigDoc(data) {
    if (!data || typeof data !== "object")
        return { ...DEFAULT_RULES };
    const d = data;
    const jurisdiction = (d === null || d === void 0 ? void 0 : d.jurisdiction) && typeof d.jurisdiction === "object"
        ? d.jurisdiction
        : {};
    const rules = (d === null || d === void 0 ? void 0 : d.bookingRules) && typeof d.bookingRules === "object"
        ? d.bookingRules
        : {};
    const timezone = safeStr(jurisdiction.timezone) || DEFAULT_RULES.timezone;
    const minNoticeMinutes = typeof rules.minNoticeMinutes === "number" && rules.minNoticeMinutes >= 0
        ? rules.minNoticeMinutes
        : DEFAULT_RULES.minNoticeMinutes;
    const maxAdvanceDays = typeof rules.maxAdvanceDays === "number" &&
        rules.maxAdvanceDays >= 7 &&
        rules.maxAdvanceDays <= 365
        ? rules.maxAdvanceDays
        : DEFAULT_RULES.maxAdvanceDays;
    const requireEmail = rules.requireEmail === true || rules.requireEmail !== false;
    const requirePhone = rules.requirePhone === true;
    const allowNewPatients = rules.allowNewPatients === true || rules.allowNewPatients !== false;
    return {
        timezone,
        minNoticeMinutes,
        maxAdvanceDays,
        requireEmail,
        requirePhone,
        allowNewPatients,
    };
}
const CONFIG_DOC_PATH = (clinicId) => `clinics/${clinicId}/public/config/publicBooking/config`;
/**
 * Load and normalize booking rules from the public config doc.
 */
async function loadPublicBookingRules(db, clinicId) {
    const snap = await db.doc(CONFIG_DOC_PATH(clinicId)).get();
    if (!snap.exists || !snap.data())
        return { ...DEFAULT_RULES };
    return normalizeBookingRulesFromConfigDoc(snap.data());
}
//# sourceMappingURL=bookingConfig.js.map