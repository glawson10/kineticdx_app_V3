import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/logger";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

type Interval = { start: string; end: string };

type WeeklyHours = Record<
  "mon" | "tue" | "wed" | "thu" | "fri" | "sat" | "sun",
  Interval[]
>;

type DayMeta = {
  corporateOnly?: boolean;
  requiresCorporateCode?: boolean;
  locationLabel?: string;
};

type WeeklyHoursMeta = Record<
  "mon" | "tue" | "wed" | "thu" | "fri" | "sat" | "sun",
  DayMeta
>;

type Input = {
  clinicId: string;
  weeklyHours: Partial<Record<string, any>>;
  weeklyHoursMeta?: Partial<Record<string, any>>;
};

const DAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;

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

function normalizeIntervals(raw: any): Interval[] {
  const out: Interval[] = [];
  const list = Array.isArray(raw) ? raw : [];
  for (const it of list) {
    const start = safeStr(it?.start);
    const end = safeStr(it?.end);
    if (!start || !end) continue;

    const a = hmToMinutes(start);
    const b = hmToMinutes(end);
    if (!Number.isFinite(a) || !Number.isFinite(b)) continue;
    if (b <= a) continue;

    out.push({ start, end });
  }

  // sort + de-overlap check
  out.sort((x, y) => hmToMinutes(x.start) - hmToMinutes(y.start));

  for (let i = 1; i < out.length; i++) {
    const prev = out[i - 1];
    const cur = out[i];
    const prevEnd = hmToMinutes(prev.end);
    const curStart = hmToMinutes(cur.start);
    if (curStart < prevEnd) {
      throw new HttpsError(
        "invalid-argument",
        "Overlapping intervals are not allowed."
      );
    }
  }

  return out;
}

function normalizeWeeklyHours(raw: any): WeeklyHours {
  const out = Object.fromEntries(DAY_KEYS.map((k) => [k, []])) as any;

  for (const k of DAY_KEYS) {
    out[k] = normalizeIntervals(raw?.[k]);
  }

  return out as WeeklyHours;
}

function normalizeWeeklyMeta(raw: any): WeeklyHoursMeta {
  const base: DayMeta = {
    corporateOnly: false,
    requiresCorporateCode: false,
    locationLabel: "",
  };

  const out = Object.fromEntries(DAY_KEYS.map((k) => [k, { ...base }])) as any;

  if (!raw || typeof raw !== "object") return out;

  for (const k of DAY_KEYS) {
    const m = raw[k];
    if (!m || typeof m !== "object") continue;

    out[k] = {
      corporateOnly: m.corporateOnly === true,
      requiresCorporateCode: m.requiresCorporateCode === true,
      locationLabel: safeStr(m.locationLabel),
    };
  }

  return out as WeeklyHoursMeta;
}

/**
 * Writes to:
 * clinics/{clinicId}/public/config/publicBooking/publicBooking
 *
 * Requires: caller is authenticated
 * (and your rules or backend membership check can be added later)
 */
export const updateClinicWeeklyHoursFn = onCall(
  { region: "europe-west3", cors: true },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const data = (request.data ?? {}) as Partial<Input>;
    const clinicId = safeStr(data.clinicId);
    if (!clinicId) throw new HttpsError("invalid-argument", "clinicId is required.");

    if (!data.weeklyHours || typeof data.weeklyHours !== "object") {
      throw new HttpsError("invalid-argument", "weeklyHours is required.");
    }

    // ✅ Normalize + validate
    const weeklyHours = normalizeWeeklyHours(data.weeklyHours);

    // meta optional; if absent keep existing doc value
    const metaProvided = data.weeklyHoursMeta && typeof data.weeklyHoursMeta === "object";
    const weeklyHoursMeta = metaProvided ? normalizeWeeklyMeta(data.weeklyHoursMeta) : null;

    const ref = db.doc(`clinics/${clinicId}/public/config/publicBooking/publicBooking`);

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) {
        throw new HttpsError("failed-precondition", "Public booking not configured.");
      }

      const patch: any = {
        weeklyHours,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: uid,
      };

      if (weeklyHoursMeta) patch.weeklyHoursMeta = weeklyHoursMeta;

      tx.set(ref, patch, { merge: true });
    });

    logger.info("updateClinicWeeklyHoursFn ok", { clinicId, uid });

    return { ok: true };
  }
);
