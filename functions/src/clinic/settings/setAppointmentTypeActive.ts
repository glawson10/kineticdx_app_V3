/**
 * settings.setAppointmentTypeActive
 * Toggle active flag for an appointment type.
 * Write path: clinics/{clinicId}/appointmentTypes/{appointmentTypeId}
 */

import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import { requireClinicPermission } from "../permissions";
import { writeSettingsAuditEvent } from "../audit/audit";
import { requireNonEmptyString } from "./validators";

const db = admin.firestore();
const FV = admin.firestore.FieldValue;

export async function setAppointmentTypeActive(request: { auth?: { uid?: string }; data?: unknown }) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }

  const data = request.data as Record<string, unknown> | undefined;
  const clinicId = requireNonEmptyString(data?.clinicId, "clinicId");
  const appointmentTypeId = requireNonEmptyString(data?.appointmentTypeId, "appointmentTypeId");

  if (typeof data?.active !== "boolean") {
    throw new HttpsError("invalid-argument", "active must be a boolean.");
  }
  const active: boolean = data.active;

  const uid = request.auth.uid;
  await requireClinicPermission(db, clinicId, uid, "settings.write");

  const ref = db
    .collection("clinics")
    .doc(clinicId)
    .collection("appointmentTypes")
    .doc(appointmentTypeId);

  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Appointment type not found.");
  }

  const beforeActive = snap.data()?.active;
  await ref.update({ active, updatedAt: FV.serverTimestamp() });

  const entityPath = `clinics/${clinicId}/appointmentTypes/${appointmentTypeId}`;
  await writeSettingsAuditEvent(
    db,
    clinicId,
    "settings.appointmentType.active_set",
    uid,
    entityPath,
    appointmentTypeId,
    { active: { before: beforeActive, after: active } }
  );
  return { ok: true };
}
