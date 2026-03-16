import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/logger";
import * as crypto from "crypto";

import {
  QUESTIONNAIRE_LAUNCH_KIND_INTAKE_LINK,
  loadQuestionnaireTemplateById,
} from "../clinic/questionnaires/questionnaireTemplates";

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

function buildQuestionnaireLaunchUrl(params: {
  baseUrl: string;
  token: string;
  useHashRouting?: boolean;
}): string {
  const base = normalizeBaseUrl(params.baseUrl);
  const t = encodeURIComponent(params.token);
  const useHash = params.useHashRouting !== false;
  return useHash ? `${base}/#/q/launch/${t}` : `${base}/q/launch/${t}`;
}

export const createQuestionnaireLaunchLinkFn = onCall(
  { region: "europe-west3", cors: true },
  async (req) => {
    const clinicId = safeStr(req.data?.clinicId);
    const templateId = safeStr(req.data?.templateId);
    const bookingRequestId = safeStr(req.data?.bookingRequestId);
    const patientId = safeStr(req.data?.patientId);
    const emailRaw = safeStr(req.data?.email).toLowerCase();
    const expiresInDaysRaw = req.data?.expiresInDays;
    const prefillRaw =
      req.data?.prefillPatient && typeof req.data.prefillPatient === "object"
        ? (req.data.prefillPatient as Record<string, unknown>)
        : {};
    const prefillPatient = {
      firstName: safeStr(prefillRaw.firstName),
      lastName: safeStr(prefillRaw.lastName),
      dobIso: safeStr(prefillRaw.dobIso),
      phone: safeStr(prefillRaw.phone),
      email: safeStr(prefillRaw.email),
      address: safeStr(prefillRaw.address),
    };

    if (!clinicId) {
      throw new HttpsError("invalid-argument", "Missing clinicId.");
    }
    if (!templateId) {
      throw new HttpsError("invalid-argument", "Missing templateId.");
    }

    const clinicSnap = await db.collection("clinics").doc(clinicId).get();
    if (!clinicSnap.exists) {
      throw new HttpsError("not-found", "Clinic does not exist.", { clinicId });
    }

    const template = await loadQuestionnaireTemplateById(db, clinicId, templateId);
    if (!template || !template.active || !template.patientFacing) {
      throw new HttpsError("not-found", "Questionnaire template not found.", {
        clinicId,
        templateId,
      });
    }
    if (template.launchKind !== QUESTIONNAIRE_LAUNCH_KIND_INTAKE_LINK) {
      throw new HttpsError(
        "failed-precondition",
        "This questionnaire template cannot be launched with an intake link."
      );
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
      schemaVersion: 2,
      clinicId,
      kind: "questionnaire",
      templateId: template.templateId,
      flowId: template.flowId ?? null,
      flowVersion: template.flowVersion ?? 1,
      flowCategory: template.flowCategory ?? "general",
      flowDefinitionId: template.flowDefinitionId ?? null,
      clinicalProfileId: template.clinicalProfileId ?? null,
      tokenHash,
      status: "active",
      expiresAt,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      usedAt: null,
      intakeSessionId: null,
      patientId: patientId || null,
      patientEmailNorm: emailRaw || null,
      bookingRequestId: bookingRequestId || null,
      prefillPatient,
      createdByUid: req.auth?.uid ?? null,
    });

    const baseUrl = await readPublicBaseUrl(clinicId);
    const url = buildQuestionnaireLaunchUrl({
      baseUrl,
      token,
      useHashRouting: true,
    });

    logger.info("createQuestionnaireLaunchLinkFn ok", {
      clinicId,
      templateId,
      linkId: linkRef.id,
      hasPatientId: !!patientId,
      hasEmail: !!emailRaw,
      expiresAtMs: expiresAt.toMillis(),
    });

    return { url, token, expiresAt, templateId };
  }
);

