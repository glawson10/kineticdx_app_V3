// functions/src/intake/resolveIntakeLinkTokenFn.ts
import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/logger";
import * as crypto from "crypto";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const GENERAL_FLOW_ID = "generalVisit";
const GENERAL_FLOW_VERSION = 1;

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

function sha256Base64Url(s: string): string {
  return crypto.createHash("sha256").update(s).digest("base64url");
}

function tsNow() {
  return admin.firestore.FieldValue.serverTimestamp();
}

function intakeDraftPayload(params: { clinicId: string; linkId: string }) {
  return {
    schemaVersion: 1,
    clinicId: params.clinicId,
    status: "draft",
    createdAt: tsNow(),
    updatedAt: tsNow(),
    submittedAt: null,
    lockedAt: null,

    intakeLinkId: params.linkId,

    flow: { flowId: GENERAL_FLOW_ID, flowVersion: GENERAL_FLOW_VERSION },
    flowId: GENERAL_FLOW_ID,
    flowVersion: GENERAL_FLOW_VERSION,
    flowCategory: "general",

    consent: null,
    patientDetails: null,
    regionSelection: null,
    answers: {},
    triage: null,
    summary: null,
  };
}

/**
 * ✅ Resolve a tokenized general questionnaire link (public).
 * Input: { token }
 * Output: { clinicId, kind, intakeSessionId, flowId, flowVersion }
 */
export const resolveIntakeLinkTokenFn = onCall(
  { region: "europe-west3", cors: true },
  async (req) => {
    const token = safeStr(req.data?.token);
    if (!token) {
      throw new HttpsError("invalid-argument", "Missing token.");
    }

    const tokenHash = sha256Base64Url(token);

    let q;
    try {
      q = await db
        .collectionGroup("intakeLinks")
        .where("tokenHash", "==", tokenHash)
        .limit(1)
        .get();
    } catch (err: any) {
      logger.error("resolveIntakeLinkTokenFn: intakeLinks query failed", {
        code: (err as any)?.code,
        message: (err as any)?.message,
        details: (err as any)?.details,
      });
      throw new HttpsError(
        "internal",
        "Failed to look up questionnaire link.",
        err
      );
    }

    if (q.empty) {
      throw new HttpsError("not-found", "Link not found.");
    }

    const linkRef = q.docs[0].ref;
    const linkId = linkRef.id;

    const result = await db.runTransaction(async (tx) => {
      const linkSnap = await tx.get(linkRef);
      if (!linkSnap.exists) {
        throw new HttpsError("not-found", "Link not found.");
      }

      const link = linkSnap.data() ?? {};
      const clinicId =
        safeStr((link as any).clinicId) || linkRef.parent.parent?.id || "";

      if (!clinicId) {
        throw new HttpsError("failed-precondition", "Link missing clinicId.");
      }

      const kind = safeStr((link as any).kind) || "preassessment";
      if (kind !== "general") {
        throw new HttpsError(
          "failed-precondition",
          "This link is not for the general questionnaire."
        );
      }

      const existingSessionId = safeStr(
        (link as any).intakeSessionId ?? (link as any).sessionId
      );

      const status = safeStr((link as any).status) || "active";
      if (status === "expired") {
        throw new HttpsError("failed-precondition", "This link has expired.");
      }
      if (status === "used" && !existingSessionId) {
        throw new HttpsError(
          "failed-precondition",
          "This link has already been used."
        );
      }

      const expiresAt = (link as any).expiresAt;
      const expiresMs =
        expiresAt && typeof expiresAt.toMillis === "function"
          ? expiresAt.toMillis()
          : null;

      if (expiresMs != null && expiresMs < Date.now()) {
        tx.set(
          linkRef,
          { status: "expired", expiredAt: tsNow() },
          { merge: true }
        );
        throw new HttpsError("failed-precondition", "This link has expired.");
      }

      const sessionsCol = db
        .collection("clinics")
        .doc(clinicId)
        .collection("intakeSessions");

      let intakeSessionId = existingSessionId;
      let resumed = false;

      if (existingSessionId) {
        const intakeRef = sessionsCol.doc(existingSessionId);
        const intakeSnap = await tx.get(intakeRef);

        if (!intakeSnap.exists) {
          tx.set(intakeRef, intakeDraftPayload({ clinicId, linkId }), {
            merge: false,
          });
        } else {
          const existing = intakeSnap.data() ?? {};
          if (
            (existing as any).submittedAt ||
            (existing as any).status === "submitted" ||
            (existing as any).lockedAt
          ) {
            throw new HttpsError(
              "failed-precondition",
              "This link has already been submitted."
            );
          }

          tx.set(intakeRef, { updatedAt: tsNow() }, { merge: true });
        }

        resumed = true;
      } else {
        const newRef = sessionsCol.doc();
        intakeSessionId = newRef.id;

        tx.set(newRef, intakeDraftPayload({ clinicId, linkId }), {
          merge: false,
        });
      }

      if (status !== "used" || !existingSessionId) {
        tx.set(
          linkRef,
          {
            status: "used",
            usedAt: tsNow(),
            intakeSessionId,
          },
          { merge: true }
        );
      }

      return {
        clinicId,
        kind: "general",
        intakeSessionId,
        flowId: GENERAL_FLOW_ID,
        flowVersion: GENERAL_FLOW_VERSION,
        resumed,
      };
    });

    logger.info("resolveIntakeLinkTokenFn ok", {
      clinicId: (result as any).clinicId,
      intakeSessionId: (result as any).intakeSessionId,
      resumed: (result as any).resumed,
      linkId,
    });

    return result;
  }
);
