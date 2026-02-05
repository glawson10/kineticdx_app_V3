// functions/src/preassessment/resolveIntakeSessionFromBookingRequestFn.ts
import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/logger";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

/**
 * ✅ For in-app public booking flow (NO token available):
 * Input: clinicId + bookingRequestId
 * Output: intakeSessionId (must already exist from onBookingRequestCreateV2)
 */
export const resolveIntakeSessionFromBookingRequestFn = onCall(
  { region: "europe-west3", cors: true },
  async (req) => {
    const clinicId = safeStr(req.data?.clinicId);
    const bookingRequestId = safeStr(req.data?.bookingRequestId);

    if (!clinicId || !bookingRequestId) {
      throw new HttpsError("invalid-argument", "Missing clinicId or bookingRequestId.", {
        clinicId,
        bookingRequestId,
      });
    }

    const brRef = db.doc(`clinics/${clinicId}/bookingRequests/${bookingRequestId}`);
    const brSnap = await brRef.get();
    if (!brSnap.exists) {
      throw new HttpsError("not-found", "bookingRequest not found.", {
        clinicId,
        bookingRequestId,
      });
    }

    const br = brSnap.data() ?? {};
    const intakeSessionId = safeStr((br as any).intakeSessionId);

    if (!intakeSessionId) {
      // This means your trigger didn’t create it (or booking not approved yet / failed).
      throw new HttpsError(
        "failed-precondition",
        "No intakeSessionId on this booking request (preassessment not created yet).",
        { clinicId, bookingRequestId }
      );
    }

    // Optional sanity check: ensure intake session exists
    const isRef = db.doc(`clinics/${clinicId}/intakeSessions/${intakeSessionId}`);
    const isSnap = await isRef.get();
    if (!isSnap.exists) {
      throw new HttpsError("failed-precondition", "intakeSessionId referenced but session doc missing.", {
        clinicId,
        bookingRequestId,
        intakeSessionId,
      });
    }

    logger.info("resolveIntakeSessionFromBookingRequestFn ok", {
      clinicId,
      bookingRequestId,
      intakeSessionId,
    });

    return { ok: true, intakeSessionId };
  }
);
