"use strict";
/**
 * Pure duration rounding for pricing (Phase 6A). No Firestore dependency so tests can run without Firebase.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.roundDuration = roundDuration;
function roundMoney(n) {
    return Math.round(n * 100) / 100;
}
/**
 * Rounds duration according to policy. Returns billable minutes.
 */
function roundDuration(durationMinutes, policy, options = {}) {
    const { roundUpToMinutes = 15, minimumBillableMinutes = 15, scheduledDurationMinutes } = options;
    if (!Number.isFinite(durationMinutes) || durationMinutes < 0)
        return 0;
    switch (policy) {
        case "scheduled":
            if (Number.isFinite(scheduledDurationMinutes) && scheduledDurationMinutes >= 0) {
                return Math.round(scheduledDurationMinutes * 100) / 100;
            }
            return roundMoney(durationMinutes);
        case "roundUpTo":
            if (roundUpToMinutes <= 0)
                return roundMoney(durationMinutes);
            const roundedUp = Math.ceil(durationMinutes / roundUpToMinutes) * roundUpToMinutes;
            return roundMoney(roundedUp);
        case "minimumBillable":
            const min = minimumBillableMinutes > 0 ? minimumBillableMinutes : 15;
            return roundMoney(Math.max(durationMinutes, min));
        case "actual":
        default:
            return roundMoney(durationMinutes);
    }
}
//# sourceMappingURL=durationRounding.js.map