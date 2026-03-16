/**
 * settings.updateLocationDisplayOrder
 * Set display order of locations (locationIds array).
 * Write path: clinics/{clinicId}/settings/locationDisplay
 * Audit: settings.locationDisplay.updated
 */

import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import { requireClinicPermission } from "../permissions";
import { writeSettingsAuditEvent } from "../audit/audit";
import { requireNonEmptyString } from "./validators";

const db = admin.firestore();
const FV = admin.firestore.FieldValue;

function requireLocationIds(value: unknown): string[] {
  if (!Array.isArray(value)) {
    throw new HttpsError("invalid-argument", "locationIds must be an array of strings.");
  }
  const out = value
    .map((v) => (typeof v === "string" ? v.trim() : String(v ?? "").trim()))
    .filter(Boolean);
  return out;
}

export async function updateLocationDisplayOrder(request: { auth?: { uid?: string }; data?: unknown }) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }

  const data = request.data as Record<string, unknown> | undefined;
  const clinicId = requireNonEmptyString(data?.clinicId, "clinicId");
  const locationIds = requireLocationIds(data?.locationIds);

  const uid = request.auth.uid;
  await requireClinicPermission(db, clinicId, uid, "settings.write");

  const ref = db.doc(`clinics/${clinicId}/settings/locationDisplay`);
  await ref.set(
    { locationIds, updatedAt: FV.serverTimestamp() },
    { merge: true }
  );

  await writeSettingsAuditEvent(
    db,
    clinicId,
    "settings.locationDisplay.updated",
    uid,
    `clinics/${clinicId}/settings`,
    "locationDisplay",
    { locationIds }
  );

  return { ok: true };
}
