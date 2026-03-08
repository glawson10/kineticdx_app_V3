/**
 * Commit 31: settings.upsertPractitionerOverride
 * Create or update a time-bounded override for a practitioner.
 * Path: clinics/{clinicId}/practitioners/{practitionerId}/overrides/{overrideId}
 */

import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import { requireClinicPermission } from "../permissions";
import { writeSettingsAuditEvent } from "../audit/audit";
import { requireNonEmptyString, assertString } from "./validators";
import { parseTimestampInput } from "./practitionerAvailabilityValidation";
import { mirrorPractitionerAvailabilityToLegacy } from "./mirrorPractitionerAvailabilityToLegacy";

const db = admin.firestore();
const FV = admin.firestore.FieldValue;

const OVERRIDE_REASON_SET = new Set(["sickness", "holiday", "training", "other"]);

function validateOverridePatch(patch: unknown): {
  locationId: string | null;
  fromAt: admin.firestore.Timestamp;
  toAt: admin.firestore.Timestamp;
  isAvailable: boolean;
  description: string | null;
  reason: string | null;
} {
  if (patch == null || typeof patch !== "object") {
    throw new HttpsError("invalid-argument", "patch is required.");
  }
  const p = patch as Record<string, unknown>;

  const fromAt = parseTimestampInput(p.fromAt, "fromAt");
  const toAt = parseTimestampInput(p.toAt, "toAt");
  if (toAt.toMillis() <= fromAt.toMillis()) {
    throw new HttpsError("invalid-argument", "toAt must be after fromAt.");
  }

  const isAvailableRaw = p.isAvailable;
  if (isAvailableRaw === undefined || isAvailableRaw === null) {
    throw new HttpsError("invalid-argument", "isAvailable is required.");
  }
  if (typeof isAvailableRaw !== "boolean") {
    throw new HttpsError("invalid-argument", "isAvailable must be a boolean.");
  }

  const locationId =
    p.locationId === null || p.locationId === undefined || p.locationId === ""
      ? null
      : assertString(p.locationId, "locationId", { trim: true });
  const description =
    assertString(p.description, "description", { trim: true, maxLength: 200 }) ?? null;

  const reasonRaw = assertString(p.reason, "reason", { trim: true, maxLength: 32 });
  const reason =
    reasonRaw && reasonRaw.length > 0
      ? OVERRIDE_REASON_SET.has(reasonRaw)
        ? reasonRaw
        : null
      : null;

  return {
    locationId: locationId ?? null,
    fromAt,
    toAt,
    isAvailable: isAvailableRaw,
    description,
    reason,
  };
}

export async function upsertPractitionerOverride(request: {
  auth?: { uid?: string };
  data?: unknown;
}) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }

  const data = request.data as Record<string, unknown> | undefined;
  const clinicId = requireNonEmptyString(data?.clinicId, "clinicId");
  const practitionerId = requireNonEmptyString(data?.practitionerId, "practitionerId");
  const overrideIdRaw = data?.overrideId;
  const overrideId =
    overrideIdRaw === null || overrideIdRaw === undefined || overrideIdRaw === ""
      ? null
      : String(overrideIdRaw).trim();
  const isCreate = !overrideId || overrideId.length === 0;

  let validated: ReturnType<typeof validateOverridePatch>;
  try {
    validated = validateOverridePatch(data?.patch);
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    throw new HttpsError("invalid-argument", e instanceof Error ? e.message : "Invalid patch.");
  }

  const uid = request.auth.uid;
  await requireClinicPermission(db, clinicId, uid, "settings.write");

  const colRef = db
    .collection("clinics")
    .doc(clinicId)
    .collection("practitioners")
    .doc(practitionerId)
    .collection("overrides");

  const now = FV.serverTimestamp();

  if (isCreate) {
    const docId = colRef.doc().id;
    await colRef.doc(docId).set({
      locationId: validated.locationId ?? null,
      fromAt: validated.fromAt,
      toAt: validated.toAt,
      isAvailable: validated.isAvailable,
      description: validated.description ?? null,
      reason: validated.reason ?? null,
      createdAt: now,
      updatedAt: now,
    });
    const entityPath = `clinics/${clinicId}/practitioners/${practitionerId}/overrides/${docId}`;
    await writeSettingsAuditEvent(
      db,
      clinicId,
      "settings.override.created",
      uid,
      entityPath,
      docId,
      { fromAt: validated.fromAt.toMillis(), toAt: validated.toAt.toMillis(), isAvailable: validated.isAvailable }
    );
    await mirrorPractitionerAvailabilityToLegacy(clinicId, practitionerId);
    return { ok: true, overrideId: docId };
  }

  const ref = colRef.doc(overrideId!);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Override not found.");
  }

  await ref.update({
    locationId: validated.locationId ?? null,
    fromAt: validated.fromAt,
    toAt: validated.toAt,
    isAvailable: validated.isAvailable,
    description: validated.description ?? null,
    reason: validated.reason ?? null,
    updatedAt: now,
  });
  const entityPath = `clinics/${clinicId}/practitioners/${practitionerId}/overrides/${overrideId}`;
  await writeSettingsAuditEvent(db, clinicId, "settings.override.updated", uid, entityPath, overrideId, {
    fromAt: validated.fromAt.toMillis(),
    toAt: validated.toAt.toMillis(),
    isAvailable: validated.isAvailable,
  });
  await mirrorPractitionerAvailabilityToLegacy(clinicId, practitionerId);
  return { ok: true, overrideId };
}
