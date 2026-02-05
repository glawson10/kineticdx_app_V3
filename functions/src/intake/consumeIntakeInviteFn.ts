// functions/src/preassessment/consumeIntakeInviteFn.ts
import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/logger";
import * as crypto from "crypto";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

function sha256Base64Url(s: string): string {
  return crypto.createHash("sha256").update(s).digest("base64url");
}

function tsNow() {
  return admin.firestore.FieldValue.serverTimestamp();
}

/**
 * ✅ Behavior (matches what you need to stop "Session does not exist"):
 * - Validate clinicId + token
 * - Find invite by tokenHash
 * - Enforce expiresAt BEFORE claiming (unless already claimed)
 * - If invite already has sessionId => RESUME that sessionId (idempotent)
 * - If not claimed => create intakeSessions/{sessionId} draft AND write invite.sessionId
 *
 * ✅ Also adds: appointmentId / patientId / patientEmailNorm mirroring if present on invite
 * ✅ Does NOT set usedAt here (Option B: mark used on submit)
 */
export const consumeIntakeInviteFn = onCall(
  { region: "europe-west3", cors: true },
  async (req) => {
    const clinicId = safeStr(req.data?.clinicId);
    const token = safeStr(req.data?.token);

    if (!clinicId || !token) {
      throw new HttpsError("invalid-argument", "Missing clinicId or token.", {
        clinicId,
        hasToken: !!token,
      });
    }

    // Optional: verify clinic exists (helps debugging)
    const clinicSnap = await db.collection("clinics").doc(clinicId).get();
    if (!clinicSnap.exists) {
      throw new HttpsError("not-found", "Clinic does not exist.", { clinicId });
    }

    const tokenHash = sha256Base64Url(token);
    const invitesCol = db.collection(`clinics/${clinicId}/intakeInvites`);

    // Find invite by tokenHash (limit 1)
    const q = await invitesCol.where("tokenHash", "==", tokenHash).limit(1).get();
    if (q.empty) {
      throw new HttpsError("failed-precondition", "Invite not found (link may be invalid).");
    }

    const inviteRef = q.docs[0].ref;

    const result = await db.runTransaction(async (tx) => {
      const inviteSnap = await tx.get(inviteRef);
      if (!inviteSnap.exists) {
        throw new HttpsError("failed-precondition", "Invite not found (link may be invalid).");
      }

      const invite = inviteSnap.data() ?? {};

      // If already claimed, resume SAME sessionId (idempotent)
      const existingSessionId = safeStr((invite as any).sessionId);
      if (existingSessionId) {
        // Ensure the session doc exists; if it was somehow deleted, recreate a minimal draft.
        const intakeRef = db
          .collection(`clinics/${clinicId}/intakeSessions`)
          .doc(existingSessionId);

        const intakeSnap = await tx.get(intakeRef);
        if (!intakeSnap.exists) {
          const now = tsNow();

          tx.set(
            intakeRef,
            {
              schemaVersion: 1,
              clinicId,
              status: "draft",
              createdAt: now,
              updatedAt: now,
              submittedAt: null,
              lockedAt: null,

              inviteId: inviteRef.id,

              // helpful linkage (if present on invite)
              appointmentId: (invite as any).appointmentId ?? null,
              patientId: (invite as any).patientId ?? null,
              patientEmailNorm: (invite as any).patientEmailNorm ?? null,

              // draft payload
              flow: null,
              consent: null,
              patientDetails: null,
              regionSelection: null,
              answers: {},
              triage: null,
              summary: null,
            },
            { merge: false }
          );
        } else {
          tx.set(intakeRef, { updatedAt: tsNow() }, { merge: true });
        }

        return { ok: true, sessionId: existingSessionId, resumed: true };
      }

      // If not yet claimed, enforce expiry
      const expiresAt = (invite as any).expiresAt;
      const expiresMs =
        expiresAt && typeof expiresAt.toMillis === "function" ? expiresAt.toMillis() : null;

      if (expiresMs != null && expiresMs < Date.now()) {
        throw new HttpsError("failed-precondition", "This link has expired.");
      }

      // ✅ Create a new intake session draft (claim)
      const sessionRef = db
        .collection(`clinics/${clinicId}/intakeSessions`)
        .doc();

      const now = tsNow();

      tx.set(
        sessionRef,
        {
          schemaVersion: 1,
          clinicId,
          status: "draft",
          createdAt: now,
          updatedAt: now,
          submittedAt: null,
          lockedAt: null,

          inviteId: inviteRef.id,

          // helpful linkage (if present on invite)
          appointmentId: (invite as any).appointmentId ?? null,
          patientId: (invite as any).patientId ?? null,
          patientEmailNorm: (invite as any).patientEmailNorm ?? null,

          // draft payload (client fills these progressively)
          flow: null,
          consent: null,
          patientDetails: null,
          regionSelection: null,
          answers: {},
          triage: null,
          summary: null,
        },
        { merge: false }
      );

      tx.set(
        inviteRef,
        {
          sessionId: sessionRef.id,
          claimedAt: now,
          // NOTE: do NOT set usedAt here (Option B: set usedAt on submit)
        },
        { merge: true }
      );

      return { ok: true, sessionId: sessionRef.id, resumed: false };
    });

    logger.info("consumeIntakeInviteFn ok", {
      clinicId,
      inviteId: inviteRef.id,
      sessionId: (result as any).sessionId,
      resumed: (result as any).resumed,
    });

    return result;
  }
);
