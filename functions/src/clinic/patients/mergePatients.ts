import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/logger";

import { requireActiveMemberWithPerm } from "../authz";

type Input = {
  clinicId: string;
  sourcePatientId: string; // will be archived
  targetPatientId: string; // kept as canonical/original
};

type AnyMap = Record<string, any>;

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

function isEmptyValue(v: any): boolean {
  if (v === null || v === undefined) return true;
  if (typeof v === "string") return v.trim().length === 0;
  return false;
}

function getNested(obj: AnyMap, path: string): any {
  const parts = path.split(".");
  let cur: any = obj;
  for (const p of parts) {
    if (!cur || typeof cur !== "object") return undefined;
    cur = cur[p];
  }
  return cur;
}

function setNested(obj: AnyMap, path: string, value: any) {
  const parts = path.split(".");
  let cur: any = obj;
  for (let i = 0; i < parts.length - 1; i++) {
    const p = parts[i];
    if (!cur[p] || typeof cur[p] !== "object") cur[p] = {};
    cur = cur[p];
  }
  cur[parts[parts.length - 1]] = value;
}

function buildPatientDisplayName(patient: AnyMap): string {
  const fn = safeStr(getNested(patient, "identity.firstName") ?? patient.firstName);
  const ln = safeStr(getNested(patient, "identity.lastName") ?? patient.lastName);
  const full = `${fn} ${ln}`.trim();
  return full || safeStr(patient.fullName) || "";
}

function fillIfEmptyPatch(params: { target: AnyMap; source: AnyMap; fields: string[] }): AnyMap {
  const { target, source, fields } = params;
  const patch: AnyMap = {};

  for (const f of fields) {
    const t = getNested(target, f);
    if (!isEmptyValue(t)) continue;

    const s = getNested(source, f);
    if (isEmptyValue(s)) continue;

    setNested(patch, f, s);
  }

  return patch;
}

async function reassignRefs(params: {
  db: admin.firestore.Firestore;
  clinicId: string;
  sourcePatientId: string;
  targetPatientId: string;
  targetPatientName: string;
}) {
  const { db, clinicId, sourcePatientId, targetPatientId, targetPatientName } = params;

  let updated = 0;
  const col = db.collection("clinics").doc(clinicId).collection("appointments");
  const pageSize = 400;

  while (true) {
    const snap = await col.where("patientId", "==", sourcePatientId).limit(pageSize).get();
    if (snap.empty) break;

    const batch = db.batch();
    for (const doc of snap.docs) {
      const update: AnyMap = {
        patientId: targetPatientId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (safeStr(targetPatientName)) update.patientName = targetPatientName;

      batch.update(doc.ref, update);
      updated++;
    }

    await batch.commit();
    if (snap.size < pageSize) break;
  }

  return updated;
}

/**
 * Firestore transactions sometimes rethrow errors as plain objects.
 * This preserves the original callable error code/message if present.
 */
function throwIfHttpsErrorLike(err: any): never {
  const code = err?.code;
  const message = err?.message;
  const details = err?.details;

  const allowed = new Set([
    "cancelled",
    "unknown",
    "invalid-argument",
    "deadline-exceeded",
    "not-found",
    "already-exists",
    "permission-denied",
    "resource-exhausted",
    "failed-precondition",
    "aborted",
    "out-of-range",
    "unimplemented",
    "internal",
    "unavailable",
    "data-loss",
    "unauthenticated",
  ]);

  if (typeof code === "string" && allowed.has(code) && typeof message === "string") {
    throw new HttpsError(code as any, message, details);
  }

  throw err;
}

export async function mergePatients(req: CallableRequest<Input>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = safeStr(req.data?.clinicId);
  const sourcePatientId = safeStr(req.data?.sourcePatientId);
  const targetPatientId = safeStr(req.data?.targetPatientId);

  if (!clinicId) throw new HttpsError("invalid-argument", "clinicId is required.");
  if (!sourcePatientId) throw new HttpsError("invalid-argument", "sourcePatientId is required.");
  if (!targetPatientId) throw new HttpsError("invalid-argument", "targetPatientId is required.");
  if (sourcePatientId === targetPatientId) {
    throw new HttpsError("invalid-argument", "sourcePatientId and targetPatientId must differ.");
  }

  const uid = req.auth.uid;
  const db = admin.firestore();

  await requireActiveMemberWithPerm(db, clinicId, uid, "patients.write");

  const sourceRef = db.collection("clinics").doc(clinicId).collection("patients").doc(sourcePatientId);
  const targetRef = db.collection("clinics").doc(clinicId).collection("patients").doc(targetPatientId);

  const fillFields: string[] = [
    "identity.firstName",
    "identity.lastName",
    "identity.preferredName",
    "identity.dateOfBirth",
    "contact.email",
    "contact.phone",
    "contact.preferredMethod",
    "contact.address.line1",
    "contact.address.city",
    "contact.address.postcode",
    "contact.address.country",
    "emergencyContact.name",
    "emergencyContact.relationship",
    "emergencyContact.phone",
    "adminNotes",
  ];

  const legacyFillFields: string[] = ["firstName", "lastName", "dob", "email", "phone", "address"];

  try {
    const now = admin.firestore.FieldValue.serverTimestamp();

    const result = await db.runTransaction(async (tx) => {
      const [sourceSnap, targetSnap] = await Promise.all([tx.get(sourceRef), tx.get(targetRef)]);

      if (!sourceSnap.exists) {
        throw new HttpsError("not-found", "Source patient not found.");
      }
      if (!targetSnap.exists) {
        throw new HttpsError("not-found", "Target patient not found.");
      }

      const source = (sourceSnap.data() ?? {}) as AnyMap;
      const target = (targetSnap.data() ?? {}) as AnyMap;

      const alreadyMergedInto = safeStr(source.mergedIntoPatientId);
      if (alreadyMergedInto) {
        throw new HttpsError(
          "failed-precondition",
          `Source patient is already merged into ${alreadyMergedInto}.`
        );
      }

      const patch1 = fillIfEmptyPatch({ target, source, fields: fillFields });
      const patch2 = fillIfEmptyPatch({ target, source, fields: legacyFillFields });

      const targetTags = Array.isArray(target.tags) ? target.tags : [];
      const sourceTags = Array.isArray(source.tags) ? source.tags : [];
      const targetAlerts = Array.isArray(target.alerts) ? target.alerts : [];
      const sourceAlerts = Array.isArray(source.alerts) ? source.alerts : [];

      const tagPatch: AnyMap = {};
      if (targetTags.length === 0 && sourceTags.length > 0) tagPatch.tags = sourceTags;

      const alertPatch: AnyMap = {};
      if (targetAlerts.length === 0 && sourceAlerts.length > 0) alertPatch.alerts = sourceAlerts;

      const mergedTargetUpdate: AnyMap = {
        ...patch1,
        ...patch2,
        ...tagPatch,
        ...alertPatch,
        updatedAt: now,
        updatedByUid: uid,
        lastMergeAt: now,
        lastMergeFromPatientId: sourcePatientId,
      };

      tx.set(targetRef, mergedTargetUpdate, { merge: true });

      const sourceStatus = source.status && typeof source.status === "object" ? source.status : {};

      tx.set(
        sourceRef,
        {
          updatedAt: now,
          updatedByUid: uid,
          active: false,
          status: {
            ...sourceStatus,
            active: false,
            archived: true,
            archivedAt: now,
          },
          mergedIntoPatientId: targetPatientId,
          mergedAt: now,
          mergedByUid: uid,
        },
        { merge: true }
      );

      const mergedTargetSim = { ...target, ...mergedTargetUpdate };
      const targetPatientName = buildPatientDisplayName(mergedTargetSim);

      return { targetPatientName };
    });

    const updatedRefs = await reassignRefs({
      db,
      clinicId,
      sourcePatientId,
      targetPatientId,
      targetPatientName: result.targetPatientName,
    });

    logger.info("mergePatients ok", {
      clinicId,
      sourcePatientId,
      targetPatientId,
      updatedRefs,
      uid,
    });

    return { ok: true, updatedRefs };
  } catch (err: any) {
    logger.error("mergePatients failed", {
      clinicId,
      sourcePatientId,
      targetPatientId,
      uid,
      err: err?.message ?? String(err),
      code: err?.code,
      stack: err?.stack,
      details: err?.details,
    });

    if (err instanceof HttpsError) throw err;

    // ✅ preserve HttpsError-like objects
    try {
      throwIfHttpsErrorLike(err);
    } catch (e: any) {
      if (e instanceof HttpsError) throw e;
    }

    throw new HttpsError("internal", "mergePatients crashed. Check logs.", {
      original: err?.message ?? String(err),
    });
  }
}
