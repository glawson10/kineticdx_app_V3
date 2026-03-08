/**
 * settings.updateCommunicationSettings
 * Partial update of clinic communication settings (reminders, reply-to, etc.).
 * Write path: clinics/{clinicId}/settings/communication
 */

import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import { requireClinicPermission } from "../permissions";
import { writeSettingsAuditEvent } from "../audit/audit";
import {
  assertBoolean,
  assertString,
  pickAllowedFields,
  requireNonEmptyString,
} from "./validators";

const db = admin.firestore();
const FV = admin.firestore.FieldValue;

const ALLOWED_KEYS = new Set([
  "defaultReminderChannel",
  "defaultReplyToEmail",
  "reminderLeadHours",
  "followUpEnabled",
  "followUpDelayHours",
  "followUpMessage",
]);

const VALID_CHANNELS = new Set(["email", "sms", "both", "none"]);
const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

type CommunicationPatch = Record<string, unknown>;

function validatePatch(patch: unknown): CommunicationPatch {
  const raw = pickAllowedFields<CommunicationPatch>(patch, ALLOWED_KEYS);

  if (Object.keys(raw).length === 0) {
    throw new HttpsError("invalid-argument", "No valid fields to update.");
  }

  const out: CommunicationPatch = {};

  if (raw.defaultReminderChannel !== undefined) {
    const v = assertString(raw.defaultReminderChannel, "defaultReminderChannel", { trim: true });
    if (v != null) {
      if (!VALID_CHANNELS.has(v)) {
        throw new HttpsError(
          "invalid-argument",
          "defaultReminderChannel must be one of: email, sms, both, none."
        );
      }
      out.defaultReminderChannel = v;
    }
  }

  if (raw.defaultReplyToEmail !== undefined) {
    const v = assertString(raw.defaultReplyToEmail, "defaultReplyToEmail", { trim: true });
    if (v != null) {
      if (!EMAIL_REGEX.test(v)) {
        throw new HttpsError("invalid-argument", "defaultReplyToEmail must be a valid email address.");
      }
      out.defaultReplyToEmail = v;
    }
  }

  if (raw.reminderLeadHours !== undefined) {
    const n = typeof raw.reminderLeadHours === "number" ? raw.reminderLeadHours : parseInt(String(raw.reminderLeadHours), 10);
    if (!Number.isFinite(n) || n < 0 || n > 168) {
      throw new HttpsError("invalid-argument", "reminderLeadHours must be between 0 and 168.");
    }
    out.reminderLeadHours = n;
  }

  const booleanFields = ["followUpEnabled"] as const;
  for (const field of booleanFields) {
    if (raw[field] !== undefined) {
      const v = assertBoolean(raw[field], field);
      if (v !== null) out[field] = v;
    }
  }

  if (raw.followUpDelayHours !== undefined) {
    const n = typeof raw.followUpDelayHours === "number" ? raw.followUpDelayHours : parseInt(String(raw.followUpDelayHours), 10);
    if (!Number.isFinite(n) || n < 1 || n > 720) {
      throw new HttpsError("invalid-argument", "followUpDelayHours must be between 1 and 720.");
    }
    out.followUpDelayHours = n;
  }

  if (raw.followUpMessage !== undefined) {
    const v = assertString(raw.followUpMessage, "followUpMessage", { trim: true, maxLength: 2000 });
    out.followUpMessage = v ?? null;
  }

  return out;
}

export async function updateCommunicationSettings(request: { auth?: { uid?: string }; data?: unknown }) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }

  const data = request.data as Record<string, unknown> | undefined;
  const clinicId = requireNonEmptyString(data?.clinicId, "clinicId");

  let patch: CommunicationPatch;
  try {
    patch = validatePatch(data?.patch);
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    throw new HttpsError("invalid-argument", e instanceof Error ? e.message : "Invalid patch.");
  }

  const uid = request.auth.uid;
  await requireClinicPermission(db, clinicId, uid, "settings.write");

  const ref = db.doc(`clinics/${clinicId}/settings/communication`);
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
    "settings.communication.updated",
    uid,
    `clinics/${clinicId}/settings/communication`,
    "communication",
    changes
  );
  return { ok: true };
}
