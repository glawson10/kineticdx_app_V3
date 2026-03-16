import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import { requireClinicPermission } from "../permissions";
import { writeSettingsAuditEvent } from "../audit/audit";

const db = admin.firestore();
const FV = admin.firestore.FieldValue;

function requireNonEmptyString(value: unknown, name: string): string {
  const s = typeof value === "string" ? value.trim() : "";
  if (!s) throw new HttpsError("invalid-argument", `${name} is required.`);
  return s;
}

export async function updateOnlineBookingEnablement(request: { auth?: { uid?: string }; data?: unknown }) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }

  const data = (request.data ?? {}) as Record<string, unknown>;
  const clinicId = requireNonEmptyString(data.clinicId, "clinicId");
  const enabled = data.enabled === true;

  const uid = request.auth.uid;
  await requireClinicPermission(db, clinicId, uid, "settings.write");

  const ref = db.doc(`clinics/${clinicId}/settings/publicBooking`);
  const snap = await ref.get();
  const before = snap.exists ? (snap.data()?.onlineBookingEnabled === true) : false;

  await ref.set(
    { onlineBookingEnabled: enabled, updatedAt: FV.serverTimestamp(), updatedByUid: uid },
    { merge: true }
  );

  await writeSettingsAuditEvent(
    db,
    clinicId,
    "settings.onlineBooking.enablement.updated",
    uid,
    `clinics/${clinicId}/settings/publicBooking`,
    "publicBooking",
    { onlineBookingEnabled: { before, after: enabled } }
  );

  return { ok: true, onlineBookingEnabled: enabled };
}
