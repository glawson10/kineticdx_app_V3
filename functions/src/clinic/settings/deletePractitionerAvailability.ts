/**
 * Delete a practitioner availability rule.
 * Path: clinics/{clinicId}/practitioners/{practitionerId}/availability/{availabilityId}
 */

import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import { requireClinicPermission } from "../permissions";
import { writeSettingsAuditEvent } from "../audit/audit";
import { requireNonEmptyString } from "./validators";
import { mirrorPractitionerAvailabilityToLegacy } from "./mirrorPractitionerAvailabilityToLegacy";

const db = admin.firestore();

export async function deletePractitionerAvailability(request: {
  auth?: { uid?: string };
  data?: unknown;
}) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }

  const data = request.data as Record<string, unknown> | undefined;
  const clinicId = requireNonEmptyString(data?.clinicId, "clinicId");
  const practitionerId = requireNonEmptyString(data?.practitionerId, "practitionerId");
  const availabilityId = requireNonEmptyString(data?.availabilityId, "availabilityId");

  const uid = request.auth.uid;
  await requireClinicPermission(db, clinicId, uid, "settings.write");

  const ref = db
    .collection("clinics")
    .doc(clinicId)
    .collection("practitioners")
    .doc(practitionerId)
    .collection("availability")
    .doc(availabilityId);

  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Availability rule not found.");
  }

  const entityPath = `clinics/${clinicId}/practitioners/${practitionerId}/availability/${availabilityId}`;
  const docData = snap.data() ?? {};
  await writeSettingsAuditEvent(db, clinicId, "settings.availability.deleted", uid, entityPath, availabilityId, {
    deleted: true,
    locationId: docData.locationId ?? null,
    startDate: docData.startDate ?? null,
  });

  await ref.delete();
  await mirrorPractitionerAvailabilityToLegacy(clinicId, practitionerId);
  return { ok: true };
}
