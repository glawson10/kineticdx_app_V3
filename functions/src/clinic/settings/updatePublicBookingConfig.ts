/**
 * settings.updatePublicBookingConfig
 * Partial update of public booking configuration.
 * Write path: clinics/{clinicId}/settings/publicBooking
 */

import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import { requireClinicPermission } from "../permissions";
import { writeSettingsAuditEvent } from "../audit/audit";
import {
  assertBoolean,
  assertIntRange,
  assertString,
  pickAllowedFields,
  requireNonEmptyString,
} from "./validators";

const db = admin.firestore();
const FV = admin.firestore.FieldValue;

const ALLOWED_KEYS = new Set([
  "slotStepMinutes",
  "minNoticeMinutes",
  "maxAdvanceDays",
  "requirePhone",
  "requireEmail",
  "allowNewPatients",
  "cancellationPolicyHours",
  "weeklyHours",
  "confirmationMessage",
]);

const VALID_SLOT_STEPS = new Set([5, 10, 15, 20, 30, 60]);

type PublicBookingPatch = Record<string, unknown>;

function validatePatch(patch: unknown): PublicBookingPatch {
  const raw = pickAllowedFields<PublicBookingPatch>(patch, ALLOWED_KEYS);

  if (Object.keys(raw).length === 0) {
    throw new HttpsError("invalid-argument", "No valid fields to update.");
  }

  const out: PublicBookingPatch = {};

  if (raw.slotStepMinutes !== undefined) {
    const v = assertIntRange(raw.slotStepMinutes, "slotStepMinutes", { min: 5, max: 60 });
    if (v != null) {
      if (!VALID_SLOT_STEPS.has(v)) {
        throw new HttpsError("invalid-argument", "slotStepMinutes must be one of: 5, 10, 15, 20, 30, 60.");
      }
      out.slotStepMinutes = v;
    }
  }

  if (raw.minNoticeMinutes !== undefined) {
    const v = assertIntRange(raw.minNoticeMinutes, "minNoticeMinutes", { min: 0, max: 43200 });
    if (v != null) out.minNoticeMinutes = v;
  }

  if (raw.maxAdvanceDays !== undefined) {
    const v = assertIntRange(raw.maxAdvanceDays, "maxAdvanceDays", { min: 1, max: 365 });
    if (v != null) out.maxAdvanceDays = v;
  }

  if (raw.cancellationPolicyHours !== undefined) {
    const v = assertIntRange(raw.cancellationPolicyHours, "cancellationPolicyHours", { min: 0, max: 168 });
    if (v != null) out.cancellationPolicyHours = v;
  }

  const booleanFields = ["requirePhone", "requireEmail", "allowNewPatients"] as const;
  for (const field of booleanFields) {
    if (raw[field] !== undefined) {
      const v = assertBoolean(raw[field], field);
      if (v !== null) out[field] = v;
    }
  }

  if (raw.confirmationMessage !== undefined) {
    const v = assertString(raw.confirmationMessage, "confirmationMessage", { trim: true, maxLength: 2000 });
    out.confirmationMessage = v ?? null;
  }

  if (raw.weeklyHours !== undefined) {
    if (raw.weeklyHours !== null && typeof raw.weeklyHours === "object") {
      out.weeklyHours = raw.weeklyHours;
    } else if (raw.weeklyHours === null) {
      out.weeklyHours = null;
    }
  }

  return out;
}

export async function updatePublicBookingConfig(request: { auth?: { uid?: string }; data?: unknown }) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }

  const data = request.data as Record<string, unknown> | undefined;
  const clinicId = requireNonEmptyString(data?.clinicId, "clinicId");

  let patch: PublicBookingPatch;
  try {
    patch = validatePatch(data?.patch);
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    throw new HttpsError("invalid-argument", e instanceof Error ? e.message : "Invalid patch.");
  }

  const uid = request.auth.uid;
  await requireClinicPermission(db, clinicId, uid, "settings.write");

  const ref = db.doc(`clinics/${clinicId}/settings/publicBooking`);
  const now = FV.serverTimestamp();

  const writeData = { ...patch, updatedAt: now, updatedByUid: uid };
  await ref.set(writeData, { merge: true });

  const changes: Record<string, unknown> = {};
  for (const key of Object.keys(patch)) {
    changes[key] = patch[key];
  }

  await writeSettingsAuditEvent(
    db,
    clinicId,
    "settings.publicBooking.updated",
    uid,
    `clinics/${clinicId}/settings/publicBooking`,
    "publicBooking",
    changes
  );
  return { ok: true };
}
