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
import { validateQuestionnaireFlow } from "../questionnaires/questionnaireTemplates";

const db = admin.firestore();
const FV = admin.firestore.FieldValue;

const DAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;
type Interval = { start: string; end: string };
type WeeklyHours = Record<(typeof DAY_KEYS)[number], Interval[]>;
type DayMeta = { corporateOnly?: boolean; requiresCorporateCode?: boolean; locationLabel?: string };
type WeeklyHoursMeta = Record<(typeof DAY_KEYS)[number], DayMeta>;

function safeStr(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

function hmToMinutes(hm: string): number {
  const m = /^(\d{2}):(\d{2})$/.exec(hm.trim());
  if (!m) return NaN;
  const hh = Number(m[1]);
  const mm = Number(m[2]);
  if (!Number.isFinite(hh) || !Number.isFinite(mm)) return NaN;
  if (hh < 0 || hh > 23 || mm < 0 || mm > 59) return NaN;
  return hh * 60 + mm;
}

function normalizeIntervals(raw: unknown): Interval[] {
  const out: Interval[] = [];
  const list = Array.isArray(raw) ? raw : [];
  for (const it of list) {
    const item = it as Record<string, unknown> | null;
    const start = safeStr(item?.start);
    const end = safeStr(item?.end);
    if (!start || !end) continue;
    const a = hmToMinutes(start);
    const b = hmToMinutes(end);
    if (!Number.isFinite(a) || !Number.isFinite(b)) continue;
    if (b <= a) continue;
    out.push({ start, end });
  }
  out.sort((x, y) => hmToMinutes(x.start) - hmToMinutes(y.start));
  for (let i = 1; i < out.length; i++) {
    const prev = out[i - 1];
    const cur = out[i];
    if (hmToMinutes(cur.start) < hmToMinutes(prev.end)) {
      throw new HttpsError("invalid-argument", "Overlapping intervals are not allowed.");
    }
  }
  return out;
}

function normalizeWeeklyHours(raw: unknown): WeeklyHours {
  const obj = raw && typeof raw === "object" ? (raw as Record<string, unknown>) : {};
  const out = Object.fromEntries(DAY_KEYS.map((k) => [k, [] as Interval[]])) as WeeklyHours;
  for (const k of DAY_KEYS) {
    out[k] = normalizeIntervals(obj[k]);
  }
  return out;
}

function normalizeWeeklyMeta(raw: unknown): WeeklyHoursMeta {
  const base: DayMeta = { corporateOnly: false, requiresCorporateCode: false, locationLabel: "" };
  const out = Object.fromEntries(DAY_KEYS.map((k) => [k, { ...base }])) as WeeklyHoursMeta;
  const obj = raw && typeof raw === "object" ? (raw as Record<string, unknown>) : {};
  for (const k of DAY_KEYS) {
    const m = obj[k];
    if (!m || typeof m !== "object") continue;
    const day = m as Record<string, unknown>;
    out[k] = {
      corporateOnly: day.corporateOnly === true,
      requiresCorporateCode: day.requiresCorporateCode === true,
      locationLabel: safeStr(day.locationLabel),
    };
  }
  return out;
}

const ALLOWED_KEYS = new Set([
  "slotStepMinutes",
  "minNoticeMinutes",
  "maxAdvanceDays",
  "requirePhone",
  "requireEmail",
  "allowNewPatients",
  "cancellationPolicyHours",
  "weeklyHours",
  "weeklyHoursMeta",
  "confirmationMessage",
  "onlineBookingEnabled",
  "questionnaireFlow",
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

  const booleanFields = ["requirePhone", "requireEmail", "allowNewPatients", "onlineBookingEnabled"] as const;
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
      out.weeklyHours = normalizeWeeklyHours(raw.weeklyHours);
    } else if (raw.weeklyHours === null) {
      out.weeklyHours = null;
    }
  }

  if (raw.weeklyHoursMeta !== undefined && raw.weeklyHoursMeta !== null && typeof raw.weeklyHoursMeta === "object") {
    out.weeklyHoursMeta = normalizeWeeklyMeta(raw.weeklyHoursMeta);
  }

  if (raw.questionnaireFlow !== undefined) {
    out.questionnaireFlow = validateQuestionnaireFlow(raw.questionnaireFlow);
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
