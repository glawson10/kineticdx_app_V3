// functions/src/intake/createGeneralQuestionnaireLinkFn.ts
import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/logger";
import * as crypto from "crypto";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const DEFAULT_PUBLIC_APP_BASE_URL = "https://kineticdx-app-v3.web.app";

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

function sha256Base64Url(s: string): string {
  return crypto.createHash("sha256").update(s).digest("base64url");
}

function randomToken(bytes = 32): string {
  return crypto.randomBytes(bytes).toString("base64url");
}

function normalizeBaseUrl(url: string): string {
  let u = safeStr(url);
  if (!u) return DEFAULT_PUBLIC_APP_BASE_URL;
  if (u.endsWith("/")) u = u.slice(0, -1);
  return u;
}

async function readPublicBaseUrl(clinicId: string): Promise<string> {
  const snap = await db.doc(`clinics/${clinicId}/settings/publicBooking`).get();
  const d = snap.exists ? (snap.data() as any) : {};
  const url = safeStr(d?.publicBaseUrl);
  return url || DEFAULT_PUBLIC_APP_BASE_URL;
}

function buildGeneralQuestionnaireUrl(params: {
  baseUrl: string;
  token: string;
  useHashRouting?: boolean;
}): string {
  const base = normalizeBaseUrl(params.baseUrl);
  const t = encodeURIComponent(params.token);
  const useHash = params.useHashRouting !== false;
  return useHash ? `${base}/#/q/general/${t}` : `${base}/q/general/${t}`;
}

/**
 * ✅ Create a tokenized general questionnaire link.
 * Input: { clinicId, patientId?, email?, expiresInDays? }
 * Output: { url, token, expiresAt }
 */
export const createGeneralQuestionnaireLinkFn = onCall(
  { region: "europe-west3", cors: true },
  async (req) => {
    const clinicId = safeStr(req.data?.clinicId);
    const patientId = safeStr(req.data?.patientId);
    const emailRaw = safeStr(req.data?.email).toLowerCase();
    const expiresInDaysRaw = req.data?.expiresInDays;

    if (!clinicId) {
      throw new HttpsError("invalid-argument", "Missing clinicId.");
    }

    const clinicSnap = await db.collection("clinics").doc(clinicId).get();
    if (!clinicSnap.exists) {
      throw new HttpsError("not-found", "Clinic does not exist.", { clinicId });
    }

    const ttlDays =
      typeof expiresInDaysRaw === "number" && expiresInDaysRaw > 0
        ? Math.ceil(expiresInDaysRaw)
        : 7;

    const token = randomToken(32);
    const tokenHash = sha256Base64Url(token);

    const linkRef = db.collection(`clinics/${clinicId}/intakeLinks`).doc();
    const expiresAt = admin.firestore.Timestamp.fromMillis(
      Date.now() + ttlDays * 24 * 60 * 60 * 1000
    );

    await linkRef.set({
      schemaVersion: 1,
      clinicId,
      kind: "general",
      tokenHash,
      status: "active",
      expiresAt,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      usedAt: null,
      intakeSessionId: null,

      // Optional linkage
      patientId: patientId || null,
      patientEmailNorm: emailRaw || null,
      createdByUid: req.auth?.uid ?? null,
    });

    const baseUrl = await readPublicBaseUrl(clinicId);
    const url = buildGeneralQuestionnaireUrl({
      baseUrl,
      token,
      useHashRouting: true,
    });

    logger.info("createGeneralQuestionnaireLinkFn ok", {
      clinicId,
      linkId: linkRef.id,
      hasPatientId: !!patientId,
      hasEmail: !!emailRaw,
      expiresAtMs: expiresAt.toMillis(),
    });

    return { url, token, expiresAt };
  }
);
