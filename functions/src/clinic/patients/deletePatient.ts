import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/logger";

import { requireActiveMemberWithPerm } from "../authz";

type Input = {
  clinicId: string;
  patientId: string;
};

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

async function requireOwnerOrManagerLike(
  db: admin.firestore.Firestore,
  clinicId: string,
  uid: string
) {
  // Preferred: explicit perms
  try {
    await requireActiveMemberWithPerm(db, clinicId, uid, "patients.manage");
    return;
  } catch (_) {
    // fallback: settings.write is typically owner/manager in your model
  }

  await requireActiveMemberWithPerm(db, clinicId, uid, "settings.write");
}

export async function deletePatient(req: CallableRequest<Input>) {
  try {
    if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

    const clinicId = safeStr(req.data?.clinicId);
    const patientId = safeStr(req.data?.patientId);
    if (!clinicId) throw new HttpsError("invalid-argument", "clinicId is required.");
    if (!patientId) throw new HttpsError("invalid-argument", "patientId is required.");

    const uid = req.auth.uid;
    const db = admin.firestore();

    await requireOwnerOrManagerLike(db, clinicId, uid);

    const patientRef = db.collection("clinics").doc(clinicId).collection("patients").doc(patientId);
    const snap = await patientRef.get();
    if (!snap.exists) throw new HttpsError("not-found", "Patient not found.");

    const now = admin.firestore.FieldValue.serverTimestamp();

    // Soft delete (safe + reversible)
    await patientRef.set(
      {
        active: false,
        archived: true, // legacy
        status: {
          active: false,
          archived: true,
          archivedAt: now,
        },
        deletedAt: now,
        deletedByUid: uid,
        updatedAt: now,
        updatedByUid: uid,
      },
      { merge: true }
    );

    logger.info("deletePatient ok", { clinicId, patientId, uid });
    return { ok: true };
  } catch (err: any) {
    logger.error("deletePatient failed", {
      err: err?.message ?? String(err),
      code: err?.code,
      details: err?.details,
      stack: err?.stack,
    });

    if (err instanceof HttpsError) throw err;
    throw new HttpsError("internal", "deletePatient crashed. Check logs.", {
      original: err?.message ?? String(err),
    });
  }
}
