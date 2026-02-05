// functions/src/preassessment/intakePdfOnSubmit.ts

import * as admin from "firebase-admin";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions/logger";

import { extractGeneralVisitV1KeyAnswers } from "./keyAnswers/generalVisitV1KeyAnswers";
import { renderGeneralVisitV1Html } from "./../preassessment/renderers/generalVisitV1Renderer";
import { htmlToPdfBuffer } from "../preassessment/pdf/htmlToPdfBuffer";

if (!admin.apps.length) admin.initializeApp();

const db = admin.firestore();
const storage = admin.storage();

/**
 * Trigger: when an intake session transitions to submitted.
 *
 * Contract:
 * - Phase 3 creates immutable patient-reported snapshot PDFs.
 * - Writes are backend-authoritative and clinic-scoped.
 */
export const intakePdfOnSubmit = onDocumentWritten(
  {
    document: "clinics/{clinicId}/intakeSessions/{sessionId}",
    region: "europe-west3",
  },
  async (event: any) => {
    const clinicId = event.params.clinicId as string;
    const sessionId = event.params.sessionId as string;

    const afterSnap = event.data?.after;
    if (!afterSnap?.exists) return;

    const after = afterSnap.data() as any;

    // Only on submit/lock
    const status = (after.status ?? "").toString();
    if (status !== "submitted" && status !== "locked") return;

    // Optional: ensure it was a status transition (reduces accidental writes)
    const before = event.data?.before?.exists ? (event.data.before.data() as any) : null;
    const beforeStatus = (before?.status ?? "").toString();

    // If status didn't actually change and we already have outputs, bail.
    if (before && beforeStatus === status) {
      if (after.pdfSnapshotPath) return;
      if (after.keyAnswersVersion === "generalVisit.v1" && after.keyAnswers) return;
    }

    // Flow identification
    const flowId = (after.flowId ?? "").toString(); // "generalVisit"
    const flowVersion = Number(after.flowVersion ?? 0); // 1
    if (flowId !== "generalVisit" || flowVersion !== 1) {
      // Not our flow; branch here for other flows later.
      return;
    }

    const answers = (after.answers ?? {}) as Record<string, any>;

    // ─────────────────────────────────────────────
    // 1) keyAnswers extraction (fast clinician lists)
    // ─────────────────────────────────────────────
    if (!(after.keyAnswersVersion === "generalVisit.v1" && after.keyAnswers)) {
      try {
        const extracted = extractGeneralVisitV1KeyAnswers(answers);

        await db.doc(`clinics/${clinicId}/intakeSessions/${sessionId}`).set(
          {
            keyAnswers: extracted.keyAnswers,
            keyAnswersVersion: extracted.keyAnswersVersion, // "generalVisit.v1"
            summaryPreview: extracted.summaryPreview,
            keyAnswersGeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        logger.info("Extracted keyAnswers", {
          clinicId,
          sessionId,
          keyAnswersVersion: extracted.keyAnswersVersion,
        });
      } catch (e) {
        logger.error("Failed to extract keyAnswers", { clinicId, sessionId, error: e });
        // Do not throw: we still want PDF generation to proceed if possible.
      }
    } else {
      logger.info("keyAnswers already exist; skipping", { clinicId, sessionId });
    }

    // ─────────────────────────────────────────────
    // 2) PDF snapshot generation (immutable)
    // ─────────────────────────────────────────────

    // Guard: do not regenerate if already generated (medico-legal stability)
    if (after.pdfSnapshotPath) {
      logger.info("PDF already exists; skipping", { clinicId, sessionId });
      return;
    }

    // Pull patient details either from blocks or answers — prefer blocks if you have them.
    const patientDetails = after.patientDetails ?? {};
    const clinicProfile = await db.doc(`clinics/${clinicId}`).get();
    const clinicName = (clinicProfile.data()?.name ?? "Clinic").toString();

    const submittedAt =
      after.submittedAt?.toDate?.() ??
      after.completedAt?.toDate?.() ??
      new Date();

    // Render HTML
    const html = renderGeneralVisitV1Html({
      clinicId,
      clinicName,
      sessionId,
      submittedAt,
      schemaVersion: Number(after.schemaVersion ?? 1),
      clinicLogoUrl: after.clinicLogoUrl ?? "", // optional convenience field
      patient: {
        fullName: patientFullName(patientDetails, answers),
        email: patientEmail(patientDetails, answers),
        phone: patientPhone(patientDetails, answers),
      },
      answers,
    });

    // Convert HTML -> PDF buffer
    const pdfBuffer = await htmlToPdfBuffer(html);

    // Storage path (clinic-scoped, private)
    const bucket = storage.bucket();
    const pdfPath = `clinics/${clinicId}/private/intakeSnapshots/${sessionId}.pdf`;

    await bucket.file(pdfPath).save(pdfBuffer, {
      contentType: "application/pdf",
      resumable: false,
      metadata: {
        cacheControl: "private, max-age=0, no-store",
      },
    });

    // Writeback to intake session
    await db.doc(`clinics/${clinicId}/intakeSessions/${sessionId}`).set(
      {
        pdfSnapshotPath: pdfPath,
        pdfGeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    logger.info("Generated intake PDF snapshot", { clinicId, sessionId, pdfPath });
  }
);

// --------------------
// Patient detail fallbacks
// --------------------
function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

function readTextAnswer(answers: Record<string, any>, qid: string): string {
  const a = answers[qid];
  if (a && typeof a === "object" && a.t === "text") return safeStr(a.v);
  return "";
}

function patientFullName(patientDetails: any, answers: Record<string, any>): string {
  const fromBlock = safeStr(patientDetails.fullName);
  if (fromBlock) return fromBlock;

  const first = readTextAnswer(answers, "patient.firstName");
  const last = readTextAnswer(answers, "patient.lastName");
  const combined = safeStr(`${first} ${last}`);
  return combined || "—";
}

function patientEmail(patientDetails: any, answers: Record<string, any>): string {
  const fromBlock = safeStr(patientDetails.email);
  if (fromBlock) return fromBlock;
  return readTextAnswer(answers, "patient.email") || "—";
}

function patientPhone(patientDetails: any, answers: Record<string, any>): string {
  const fromBlock = safeStr(patientDetails.phone);
  if (fromBlock) return fromBlock;
  return readTextAnswer(answers, "patient.phone") || "—";
}
