"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.assertNoClosureOverlap = assertNoClosureOverlap;
const https_1 = require("firebase-functions/v2/https");
/**
 * Throws if [startAt, endAt) overlaps any active clinic closure.
 *
 * Assumes:
 * - startAt < endAt
 * - timestamps are Firestore Timestamps
 */
async function assertNoClosureOverlap({ db, clinicId, startAt, endAt, }) {
    // Query only closures that *could* overlap
    const snap = await db
        .collection(`clinics/${clinicId}/closures`)
        .where("active", "==", true)
        .where("fromAt", "<", endAt)
        .get();
    for (const doc of snap.docs) {
        const data = doc.data();
        const fromAt = data.fromAt;
        const toAt = data.toAt;
        if (!fromAt || !toAt)
            continue;
        // Overlap condition:
        // [startAt, endAt) intersects [fromAt, toAt)
        const overlaps = startAt.toMillis() < toAt.toMillis() &&
            endAt.toMillis() > fromAt.toMillis();
        if (overlaps) {
            throw new https_1.HttpsError("failed-precondition", "Appointment overlaps a clinic closure.");
        }
    }
}
//# sourceMappingURL=assertNoClosureOverlap.js.map