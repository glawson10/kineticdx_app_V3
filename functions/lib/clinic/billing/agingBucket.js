"use strict";
/**
 * Pure function: returns the aging bucket for a due date relative to now.
 * Used by getAgedReceivables and by tests without requiring Firestore.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.getAgingBucket = getAgingBucket;
function getAgingBucket(now, dueDate) {
    const ageDays = Math.floor((now.getTime() - dueDate.getTime()) / 86400000);
    if (ageDays <= 0)
        return "current";
    if (ageDays <= 30)
        return "days30";
    if (ageDays <= 60)
        return "days60";
    return "days90plus";
}
//# sourceMappingURL=agingBucket.js.map