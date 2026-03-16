/**
 * Location opening hours: update weeklyHours for a location.
 * Validation: location hours must be within clinic opening hours (location ⊆ clinic).
 * Write path: clinics/{clinicId}/locations/{locationId}.weeklyHours
 */

import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import { requireClinicPermission } from "../permissions";
import { writeSettingsAuditEvent } from "../audit/audit";
import { requireNonEmptyString } from "./validators";

const db = admin.firestore();
const FV = admin.firestore.FieldValue;

const DAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;
type DayKey = (typeof DAY_KEYS)[number];

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
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

function takeIntervals(list: unknown): Array<{ start: string; end: string }> {
  const out: Array<{ start: string; end: string }> = [];
  if (!Array.isArray(list)) return out;
  for (const it of list) {
    if (!it || typeof it !== "object" || Array.isArray(it)) continue;
    const start = safeStr((it as any).start);
    const end = safeStr((it as any).end);
    if (!start || !end) continue;
    const a = hmToMinutes(start);
    const b = hmToMinutes(end);
    if (!Number.isFinite(a) || !Number.isFinite(b) || b <= a) continue;
    out.push({ start, end });
  }
  return out;
}

function normalizeWeeklyHours(raw: unknown): Record<string, Array<{ start: string; end: string }>> {
  const out: Record<string, Array<{ start: string; end: string }>> = {};
  for (const day of DAY_KEYS) {
    out[day] = [];
  }
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return out;
  const obj = raw as Record<string, unknown>;
  for (const day of DAY_KEYS) {
    const v = obj[day];
    out[day] = Array.isArray(v) ? takeIntervals(v) : [];
  }
  return out;
}

/** Check that every location interval on each day is contained in some clinic interval that day. Exported for tests. */
export function locationHoursWithinClinic(
  clinicWeekly: Record<string, Array<{ start: string; end: string }>>,
  locationWeekly: Record<string, Array<{ start: string; end: string }>>
): { ok: boolean; message?: string } {
  for (const day of DAY_KEYS) {
    const locIntervals = locationWeekly[day] ?? [];
    const clinicIntervals = clinicWeekly[day] ?? [];
    if (locIntervals.length === 0) continue;
    if (clinicIntervals.length === 0) {
      return { ok: false, message: `Location has hours on ${day} but clinic is closed that day. Location hours must fall within clinic opening hours.` };
    }
    const clinicMins = clinicIntervals.map((i) => ({ a: hmToMinutes(i.start), b: hmToMinutes(i.end) }));
    for (const loc of locIntervals) {
      const la = hmToMinutes(loc.start);
      const lb = hmToMinutes(loc.end);
      const contained = clinicMins.some((c) => la >= c.a && lb <= c.b);
      if (!contained) {
        return { ok: false, message: `Location hours on ${day} (${loc.start}–${loc.end}) extend outside clinic opening hours. Location hours must fall within clinic opening hours.` };
      }
    }
  }
  return { ok: true };
}

export async function updateLocationWeeklyHours(request: { auth?: { uid?: string }; data?: unknown }) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }

  const data = request.data as Record<string, unknown> | undefined;
  const clinicId = requireNonEmptyString(data?.clinicId, "clinicId");
  const locationId = requireNonEmptyString(data?.locationId, "locationId");
  const weeklyHoursRaw = data?.weeklyHours;

  const locationWeekly = normalizeWeeklyHours(weeklyHoursRaw);
  const hasAny = DAY_KEYS.some((d) => (locationWeekly[d]?.length ?? 0) > 0);

  const uid = request.auth.uid;
  await requireClinicPermission(db, clinicId, uid, "settings.write");

  const [settingsSnap, locSnap] = await Promise.all([
    db.doc(`clinics/${clinicId}/settings/publicBooking`).get(),
    db.doc(`clinics/${clinicId}/locations/${locationId}`).get(),
  ]);

  if (!locSnap.exists) {
    throw new HttpsError("not-found", "Location not found.");
  }

  const settingsData = settingsSnap.exists ? (settingsSnap.data() ?? {}) : {};
  const clinicWeekly = normalizeWeeklyHours(settingsData.weeklyHours);

  if (hasAny) {
    const check = locationHoursWithinClinic(clinicWeekly, locationWeekly);
    if (!check.ok) {
      throw new HttpsError("invalid-argument", check.message ?? "Location hours must fall within clinic opening hours.");
    }
  }

  const updateData: Record<string, unknown> = {
    updatedAt: FV.serverTimestamp(),
    weeklyHours: locationWeekly,
  };

  await db.doc(`clinics/${clinicId}/locations/${locationId}`).update(updateData);

  await writeSettingsAuditEvent(
    db,
    clinicId,
    "settings.location.openingHours.updated",
    uid,
    `clinics/${clinicId}/locations`,
    locationId,
    { weeklyHours: locationWeekly }
  );

  return { ok: true, locationId };
}
