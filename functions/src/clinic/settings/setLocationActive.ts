/**
 * settings.setLocationActive
 * Toggle active flag for a location.
 * Write path: clinics/{clinicId}/locations/{locationId}
 * Audit: settings.location.activated (false→true) or settings.location.deactivated (true→false).
 */

import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import { requireClinicPermission } from "../permissions";
import { writeSettingsAuditEvent } from "../audit/audit";
import { requireNonEmptyString } from "./validators";

const db = admin.firestore();
const FV = admin.firestore.FieldValue;

export async function setLocationActive(request: { auth?: { uid?: string }; data?: unknown }) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }

  const data = request.data as Record<string, unknown> | undefined;
  const clinicId = requireNonEmptyString(data?.clinicId, "clinicId");
  const locationId = requireNonEmptyString(data?.locationId, "locationId");

  if (typeof data?.active !== "boolean") {
    throw new HttpsError("invalid-argument", "active must be a boolean.");
  }
  const active: boolean = data.active;

  const uid = request.auth.uid;
  await requireClinicPermission(db, clinicId, uid, "settings.write");

  const ref = db
    .collection("clinics")
    .doc(clinicId)
    .collection("locations")
    .doc(locationId);

  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Location not found.");
  }

  const beforeActive = snap.data()?.active;
  // TODO: Future guard: do not allow deactivating a location that has future appointments
  // (requires reliable query for appointments by locationId).
  await ref.update({ active, updatedAt: FV.serverTimestamp() });

  const entityPath = `clinics/${clinicId}/locations/${locationId}`;
  const eventType =
    beforeActive === false && active === true
      ? "settings.location.activated"
      : beforeActive === true && active === false
        ? "settings.location.deactivated"
        : "settings.location.active_set";
  await writeSettingsAuditEvent(db, clinicId, eventType, uid, entityPath, locationId, {
    active: { before: beforeActive, after: active },
  });
  return { ok: true };
}
