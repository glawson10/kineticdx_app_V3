// functions/src/clinic/intake/computeIntakeSummary.ts
import * as admin from "firebase-admin";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";

if (!admin.apps.length) {
  admin.initializeApp();
}

type Triage = {
  status: "red" | "amber" | "green";
  reasons: string[];
};

function asString(v: unknown): string {
  return v == null ? "" : String(v);
}

function nowServer(): FirebaseFirestore.FieldValue {
  return admin.firestore.FieldValue.serverTimestamp();
}

function getFlowId(session: any): string {
  return (
    session?.flow?.flowId ??
    session?.flowId ??
    session?.regionSelection?.bodyArea ??
    ""
  );
}

/**
 * Phase 3 summary: triage + patient-safe narrative only.
 * No differentials, no tests.
 */
function buildPhase3Summary(session: any): {
  status: "ready";
  flowId: string;
  triage: Triage;
  narrative: string;
  generatedAt: FirebaseFirestore.FieldValue;
} {
  const flowId = getFlowId(session);

  const triage: Triage =
    session?.triage &&
    typeof session.triage === "object" &&
    typeof session.triage.status === "string"
      ? {
          status: (session.triage.status as any) ?? "green",
          reasons: Array.isArray(session.triage.reasons)
            ? session.triage.reasons.map((x: any) => asString(x))
            : [],
        }
      : { status: "green", reasons: [] };

  const narrative =
    typeof session?.summary?.narrative === "string"
      ? session.summary.narrative
      : "";

  return {
    status: "ready",
    flowId,
    triage,
    narrative,
    generatedAt: nowServer(),
  };
}

/**
 * Gen2 Callable (v2):
 * - Region pinned here so it remains consistent even if exported via `export *`
 * - If you prefer centralizing region in index.ts, we can instead export a handler function,
 *   but this drop-in keeps your current pattern.
 */
export const computeIntakeSummaryV2 = onCall(
  { region: "europe-west3", cors: true },
  async (req) => {
    try {
      const clinicId = asString(req.data?.clinicId);
      const intakeSessionId = asString(req.data?.intakeSessionId);

      if (!clinicId || !intakeSessionId) {
        throw new HttpsError(
          "invalid-argument",
          "clinicId and intakeSessionId are required",
          { clinicId, intakeSessionId }
        );
      }

      const ref = admin
        .firestore()
        .collection("clinics")
        .doc(clinicId)
        .collection("intakeSessions")
        .doc(intakeSessionId);

      const snap = await ref.get();
      if (!snap.exists) {
        throw new HttpsError("not-found", "Intake session not found", {
          clinicId,
          intakeSessionId,
        });
      }

      const session = snap.data() || {};
      const flowId = getFlowId(session);

      const summary = buildPhase3Summary(session);

      await ref.set(
        {
          summary,
          summaryStatus: "ready",
          summaryError: admin.firestore.FieldValue.delete(),
          summaryUpdatedAt: nowServer(),
        },
        { merge: true }
      );

      return { ok: true, summaryStatus: "ready", flowId };
    } catch (err: any) {
      console.error("computeIntakeSummary crashed", err);

      throw new HttpsError("internal", err?.message ?? "Summary failed", {
        name: err?.name,
        stack: (err?.stack ?? "")
          .toString()
          .split("\n")
          .slice(0, 12)
          .join("\n"),
      });
    }
  }
);
