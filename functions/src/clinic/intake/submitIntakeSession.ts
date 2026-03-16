// functions/src/clinic/intake/submitIntakeSession.ts
//
// ✅ Updated in full:
// - Keeps transaction read-before-write discipline
// - ✅ Supports generalVisit submissions (regionSelection optional for generalVisit)
// - ✅ Adds top-level flowId/flowVersion for easier querying
// - ✅ Adds flowCategory: "general" | "region" for clean tab queries
// - ✅ FIX: never allocates a new session id when caller provides a non-draft id
//   (critical for invite/link flows so sessionId stays stable)
// - Keeps idempotency + invite usedAt handling
//
// IMPORTANT:
// - This file MUST be compiled to functions/lib before deploy:
//     cd functions
//     npm run build
//     cd ..
//     firebase deploy --only functions:submitIntakeSessionFn

import * as admin from "firebase-admin";
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/logger";

import { schemaVersion } from "../../schema/schemaVersions";

type AnswerValue =
  | { t: "bool"; v: boolean }
  | { t: "int"; v: number }
  | { t: "num"; v: number }
  | { t: "text"; v: string }
  | { t: "single"; v: string }
  | { t: "multi"; v: string[] }
  | { t: "date"; v: string }
  | { t: "map"; v: Record<string, any> };

type SubmitIntakeRequest = {
  clinicId: string;
  sessionId: string; // can be "draft" (client placeholder) or real id
  intakeSchemaVersion: number;

  flowId: string;
  flowVersion: number;

  /** PA-P3: optional registry snapshot from client draft */
  templateId?: string | null;
  flowDefinitionId?: string | null;
  clinicalProfileId?: string | null;
  summaryEngine?: string | null;
  decisionSupportProfile?: string | null;
  supportsDifferentialHypothesis?: boolean;

  consent: {
    policyBundleId: string;
    policyBundleVersion: number;
    locale: string;
    termsAccepted: boolean;
    privacyAccepted: boolean;
    dataStorageAccepted: boolean;
    notEmergencyAck: boolean;
    noDiagnosisAck: boolean;
    consentToContact: boolean;
  };

  patientDetails: {
    firstName: string;
    lastName: string;
    dateOfBirth?: string | null;
    email?: string;
    phone?: string;
    isProxy?: boolean;
    proxyName?: string | null;
    proxyRelationship?: string | null;
  };

  // ✅ Optional: generalVisit does not require regionSelection
  regionSelection?: {
    bodyArea: string;
    side: string;
    regionSetVersion: number;
  };

  answers: Record<string, AnswerValue>;
};

function assertString(x: any, field: string) {
  if (typeof x !== "string" || x.trim().length === 0) {
    throw new HttpsError("invalid-argument", `Missing/invalid ${field}`);
  }
}
function assertNumber(x: any, field: string) {
  if (typeof x !== "number" || Number.isNaN(x)) {
    throw new HttpsError("invalid-argument", `Missing/invalid ${field}`);
  }
}
function assertBool(x: any, field: string) {
  if (typeof x !== "boolean") {
    throw new HttpsError("invalid-argument", `Missing/invalid ${field}`);
  }
}

function normalizeRegion(bodyArea: string) {
  const s = (bodyArea ?? "").toString().trim();
  if (!s) return s;
  return s.startsWith("region.") ? s : `region.${s}`;
}

function validateAnswerValue(v: any, key: string) {
  if (!v || typeof v !== "object") {
    throw new HttpsError("invalid-argument", `Answer ${key} invalid`);
  }
  if (typeof v.t !== "string") {
    throw new HttpsError("invalid-argument", `Answer ${key} missing t`);
  }
  if (!("v" in v)) {
    throw new HttpsError("invalid-argument", `Answer ${key} missing v`);
  }

  switch (v.t) {
    case "bool":
      if (typeof v.v !== "boolean") {
        throw new HttpsError("invalid-argument", `Answer ${key} must be bool`);
      }
      break;

    case "int":
      if (typeof v.v !== "number" || !Number.isInteger(v.v)) {
        throw new HttpsError("invalid-argument", `Answer ${key} must be int`);
      }
      break;

    case "num":
      if (typeof v.v !== "number") {
        throw new HttpsError("invalid-argument", `Answer ${key} must be num`);
      }
      break;

    case "text":
      if (typeof v.v !== "string") {
        throw new HttpsError("invalid-argument", `Answer ${key} must be text`);
      }
      break;

    case "single":
      if (typeof v.v !== "string") {
        throw new HttpsError("invalid-argument", `Answer ${key} must be single`);
      }
      break;

    case "multi":
      if (!Array.isArray(v.v) || v.v.some((x: any) => typeof x !== "string")) {
        throw new HttpsError("invalid-argument", `Answer ${key} must be multi`);
      }
      break;

    case "date":
      if (typeof v.v !== "string") {
        throw new HttpsError("invalid-argument", `Answer ${key} must be date`);
      }
      break;

    case "map":
      if (typeof v.v !== "object" || v.v === null || Array.isArray(v.v)) {
        throw new HttpsError("invalid-argument", `Answer ${key} must be map`);
      }
      break;

    default:
      throw new HttpsError(
        "invalid-argument",
        `Answer ${key} has invalid t=${v.t}`
      );
  }
}

export async function submitIntakeSession(
  req: CallableRequest<SubmitIntakeRequest>
) {
  try {
    logger.info("🔥 submitIntakeSessionFn HIT", { hasAuth: !!req.auth });

    const data = (req.data ?? {}) as Partial<SubmitIntakeRequest>;

    assertString(data.clinicId, "clinicId");
    assertString(data.sessionId, "sessionId");
    assertNumber(data.intakeSchemaVersion, "intakeSchemaVersion");
    assertString(data.flowId, "flowId");
    assertNumber(data.flowVersion, "flowVersion");

    if (!data.consent)
      throw new HttpsError("invalid-argument", "Missing consent");
    if (!data.patientDetails)
      throw new HttpsError("invalid-argument", "Missing patientDetails");
    if (!data.answers)
      throw new HttpsError("invalid-argument", "Missing answers");

    const clinicId = data.clinicId!.trim();
    const sessionIdRaw = data.sessionId!.trim();
    const intakeSchemaVersion = data.intakeSchemaVersion!;
    const flowId = data.flowId!.trim();
    const flowVersion = data.flowVersion!;

    const isGeneralVisit = flowId === "generalVisit";
    const flowCategory: "general" | "region" = isGeneralVisit
      ? "general"
      : "region";

    const db = admin.firestore();

    const clinicSnap = await db.collection("clinics").doc(clinicId).get();
    if (!clinicSnap.exists) {
      throw new HttpsError("not-found", "Clinic does not exist");
    }

    const expected = schemaVersion("intakeSession");
    if (intakeSchemaVersion !== expected) {
      throw new HttpsError(
        "failed-precondition",
        `Schema mismatch client=${intakeSchemaVersion} server=${expected}`
      );
    }

    const c = data.consent!;
    assertString(c.policyBundleId, "consent.policyBundleId");
    assertNumber(c.policyBundleVersion, "consent.policyBundleVersion");
    assertString(c.locale, "consent.locale");
    assertBool(c.termsAccepted, "consent.termsAccepted");
    assertBool(c.privacyAccepted, "consent.privacyAccepted");
    assertBool(c.dataStorageAccepted, "consent.dataStorageAccepted");
    assertBool(c.notEmergencyAck, "consent.notEmergencyAck");
    assertBool(c.noDiagnosisAck, "consent.noDiagnosisAck");
    assertBool(c.consentToContact, "consent.consentToContact");

    if (
      !c.termsAccepted ||
      !c.privacyAccepted ||
      !c.dataStorageAccepted ||
      !c.notEmergencyAck ||
      !c.noDiagnosisAck
    ) {
      throw new HttpsError("failed-precondition", "Consent incomplete");
    }

    const p = data.patientDetails!;
    assertString(p.firstName, "patientDetails.firstName");
    assertString(p.lastName, "patientDetails.lastName");

    // ✅ Region selection: required for region flows, optional for generalVisit
    let normalizedBodyArea = "";
    let regionSelectionToWrite: any = null;

    if (!isGeneralVisit) {
      if (!data.regionSelection) {
        throw new HttpsError("invalid-argument", "Missing regionSelection");
      }

      const r = data.regionSelection!;
      assertString(r.bodyArea, "regionSelection.bodyArea");
      assertString(r.side, "regionSelection.side");
      assertNumber(r.regionSetVersion, "regionSelection.regionSetVersion");

      normalizedBodyArea = normalizeRegion(r.bodyArea);

      regionSelectionToWrite = {
        ...r,
        bodyArea: normalizedBodyArea,
        // selectedAt gets written inside transaction with `now`
      };
    } else {
      // If a client accidentally sends regionSelection, ignore it for generalVisit.
      regionSelectionToWrite = null;
    }

    const answers = data.answers!;
    for (const [k, v] of Object.entries(answers)) validateAnswerValue(v, k);

    logger.info("✅ payload validated", {
      clinicId,
      sessionIdRaw,
      flowId,
      flowVersion,
      flowCategory,
      bodyArea: normalizedBodyArea,
      hasRegionSelection: !!regionSelectionToWrite,
      answersCount: Object.keys(answers).length,
    });

    const now = admin.firestore.FieldValue.serverTimestamp();

    const sessionsCol = db
      .collection("clinics")
      .doc(clinicId)
      .collection("intakeSessions");

    const invitesCol = db
      .collection("clinics")
      .doc(clinicId)
      .collection("intakeInvites");

    const shouldAutoCreate = sessionIdRaw.toLowerCase() === "draft";

    let finalSessionId = sessionIdRaw;

    await db.runTransaction(async (tx) => {
      // ─────────────────────────────────────────────
      // READS (ALL reads must happen before ANY writes)
      // ─────────────────────────────────────────────

      // ✅ If draft: allocate new doc id
      // ✅ If non-draft: ALWAYS use the provided id (never swap ids)
      const intakeRef = shouldAutoCreate
        ? sessionsCol.doc()
        : sessionsCol.doc(sessionIdRaw);

      const intakeSnap = await tx.get(intakeRef);
      finalSessionId = intakeRef.id;

      const existing = intakeSnap.exists ? (intakeSnap.data() ?? {}) : {};

      // Read invite (Option B) before any writes
      const inviteQ = await tx.get(
        invitesCol.where("sessionId", "==", intakeRef.id).limit(1)
      );

      const invDoc = inviteQ.empty ? null : inviteQ.docs[0];
      const invRef = invDoc?.ref ?? null;
      const inv = invDoc?.data() as any | undefined;

      // Idempotency (if already submitted, do nothing)
      if (
        (existing as any).submittedAt ||
        (existing as any).status === "submitted"
      ) {
        return;
      }

      // ─────────────────────────────────────────────
      // WRITES (ONLY after reads)
      // ─────────────────────────────────────────────
      tx.set(
        intakeRef,
        {
          schemaVersion: intakeSchemaVersion,
          clinicId,
          createdBy: { kind: "patient" as const },

          status: "submitted",
          submittedAt: now,
          lockedAt: now,
          updatedAt: now,

          // ✅ Keep nested flow, plus top-level for easy querying/indexing
          flow: { flowId, flowVersion },
          flowId,
          flowVersion,
          flowCategory, // "general" | "region"

          ...(data.templateId != null && String(data.templateId).trim() !== ""
            ? { templateId: String(data.templateId).trim() }
            : {}),
          ...(data.flowDefinitionId != null && String(data.flowDefinitionId).trim() !== ""
            ? { flowDefinitionId: String(data.flowDefinitionId).trim() }
            : {}),
          ...(data.clinicalProfileId != null && String(data.clinicalProfileId).trim() !== ""
            ? { clinicalProfileId: String(data.clinicalProfileId).trim() }
            : {}),
          ...(data.summaryEngine != null && String(data.summaryEngine).trim() !== ""
            ? { summaryEngine: String(data.summaryEngine).trim() }
            : {}),
          ...(data.decisionSupportProfile != null && String(data.decisionSupportProfile).trim() !== ""
            ? { decisionSupportProfile: String(data.decisionSupportProfile).trim() }
            : {}),
          ...(typeof data.supportsDifferentialHypothesis === "boolean"
            ? { supportsDifferentialHypothesis: data.supportsDifferentialHypothesis }
            : {}),

          consent: { ...c, acceptedAt: now },

          patientDetails: {
            ...p,
            firstName: p.firstName.trim(),
            lastName: p.lastName.trim(),
            confirmedAt: now,
          },

          // ✅ Only write regionSelection for region flows
          ...(regionSelectionToWrite
            ? {
                regionSelection: {
                  ...regionSelectionToWrite,
                  selectedAt: now,
                },
              }
            : {}),

          answers,

          // Region flows still use triage; generalVisit can default to green (harmless)
          triage: { status: "green", reasons: [] as string[] },

          // Preserve original createdAt if it exists; otherwise set now.
          createdAt: (existing as any).createdAt ?? now,
        },
        { merge: true }
      );

      if (invRef && inv && !inv.usedAt) {
        tx.set(
          invRef,
          { usedAt: now, submittedSessionId: intakeRef.id },
          { merge: true }
        );
      }
    });

    logger.info("✅ intakeSession submitted", {
      clinicId,
      sessionId: finalSessionId,
      flowId,
      flowCategory,
    });

    return { ok: true, intakeSessionId: finalSessionId };
  } catch (err: any) {
    if (err instanceof HttpsError) {
      logger.warn("submitIntakeSession rejected", {
        code: err.code,
        message: err.message,
      });
      throw err;
    }

    logger.error("submitIntakeSession crashed", err);
    throw new HttpsError("internal", "submitIntakeSession crashed", {
      message: err?.message ?? String(err),
    });
  }
}
