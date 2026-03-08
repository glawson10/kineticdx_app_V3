/**
 * Commit 31: settings.deletePractitionerOverride
 * Hard delete a practitioner override.
 * Path: clinics/{clinicId}/practitioners/{practitionerId}/overrides/{overrideId}
 */

import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import { requireClinicPermission } from "../permissions";
import { writeSettingsAuditEvent } from "../audit/audit";
import { requireNonEmptyString } from "./validators";
import { mirrorPractitionerAvailabilityToLegacy } from "./mirrorPractitionerAvailabilityToLegacy";

const db = admin.firestore();

export async function deletePractitionerOverride(request: {
  auth?: { uid?: string };
  data?: unknown;
}) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }

  const data = request.data as Record<string, unknown> | undefined;
  const clinicId = requireNonEmptyString(data?.clinicId, "clinicId");
  const practitionerId = requireNonEmptyString(data?.practitionerId, "practitionerId");
  const overrideId = requireNonEmptyString(data?.overrideId, "overrideId");

  const uid = request.auth.uid;
  await requireClinicPermission(db, clinicId, uid, "settings.write");

  const ref = db
    .collection("clinics")
    .doc(clinicId)
    .collection("practitioners")
    .doc(practitionerId)
    .collection("overrides")
    .doc(overrideId);

  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Override not found.");
  }

  await ref.delete();

  const entityPath = `clinics/${clinicId}/practitioners/${practitionerId}/overrides/${overrideId}`;
  await writeSettingsAuditEvent(db, clinicId, "settings.override.deleted", uid, entityPath, overrideId, {
    deleted: true,
  });

  await mirrorPractitionerAvailabilityToLegacy(clinicId, practitionerId);
  return { ok: true };
}
