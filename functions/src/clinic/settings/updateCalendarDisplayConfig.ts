/**
 * settings.updateCalendarDisplayConfig
 * Partial update of calendar display settings.
 * Write path: clinics/{clinicId}/settings/calendarDisplay
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
  "displayStartHour",
  "displayEndHour",
  "minutesPerBlock",
  "slotMinutes",
  "slotHeightPx",
  "timePickerIncrement",
  "showCurrentTimeIndicator",
  "hidePatientNames",
  "confirmMove",
  "showFinancialIndicators",
  "showWaitlistMatches",
  "smartOneDayView",
  "defaultView",
  "weekStartsOn",
  "showWeekends",
  "showClosedDayLabel",
  "condensedHeader",
  "clientNameSeparateLine",
]);

const VALID_DEFAULT_VIEWS = new Set(["day", "week", "month"]);
const VALID_WEEK_STARTS = new Set(["monday", "sunday"]);
const VALID_MINUTES_PER_BLOCK = new Set([5, 10, 15, 20, 30, 60]);

type DisplayConfigPatch = Record<string, unknown>;

function validatePatch(patch: unknown): DisplayConfigPatch {
  const raw = pickAllowedFields<DisplayConfigPatch>(patch, ALLOWED_KEYS);

  if (Object.keys(raw).length === 0) {
    throw new HttpsError("invalid-argument", "No valid fields to update.");
  }

  const out: DisplayConfigPatch = {};

  if (raw.displayStartHour !== undefined) {
    const v = assertIntRange(raw.displayStartHour, "displayStartHour", { min: 0, max: 23 });
    if (v != null) out.displayStartHour = v;
  }

  if (raw.displayEndHour !== undefined) {
    const v = assertIntRange(raw.displayEndHour, "displayEndHour", { min: 1, max: 24 });
    if (v != null) out.displayEndHour = v;
  }

  const startHour = (out.displayStartHour ?? raw.displayStartHour) as number | undefined;
  const endHour = (out.displayEndHour ?? raw.displayEndHour) as number | undefined;
  if (startHour !== undefined && endHour !== undefined && endHour <= startHour) {
    throw new HttpsError("invalid-argument", "displayEndHour must be greater than displayStartHour.");
  }

  const slotMinutesRaw = raw.slotMinutes !== undefined ? raw.slotMinutes : raw.minutesPerBlock;
  if (slotMinutesRaw !== undefined) {
    const v = assertIntRange(slotMinutesRaw, "slotMinutes", { min: 5, max: 60 });
    if (v != null) {
      if (!VALID_MINUTES_PER_BLOCK.has(v)) {
        throw new HttpsError("invalid-argument", "slotMinutes must be one of: 5, 10, 15, 20, 30, 60.");
      }
      out.slotMinutes = v;
    }
  }

  if (raw.slotHeightPx !== undefined) {
    const v = assertIntRange(raw.slotHeightPx, "slotHeightPx", { min: 20, max: 120 });
    if (v != null) out.slotHeightPx = v;
  }

  if (raw.timePickerIncrement !== undefined) {
    const v = assertIntRange(raw.timePickerIncrement, "timePickerIncrement", { min: 1, max: 60 });
    if (v != null) out.timePickerIncrement = v;
  }

  const booleanFields = [
    "showCurrentTimeIndicator",
    "hidePatientNames",
    "confirmMove",
    "showFinancialIndicators",
    "showWaitlistMatches",
    "smartOneDayView",
    "showWeekends",
    "showClosedDayLabel",
    "condensedHeader",
    "clientNameSeparateLine",
  ] as const;

  for (const field of booleanFields) {
    if (raw[field] !== undefined) {
      const v = assertBoolean(raw[field], field);
      if (v !== null) out[field] = v;
    }
  }

  if (raw.defaultView !== undefined) {
    const v = assertString(raw.defaultView, "defaultView", { trim: true });
    if (v != null) {
      if (!VALID_DEFAULT_VIEWS.has(v)) {
        throw new HttpsError("invalid-argument", "defaultView must be one of: day, week, month.");
      }
      out.defaultView = v;
    }
  }

  if (raw.weekStartsOn !== undefined) {
    const v = assertString(raw.weekStartsOn, "weekStartsOn", { trim: true });
    if (v != null) {
      if (!VALID_WEEK_STARTS.has(v)) {
        throw new HttpsError("invalid-argument", "weekStartsOn must be one of: monday, sunday.");
      }
      out.weekStartsOn = v;
    }
  }

  return out;
}

export async function updateCalendarDisplayConfig(request: { auth?: { uid?: string }; data?: unknown }) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }

  const data = request.data as Record<string, unknown> | undefined;
  const clinicId = requireNonEmptyString(data?.clinicId, "clinicId");

  let patch: DisplayConfigPatch;
  try {
    patch = validatePatch(data?.patch);
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    throw new HttpsError("invalid-argument", e instanceof Error ? e.message : "Invalid patch.");
  }

  const uid = request.auth.uid;
  await requireClinicPermission(db, clinicId, uid, "settings.write");

  const ref = db.doc(`clinics/${clinicId}/settings/calendarDisplay`);
  const now = FV.serverTimestamp();

  const writeData = { ...patch, updatedAt: now };
  await ref.set(writeData, { merge: true });

  const changes: Record<string, unknown> = {};
  for (const key of Object.keys(patch)) {
    changes[key] = patch[key];
  }

  await writeSettingsAuditEvent(
    db,
    clinicId,
    "settings.calendarDisplay.updated",
    uid,
    `clinics/${clinicId}/settings/calendarDisplay`,
    "calendarDisplay",
    changes
  );
  return { ok: true };
}
