import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";

/**
 * Throws if [startAt, endAt) overlaps any active clinic closure.
 *
 * Assumes:
 * - startAt < endAt
 * - timestamps are Firestore Timestamps
 */
export async function assertNoClosureOverlap({
  db,
  clinicId,
  startAt,
  endAt,
}: {
  db: admin.firestore.Firestore;
  clinicId: string;
  startAt: admin.firestore.Timestamp;
  endAt: admin.firestore.Timestamp;
}) {
  // Query only closures that *could* overlap
  const snap = await db
    .collection(`clinics/${clinicId}/closures`)
    .where("active", "==", true)
    .where("fromAt", "<", endAt)
    .get();

  for (const doc of snap.docs) {
    const data = doc.data();
    const fromAt = data.fromAt as admin.firestore.Timestamp | undefined;
    const toAt = data.toAt as admin.firestore.Timestamp | undefined;

    if (!fromAt || !toAt) continue;

    // Overlap condition:
    // [startAt, endAt) intersects [fromAt, toAt)
    const overlaps =
      startAt.toMillis() < toAt.toMillis() &&
      endAt.toMillis() > fromAt.toMillis();

    if (overlaps) {
      throw new HttpsError(
        "failed-precondition",
        "Appointment overlaps a clinic closure."
      );
    }
  }
}
