// functions/src/public/listPublicSlots.ts
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/logger";
import { enforceRateLimit } from "./rateLimit";
import { requireClinicPermission } from "../clinic/permissions";

// Commit 17: Availability reads only from public/config/publicBooking/config (no writePublicBookingMirror / private settings).
// Commit 51: In-memory slot cache (TTL 45s, key: clinicId|locationId|practitionerId|appointmentTypeId|date in clinic TZ).

import { normalizeBookingRulesFromConfigDoc } from "./bookingConfig";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const SLOT_CACHE_TTL_MS = 45 * 1000;
const SLOT_CACHE_MAX_KEYS = 500;
const slotCache = new Map<
  string,
  { result: Record<string, unknown>; cachedAt: number }
>();

function evictSlotCacheIfNeeded(): void {
  if (slotCache.size <= SLOT_CACHE_MAX_KEYS) return;
  const entries = Array.from(slotCache.entries()).sort(
    (a, b) => a[1].cachedAt - b[1].cachedAt
  );
  const toDelete = entries.length - SLOT_CACHE_MAX_KEYS;
  for (let i = 0; i < toDelete; i++) {
    slotCache.delete(entries[i][0]);
  }
}

/** Commit 51: Invalidate slot cache for a given clinic/practitioner/date after successful booking. */
export function invalidateSlotCacheForBooking(
  clinicId: string,
  practitionerId: string,
  dateYmd: string
): void {
  const toDelete: string[] = [];
  for (const key of slotCache.keys()) {
    const parts = key.split("|");
    if (parts[0] === clinicId && parts[2] === practitionerId && parts[4] === dateYmd) {
      toDelete.push(key);
    }
  }
  for (const k of toDelete) slotCache.delete(k);
  if (toDelete.length > 0) {
    logger.info("Slot cache invalidated after booking", {
      clinicId,
      practitionerId,
      dateYmd,
      keysRemoved: toDelete.length,
    });
  }
}

type Input = {
  clinicId: string;
  serviceId?: string;
  practitionerId?: string;
  /** Location-first booking: filter availability by location. Optional. */
  locationId?: string;
  /** Appointment type filter. Optional. */
  appointmentTypeId?: string;
  rangeStartMs?: number;
  rangeEndMs?: number;

  corpSlug?: string;
  corpCode?: string;

  fromUtc?: string;
  toUtc?: string;
  tz?: string;
  purpose?: string; // "openingWindows"
};

type CorporateMode = "LINK_ONLY" | "CODE_UNLOCK";

type PublicPractitioner = {
  id: string; // uid
  displayName?: string;
  serviceIdsAllowed?: string[];
  sortOrder?: number;
  allowedLocationIds?: string[];
  title?: string;
  photoUrl?: string;
  bio?: string;
};

type PublicSettings = {
  timezone?: string;
  slotStepMinutes?: number;
  minNoticeMinutes?: number;
  maxAdvanceDays?: number;
  onlineBookingEnabled?: boolean;

  // Clinic hours (public booking settings)
  weeklyHours?: Record<string, Array<{ start: string; end: string }>>;
  /** Per-location opening hours from mirror. Key = locationId. */
  locationOpeningHours?: Record<string, Record<string, Array<{ start: string; end: string }>>>;
  openingHours?: any;

  corporatePrograms?: Array<{
    corpSlug: string;
    displayName?: string;
    mode?: CorporateMode;
    days?: string[];
    serviceIdsAllowed?: string[];
    practitionerIdsAllowed?: string[];
  }>;

  practitioners?: PublicPractitioner[];

  publicBooking?: {
    practitioners?: Array<any>;
    [k: string]: any;
  };

  [k: string]: any;
};

function safeStr(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

function parseMillis(label: string, ms: unknown): Date {
  if (typeof ms !== "number" || !Number.isFinite(ms) || ms <= 0) {
    throw new HttpsError("invalid-argument", `Invalid ${label}Ms.`);
  }
  const d = new Date(ms);
  if (Number.isNaN(d.getTime())) {
    throw new HttpsError("invalid-argument", `Invalid ${label}Ms.`);
  }
  return d;
}

function parseIso(label: string, iso: string): Date {
  const t = Date.parse(iso);
  if (!Number.isFinite(t)) {
    throw new HttpsError(
      "invalid-argument",
      `Invalid ${label} (expected ISO date string).`
    );
  }
  const d = new Date(t);
  if (Number.isNaN(d.getTime()))
    throw new HttpsError("invalid-argument", `Invalid ${label}.`);
  return d;
}

function getTz(settings: PublicSettings, overrideTz?: string): string {
  return safeStr(overrideTz) || safeStr(settings.timezone) || "Europe/Prague";
}

function ymdFromDateInTz(d: Date, tz: string): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: tz,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(d);

  const y = parts.find((p) => p.type === "year")?.value ?? "";
  const m = parts.find((p) => p.type === "month")?.value ?? "";
  const day = parts.find((p) => p.type === "day")?.value ?? "";
  return `${y}-${m}-${day}`;
}

function dayKeyFromDateInTz(
  d: Date,
  tz: string
): "mon" | "tue" | "wed" | "thu" | "fri" | "sat" | "sun" {
  const weekday = new Intl.DateTimeFormat("en-US", {
    weekday: "short",
    timeZone: tz,
  }).format(d);

  const w = weekday.toLowerCase();
  if (w.startsWith("mon")) return "mon";
  if (w.startsWith("tue")) return "tue";
  if (w.startsWith("wed")) return "wed";
  if (w.startsWith("thu")) return "thu";
  if (w.startsWith("fri")) return "fri";
  if (w.startsWith("sat")) return "sat";
  return "sun";
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

function findCorporate(settings: PublicSettings, corpSlug?: string) {
  const slug = safeStr(corpSlug).toLowerCase();
  if (!slug) return null;
  const list = Array.isArray(settings.corporatePrograms)
    ? settings.corporatePrograms
    : [];
  return list.find((p) => safeStr(p?.corpSlug).toLowerCase() === slug) ?? null;
}

function extractAllowedPractitionerIds(settings: PublicSettings): string[] {
  const raw =
    (Array.isArray(settings.practitioners) ? settings.practitioners : null) ??
    (Array.isArray(settings.publicBooking?.practitioners)
      ? settings.publicBooking?.practitioners
      : null) ??
    [];

  const ids: string[] = [];

  for (const item of raw as any[]) {
    if (item && typeof item === "object") {
      const id = safeStr((item as any).id);
      if (id) ids.push(id);
      continue;
    }

    if (typeof item === "string") {
      const m = item.match(/id:\s*"?([^"]+)"?/i);
      if (m?.[1]) ids.push(m[1].trim());
    }
  }

  return Array.from(new Set(ids));
}

async function loadClosures(
  clinicId: string,
  rangeStart: admin.firestore.Timestamp,
  rangeEnd: admin.firestore.Timestamp
) {
  const snap = await db
    .collection(`clinics/${clinicId}/closures`)
    .where("active", "==", true)
    .where("fromAt", "<", rangeEnd)
    .get();

  const out: Array<{ fromMs: number; toMs: number }> = [];
  for (const doc of snap.docs) {
    const d = doc.data() as any;
    const fromAt = d?.fromAt as admin.firestore.Timestamp | undefined;
    const toAt = d?.toAt as admin.firestore.Timestamp | undefined;
    if (!fromAt || !toAt) continue;

    const fromMs = fromAt.toMillis();
    const toMs = toAt.toMillis();

    if (rangeStart.toMillis() < toMs && rangeEnd.toMillis() > fromMs) {
      out.push({ fromMs, toMs });
    }
  }
  return out;
}

async function loadClinicWideBusyBlocks(
  clinicId: string,
  rangeStart: admin.firestore.Timestamp,
  rangeEnd: admin.firestore.Timestamp
) {
  const col = db.collection(`clinics/${clinicId}/public/availability/blocks`);
  const snap = await col.where("startUtc", "<", rangeEnd).get();

  const out: Array<{ startMs: number; endMs: number }> = [];

  for (const doc of snap.docs) {
    const d = doc.data() as any;

    const s = d?.startUtc as admin.firestore.Timestamp | undefined;
    const e = d?.endUtc as admin.firestore.Timestamp | undefined;
    const status = safeStr(d?.status);

    if (!s || !e) continue;
    if (status === "cancelled") continue;

    const scope = safeStr(d?.scope);
    const kind = safeStr(d?.kind).toLowerCase();
    const pid = safeStr(d?.practitionerId);
    const cid = safeStr(d?.clinicianId);

    const isClinicScoped = scope === "clinic";
    const isLegacyClinicWideAdmin = !scope && kind === "admin" && !pid && !cid;

    if (!isClinicScoped && !isLegacyClinicWideAdmin) continue;

    const sMs = s.toMillis();
    const eMs = e.toMillis();

    if (rangeStart.toMillis() < eMs && rangeEnd.toMillis() > sMs) {
      out.push({ startMs: sMs, endMs: eMs });
    }
  }

  return out;
}

async function loadBusyBlocks(
  clinicId: string,
  practitionerId: string | undefined,
  rangeStart: admin.firestore.Timestamp,
  rangeEnd: admin.firestore.Timestamp
) {
  const pid = safeStr(practitionerId);
  const col = db.collection(`clinics/${clinicId}/public/availability/blocks`);
  const snap = await col.where("startUtc", "<", rangeEnd).get();

  const out: Array<{ startMs: number; endMs: number }> = [];

  for (const doc of snap.docs) {
    const d = doc.data() as any;

    const s = d?.startUtc as admin.firestore.Timestamp | undefined;
    const e = d?.endUtc as admin.firestore.Timestamp | undefined;
    const status = safeStr(d?.status);

    const scope = safeStr(d?.scope);
    const kind = safeStr(d?.kind).toLowerCase();

    const docPid = safeStr(d?.practitionerId);
    const docCid = safeStr(d?.clinicianId);

    if (!s || !e) continue;
    if (status === "cancelled") continue;

    const sMs = s.toMillis();
    const eMs = e.toMillis();
    if (!(rangeStart.toMillis() < eMs && rangeEnd.toMillis() > sMs)) continue;

    let applies = false;

    if (scope === "clinic") {
      applies = true;
    } else if (scope === "practitioner") {
      if (!pid) applies = false;
      else applies = docPid === pid || docCid === pid;
    } else if (!scope) {
      if (kind === "admin" && !docPid && !docCid) {
        applies = true;
      } else {
        if (!pid) applies = false;
        else applies = docPid === pid || docCid === pid;
      }
    } else {
      applies = false;
    }

    if (!applies) continue;

    out.push({ startMs: sMs, endMs: eMs });
  }

  return out;
}

async function loadAppointmentsAsBlocks(
  clinicId: string,
  practitionerId: string | undefined,
  rangeStart: admin.firestore.Timestamp,
  rangeEnd: admin.firestore.Timestamp
) {
  const pid = safeStr(practitionerId);
  if (!pid) return [];

  const col = db.collection(`clinics/${clinicId}/appointments`);
  const snap = await col.where("startAt", "<", rangeEnd).get();

  const out: Array<{ startMs: number; endMs: number }> = [];

  for (const doc of snap.docs) {
    const d = doc.data() as any;

    const docPid = safeStr(d?.practitionerId);
    if (docPid !== pid) continue;

    const status = safeStr(d?.status).toLowerCase();
    if (status === "cancelled") continue;

    const sTs =
      (d?.startAt as admin.firestore.Timestamp | undefined) ??
      (d?.start as admin.firestore.Timestamp | undefined);

    const eTs =
      (d?.endAt as admin.firestore.Timestamp | undefined) ??
      (d?.end as admin.firestore.Timestamp | undefined);

    if (!sTs || !eTs) continue;

    const sMs = sTs.toMillis();
    const eMs = eTs.toMillis();
    if (!(rangeStart.toMillis() < eMs && rangeEnd.toMillis() > sMs)) continue;

    out.push({ startMs: sMs, endMs: eMs });
  }

  return out;
}

type OverrideRanges = {
  unavailable: Array<{ startMs: number; endMs: number }>;
  available: Array<{ startMs: number; endMs: number }>;
};

/**
 * Load practitioner overrides that overlap [rangeStart, rangeEnd].
 * When locationId is set, only include overrides whose locationId is null (global) or matches.
 * Used so public slots respect "unavailable" (time off) and "extra available" (one-off hours).
 */
async function loadPractitionerOverrides(
  clinicId: string,
  practitionerId: string,
  rangeStart: admin.firestore.Timestamp,
  rangeEnd: admin.firestore.Timestamp,
  locationId?: string
): Promise<OverrideRanges> {
  const pid = safeStr(practitionerId);
  if (!pid) return { unavailable: [], available: [] };

  const col = db
    .collection("clinics")
    .doc(clinicId)
    .collection("practitioners")
    .doc(pid)
    .collection("overrides");

  const snap = await col.where("toAt", ">", rangeStart).get();
  const rangeStartMs = rangeStart.toMillis();
  const rangeEndMs = rangeEnd.toMillis();
  const locId = safeStr(locationId);

  const unavailable: Array<{ startMs: number; endMs: number }> = [];
  const available: Array<{ startMs: number; endMs: number }> = [];

  for (const doc of snap.docs) {
    const d = doc.data() as any;
    const fromAt = d?.fromAt as admin.firestore.Timestamp | undefined;
    const toAt = d?.toAt as admin.firestore.Timestamp | undefined;
    if (!fromAt || !toAt) continue;
    const fromMs = fromAt.toMillis();
    const toMs = toAt.toMillis();
    if (fromMs >= rangeEndMs) continue;

    const overrideLocId = d?.locationId == null || d?.locationId === "" ? null : safeStr(d.locationId);
    if (locId.length > 0 && overrideLocId != null && overrideLocId !== locId) continue;

    const isAvailable = d?.isAvailable === true;
    const block = { startMs: fromMs, endMs: toMs };
    if (isAvailable) available.push(block);
    else unavailable.push(block);
  }

  return { unavailable, available };
}

function slotContainedInRanges(
  startMs: number,
  endMs: number,
  ranges: Array<{ startMs: number; endMs: number }>
): boolean {
  return ranges.some((r) => startMs >= r.startMs && endMs <= r.endMs);
}

function overlapsAny(
  startMs: number,
  endMs: number,
  blocks: Array<{ startMs: number; endMs: number }>
) {
  return blocks.some((b) => startMs < b.endMs && endMs > b.startMs);
}

function normalizeWeeklyHours(
  settings: PublicSettings
): Record<string, Array<{ start: string; end: string }>> {
  const keys = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;

  const out: Record<string, Array<{ start: string; end: string }>> =
    Object.fromEntries(keys.map((k) => [k, []])) as any;

  const takeIntervals = (k: string, list: any[]) => {
    const cleaned: Array<{ start: string; end: string }> = [];
    for (const it of list) {
      const start = safeStr(it?.start);
      const end = safeStr(it?.end);
      if (!start || !end) continue;

      const a = hmToMinutes(start);
      const b = hmToMinutes(end);
      if (!Number.isFinite(a) || !Number.isFinite(b)) continue;
      if (b <= a) continue;

      cleaned.push({ start, end });
    }
    out[k] = cleaned;
  };

  // Prefer canonical weeklyHours
  if (settings.weeklyHours && typeof settings.weeklyHours === "object") {
    for (const k of keys) {
      const v = (settings.weeklyHours as any)[k];
      if (Array.isArray(v)) takeIntervals(k, v);
    }
    return out;
  }

  // Fallback: legacy openingHours
  const oh: any = (settings as any).openingHours;
  if (oh && typeof oh === "object") {
    let matchedKeyMap = false;
    for (const k of keys) {
      const v = oh[k];
      if (Array.isArray(v)) {
        matchedKeyMap = true;
        takeIntervals(k, v);
      }
    }
    if (matchedKeyMap) return out;

    const daysArr = oh.days;
    if (Array.isArray(daysArr)) {
      for (const row of daysArr) {
        const rawDay =
          safeStr(row?.day) ||
          safeStr(row?.dayKey) ||
          safeStr(row?.weekday) ||
          safeStr(row?.id);

        const dk = rawDay.toLowerCase().slice(0, 3);
        if (!keys.includes(dk as any)) continue;

        const closed =
          row?.closed === true ||
          row?.isClosed === true ||
          row?.open === false ||
          row?.isOpen === false;

        if (closed) {
          out[dk] = [];
          continue;
        }

        const intervals =
          (Array.isArray(row?.intervals) && row.intervals) ||
          (Array.isArray(row?.windows) && row.windows) ||
          (Array.isArray(row?.ranges) && row.ranges) ||
          (safeStr(row?.start) && safeStr(row?.end)
            ? [{ start: row.start, end: row.end }]
            : []) ||
          [];

        if (Array.isArray(intervals)) takeIntervals(dk, intervals);
      }
      return out;
    }
  }

  return out;
}

async function loadStaffWeeklyAvailability(params: {
  clinicId: string;
  practitionerId: string;
}): Promise<{
  timezone?: string;
  weekly: Record<string, Array<{ start: string; end: string }>>;
} | null> {
  const clinicId = safeStr(params.clinicId);
  const pid = safeStr(params.practitionerId);
  if (!clinicId || !pid) return null;

  const ref = db.doc(
    `clinics/${clinicId}/staffProfiles/${pid}/availability/default`
  );
  const snap = await ref.get();
  if (!snap.exists) return null;

  const data = snap.data() as any;
  const weekly = data?.weekly;
  if (!weekly || typeof weekly !== "object") return null;

  const keys = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;

  const out: Record<string, Array<{ start: string; end: string }>> =
    Object.fromEntries(keys.map((k) => [k, []])) as any;

  for (const k of keys) {
    const v = weekly[k];
    if (!Array.isArray(v)) continue;

    const cleaned: Array<{ start: string; end: string }> = [];
    for (const it of v) {
      const start = safeStr(it?.start);
      const end = safeStr(it?.end);
      if (!start || !end) continue;

      const a = hmToMinutes(start);
      const b = hmToMinutes(end);
      if (!Number.isFinite(a) || !Number.isFinite(b)) continue;
      if (b <= a) continue;

      cleaned.push({ start, end });
    }

    cleaned.sort((x, y) => hmToMinutes(x.start) - hmToMinutes(y.start));
    out[k] = cleaned;
  }

  const timezone = safeStr(data?.timezone) || undefined;
  return { timezone, weekly: out };
}

const AVAIL_DAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;
/** dayOfWeek 1 = Monday → mon, 7 = Sunday → sun (canonical availability blocks). */
const DOW_TO_DAY: Record<number, (typeof AVAIL_DAY_KEYS)[number]> = {
  1: "mon",
  2: "tue",
  3: "wed",
  4: "thu",
  5: "fri",
  6: "sat",
  7: "sun",
};

/**
 * Load practitioner availability from practitioners/{id}/availability filtered by locationId.
 * Used when the request is location-scoped so slots/calendar only show availability for that location.
 * See docs/AVAILABILITY_SOURCES.md.
 */
async function loadStaffWeeklyAvailabilityForLocation(params: {
  clinicId: string;
  practitionerId: string;
  locationId: string;
}): Promise<{
  timezone?: string;
  weekly: Record<string, Array<{ start: string; end: string }>>;
} | null> {
  const clinicId = safeStr(params.clinicId);
  const pid = safeStr(params.practitionerId);
  const locationId = safeStr(params.locationId);
  if (!clinicId || !pid || !locationId) return null;

  const availCol = db
    .collection("clinics")
    .doc(clinicId)
    .collection("practitioners")
    .doc(pid)
    .collection("availability");

  const snap = await availCol.get();
  const perDay: Record<string, IntervalMin[]> = Object.fromEntries(
    AVAIL_DAY_KEYS.map((k) => [k, []])
  ) as Record<string, IntervalMin[]>;

  for (const doc of snap.docs) {
    const data = doc.data();
    if (data?.active === false) continue;
    if (safeStr(data?.locationId) !== locationId) continue;

    const blocks = Array.isArray(data?.blocks) ? data.blocks : [];
    for (const b of blocks) {
      if (!b || typeof b !== "object") continue;
      const bookableOnline = (b as any).bookableOnline !== false;
      if (!bookableOnline) continue;

      const dayOfWeek = Number((b as any).dayOfWeek);
      const dayKey = DOW_TO_DAY[dayOfWeek];
      if (!dayKey) continue;

      const startM = hmToMinutes(safeStr((b as any).startTime));
      const endM = hmToMinutes(safeStr((b as any).endTime));
      if (startM == null || endM == null || endM <= startM) continue;

      perDay[dayKey].push({ a: startM, b: endM });
    }
  }

  const weekly: Record<string, Array<{ start: string; end: string }>> =
    Object.fromEntries(
      AVAIL_DAY_KEYS.map((k) => [
        k,
        mergeIntervals(perDay[k]).map(({ a, b }) => ({
          start: minutesToHHmm(a),
          end: minutesToHHmm(b),
        })),
      ])
    );

  const hasAny = Object.values(weekly).some((arr) => arr.length > 0);
  if (!hasAny) return null;

  return { timezone: undefined, weekly };
}

function minutesToHHmm(m: number): string {
  const hh = Math.floor(m / 60);
  const mm = m % 60;
  return `${String(hh).padStart(2, "0")}:${String(mm).padStart(2, "0")}`;
}

type IntervalMin = { a: number; b: number };

function mergeIntervals(list: IntervalMin[]): IntervalMin[] {
  const sorted = [...list].sort((x, y) => x.a - y.a);
  const out: IntervalMin[] = [];
  let cur: IntervalMin | null = null;

  for (const it of sorted) {
    if (!cur) {
      cur = { a: it.a, b: it.b };
      continue;
    }
    if (it.a <= cur.b) {
      cur.b = Math.max(cur.b, it.b);
    } else {
      out.push(cur);
      cur = { a: it.a, b: it.b };
    }
  }
  if (cur) out.push(cur);
  return out;
}

function normalizeToMinutes(
  weekly: Record<string, Array<{ start: string; end: string }>>
): Record<string, IntervalMin[]> {
  const keys = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;
  const out: Record<string, IntervalMin[]> = Object.fromEntries(
    keys.map((k) => [k, []])
  ) as any;

  for (const k of keys) {
    const intervals = Array.isArray(weekly[k]) ? weekly[k] : [];
    const mins: IntervalMin[] = [];
    for (const it of intervals) {
      const a = hmToMinutes(safeStr(it.start));
      const b = hmToMinutes(safeStr(it.end));
      if (!Number.isFinite(a) || !Number.isFinite(b)) continue;
      if (b <= a) continue;
      mins.push({ a, b });
    }
    out[k] = mergeIntervals(mins);
  }

  return out;
}

function minsToWeekly(
  weeklyMins: Record<string, IntervalMin[]>
): Record<string, Array<{ start: string; end: string }>> {
  const keys = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;
  const out: Record<string, Array<{ start: string; end: string }>> =
    Object.fromEntries(keys.map((k) => [k, []])) as any;

  const fmt = (m: number) => {
    const hh = Math.floor(m / 60);
    const mm = m % 60;
    return `${String(hh).padStart(2, "0")}:${String(mm).padStart(2, "0")}`;
  };

  for (const k of keys) {
    out[k] = (weeklyMins[k] || []).map((it) => ({
      start: fmt(it.a),
      end: fmt(it.b),
    }));
  }

  return out;
}

/** Exported for unit tests (multi-location slot resolution). */
export function intersectWeeklyHours(
  clinicWeekly: Record<string, Array<{ start: string; end: string }>>,
  staffWeekly: Record<string, Array<{ start: string; end: string }>>
): Record<string, Array<{ start: string; end: string }>> {
  const keys = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;

  const a = normalizeToMinutes(clinicWeekly);
  const b = normalizeToMinutes(staffWeekly);

  const outMins: Record<string, IntervalMin[]> = Object.fromEntries(
    keys.map((k) => [k, []])
  ) as any;

  for (const k of keys) {
    const A = a[k] || [];
    const B = b[k] || [];
    const out: IntervalMin[] = [];

    let i = 0;
    let j = 0;

    while (i < A.length && j < B.length) {
      const x = A[i];
      const y = B[j];

      const start = Math.max(x.a, y.a);
      const end = Math.min(x.b, y.b);

      if (end > start) out.push({ a: start, b: end });

      if (x.b < y.b) i++;
      else j++;
    }

    outMins[k] = mergeIntervals(out);
  }

  return minsToWeekly(outMins);
}

/**
 * Compute effective weekly hours for slot resolution: clinic ∩ (location if present) ∩ (practitioner if present).
 * Exported for unit tests (multi-location slot resolution).
 */
export function computeEffectiveWeeklyHours(
  clinicWeekly: Record<string, Array<{ start: string; end: string }>>,
  locationWeekly: Record<string, Array<{ start: string; end: string }>> | null,
  practitionerWeekly: Record<string, Array<{ start: string; end: string }>> | null
): Record<string, Array<{ start: string; end: string }>> {
  let afterClinic = clinicWeekly;
  if (locationWeekly && Object.values(locationWeekly).some((arr) => Array.isArray(arr) && arr.length > 0)) {
    afterClinic = intersectWeeklyHours(clinicWeekly, locationWeekly);
  }
  if (practitionerWeekly && Object.values(practitionerWeekly).some((arr) => Array.isArray(arr) && arr.length > 0)) {
    return intersectWeeklyHours(afterClinic, practitionerWeekly);
  }
  return afterClinic;
}

type DayFlag = {
  corporateOnly: boolean;
  mode: CorporateMode | null;
  corpSlug?: string;
  displayName?: string;
};

// Commit 17: Availability engine reads only from public mirror (config doc). No private settings reads.
const CONFIG_DOC_PATH = (clinicId: string) =>
  `clinics/${clinicId}/public/config/publicBooking/config`;
const FULL_MIRROR_PATH = (clinicId: string) =>
  `clinics/${clinicId}/public/config/publicBooking/publicBooking`;

const DAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;

function defaultWeeklyHours(): Record<string, Array<{ start: string; end: string }>> {
  return Object.fromEntries(DAY_KEYS.map((k) => [k, []])) as Record<
    string,
    Array<{ start: string; end: string }>
  >;
}

/** Normalize one location's weekly hours from mirror (same shape as clinic weeklyHours). */
function normalizeLocationWeeklyHoursFromMirror(raw: unknown): Record<string, Array<{ start: string; end: string }>> {
  const out = defaultWeeklyHours();
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return out;
  const obj = raw as Record<string, unknown>;
  for (const day of DAY_KEYS) {
    const v = obj[day];
    if (!Array.isArray(v)) continue;
    out[day] = v
      .filter((it: any) => it && typeof it === "object" && safeStr(it.start) && safeStr(it.end))
      .map((it: any) => ({ start: safeStr(it.start), end: safeStr(it.end) }));
  }
  return out;
}

/** Load booking rules + weeklyHours + locationOpeningHours from mirror config doc only. Uses defaults if missing. */
async function loadPublicConfigFromMirror(clinicId: string): Promise<{
  timezone: string;
  slotStepMinutes: number;
  minNoticeMinutes: number;
  maxAdvanceDays: number;
  weeklyHours: Record<string, Array<{ start: string; end: string }>>;
  locationOpeningHours: Record<string, Record<string, Array<{ start: string; end: string }>>>;
  onlineBookingEnabled: boolean;
}> {
  const configRef = db.doc(CONFIG_DOC_PATH(clinicId));
  const configSnap = await configRef.get();

  if (!configSnap.exists || !configSnap.data()) {
    logger.warn("[projection/publicBooking] public booking config missing; using defaults", {
      clinicId,
    });
    return {
      timezone: "UTC",
      slotStepMinutes: 15,
      minNoticeMinutes: 0,
      maxAdvanceDays: 90,
      weeklyHours: defaultWeeklyHours(),
      locationOpeningHours: {},
      onlineBookingEnabled: true,
    };
  }

  const d = configSnap.data() as any;
  const rules = normalizeBookingRulesFromConfigDoc(d);
  const rulesRaw = d?.bookingRules && typeof d.bookingRules === "object" ? d.bookingRules : {};
  const wh = d?.weeklyHours && typeof d.weeklyHours === "object" ? d.weeklyHours : {};
  const locHoursRaw = d?.locationOpeningHours && typeof d.locationOpeningHours === "object" ? d.locationOpeningHours : {};

  const timezone = rules.timezone || "UTC";
  const slotStepMinutes =
    typeof rulesRaw.slotStepMinutes === "number" && [5, 10, 15, 20, 30].includes(rulesRaw.slotStepMinutes)
      ? rulesRaw.slotStepMinutes
      : 15;
  const minNoticeMinutes = rules.minNoticeMinutes;
  const maxAdvanceDays = rules.maxAdvanceDays;

  const weeklyHours = defaultWeeklyHours();
  for (const day of DAY_KEYS) {
    const v = wh[day];
    if (Array.isArray(v)) {
      weeklyHours[day] = v
        .filter((it: any) => it && typeof it === "object" && safeStr(it.start) && safeStr(it.end))
        .map((it: any) => ({ start: safeStr(it.start), end: safeStr(it.end) }));
    }
  }

  const locationOpeningHours: Record<string, Record<string, Array<{ start: string; end: string }>>> = {};
  for (const [locId, raw] of Object.entries(locHoursRaw)) {
    if (typeof locId !== "string" || !locId.trim()) continue;
    const normalized = normalizeLocationWeeklyHoursFromMirror(raw);
    const hasAny = DAY_KEYS.some((day) => (normalized[day]?.length ?? 0) > 0);
    if (hasAny) locationOpeningHours[locId.trim()] = normalized;
  }

  const onlineBookingEnabled = rulesRaw.onlineBookingEnabled !== false;

  return {
    timezone,
    slotStepMinutes,
    minNoticeMinutes,
    maxAdvanceDays,
    weeklyHours,
    locationOpeningHours,
    onlineBookingEnabled,
  };
}

/** Load practitioners + corporatePrograms from full mirror (for allowlist). Does not read private settings. */
async function loadFullMirrorExtras(clinicId: string): Promise<{
  practitioners: PublicPractitioner[];
  corporatePrograms: PublicSettings["corporatePrograms"];
}> {
  const fullRef = db.doc(FULL_MIRROR_PATH(clinicId));
  const snap = await fullRef.get();
  if (!snap.exists || !snap.data()) return { practitioners: [], corporatePrograms: undefined };

  const d = snap.data() as any;
  const raw =
    Array.isArray(d?.practitioners) ? d.practitioners : Array.isArray(d?.publicBooking?.practitioners)
      ? d.publicBooking.practitioners
      : [];
  const practitioners: PublicPractitioner[] = [];
  for (const item of raw) {
    if (item && typeof item === "object") {
      const id = safeStr((item as any).id);
      if (id) {
        const allowedLocationIds = Array.isArray((item as any).allowedLocationIds)
          ? (item as any).allowedLocationIds.filter((x: any) => typeof x === "string" && x.trim())
          : undefined;
        const entry: PublicPractitioner = {
          id,
          displayName: safeStr((item as any).displayName),
          serviceIdsAllowed: (item as any).serviceIdsAllowed,
          sortOrder: (item as any).sortOrder,
          allowedLocationIds,
        };
        const title = safeStr((item as any).title);
        if (title) entry.title = title;
        const photoUrl = safeStr((item as any).photoUrl);
        if (photoUrl) entry.photoUrl = photoUrl;
        const bio = safeStr((item as any).bio);
        if (bio) entry.bio = bio;
        practitioners.push(entry);
      }
    }
  }
  const corporatePrograms = Array.isArray(d?.corporatePrograms) ? d.corporatePrograms : undefined;
  return { practitioners, corporatePrograms };
}

/** Commit 17: Load settings for availability from mirror config only. No private settings fallback. */
async function loadPublicSettingsFromMirror(clinicId: string): Promise<PublicSettings> {
  const [config, extras] = await Promise.all([
    loadPublicConfigFromMirror(clinicId),
    loadFullMirrorExtras(clinicId),
  ]);

  return {
    timezone: config.timezone,
    slotStepMinutes: config.slotStepMinutes,
    minNoticeMinutes: config.minNoticeMinutes,
    maxAdvanceDays: config.maxAdvanceDays,
    weeklyHours: config.weeklyHours,
    locationOpeningHours: config.locationOpeningHours ?? {},
    onlineBookingEnabled: config.onlineBookingEnabled,
    practitioners: extras.practitioners,
    corporatePrograms: extras.corporatePrograms,
  } as PublicSettings;
}

export const listPublicSlotsFn = onCall(
  { region: "europe-west3", cors: true },
  async (request) => {
    try {
      const data = (request.data ?? {}) as Partial<Input>;

      const clinicId = safeStr(data.clinicId);
      const serviceId = safeStr(data.serviceId);
      const practitionerId = safeStr(data.practitionerId);
      const locationId = safeStr(data.locationId) || undefined;
      const appointmentTypeId = safeStr(data.appointmentTypeId) || undefined;

      if (!clinicId) {
        throw new HttpsError("invalid-argument", "clinicId is required.");
      }

      const purpose = safeStr((data as any).purpose);
      const openingOnly = purpose === "openingWindows";

      logger.info("listPublicSlots purpose", {
        clinicId,
        purpose,
        openingOnly,
        practitionerId: practitionerId || null,
      });

      const fromUtc = safeStr((data as any).fromUtc);
      const toUtc = safeStr((data as any).toUtc);

      const rangeStartDt = fromUtc
        ? parseIso("fromUtc", fromUtc)
        : parseMillis("rangeStart", (data as any).rangeStartMs);

      const rangeEndDt = toUtc
        ? parseIso("toUtc", toUtc)
        : parseMillis("rangeEnd", (data as any).rangeEndMs);

      if (rangeEndDt <= rangeStartDt) {
        throw new HttpsError("invalid-argument", "Invalid range.");
      }

      // Rate limit
      try {
        await enforceRateLimit({
          db,
          clinicId,
          req: request.rawRequest,
          cfg: { name: "listPublicSlots", max: 120, windowSeconds: 60 },
        });
      } catch (e) {
        logger.warn("Rate limit skipped/failed (callable)", {
          clinicId,
          err: String(e),
        });
      }

      // ✅ Commit 17: Read only from mirror config (no private settings)
      const settings = await loadPublicSettingsFromMirror(clinicId);

      const isOpeningWindows = purpose === "openingWindows";
      if (!isOpeningWindows && settings.onlineBookingEnabled === false) {
        throw new HttpsError(
          "failed-precondition",
          "Booking is temporarily unavailable."
        );
      }

      // Validate practitionerId against allowlist (only if practitionerId provided AND not openingWindows)
      // For openingWindows (internal calendar), we allow any practitioner - they just need to exist in the clinic
      if (practitionerId) {
        if (isOpeningWindows) {
          // ✅ For internal calendar, verify practitioner exists in clinic (but don't check public allowlist)
          const memberRef = db.doc(`clinics/${clinicId}/members/${practitionerId}`);
          const legacyRef = db.doc(`clinics/${clinicId}/memberships/${practitionerId}`);
          
          const [memberSnap, legacySnap] = await Promise.all([
            memberRef.get(),
            legacyRef.get(),
          ]);
          
          if (!memberSnap.exists && !legacySnap.exists) {
            throw new HttpsError(
              "failed-precondition",
              `Practitioner ${practitionerId} is not a member of this clinic.`
            );
          }
        } else {
          // ✅ For public booking, check against allowlist
          const allowed = extractAllowedPractitionerIds(settings);
          const ok = allowed.includes(practitionerId);

          if (!ok) {
            throw new HttpsError(
              "failed-precondition",
              "Selected practitioner is not available for public booking."
            );
          }
        }
      }

      const clinicTz = getTz(settings, "");
      const step =
        typeof settings.slotStepMinutes === "number"
          ? settings.slotStepMinutes
          : 15;

      if (!isOpeningWindows) {
        const cacheKey = [
          clinicId,
          locationId ?? "",
          practitionerId ?? "",
          appointmentTypeId ?? "",
          ymdFromDateInTz(rangeStartDt, clinicTz),
        ].join("|");
        const cached = slotCache.get(cacheKey);
        if (cached && Date.now() - cached.cachedAt < SLOT_CACHE_TTL_MS) {
          return { ...cached.result, cached: true };
        }
      }

      const minNotice =
        typeof settings.minNoticeMinutes === "number"
          ? settings.minNoticeMinutes
          : 0;

      const maxAdvanceDays =
        typeof settings.maxAdvanceDays === "number"
          ? settings.maxAdvanceDays
          : 365;

      const nowMs = Date.now();
      const maxMs = nowMs + maxAdvanceDays * 86400000;

      const rangeStartTs = admin.firestore.Timestamp.fromDate(rangeStartDt);
      const rangeEndTs = admin.firestore.Timestamp.fromDate(rangeEndDt);

      const closuresPromise = loadClosures(clinicId, rangeStartTs, rangeEndTs);

      const busyPromise = openingOnly
        ? loadClinicWideBusyBlocks(clinicId, rangeStartTs, rangeEndTs)
        : loadBusyBlocks(clinicId, practitionerId, rangeStartTs, rangeEndTs);

      const apptPromise =
        !openingOnly && practitionerId
          ? loadAppointmentsAsBlocks(
              clinicId,
              practitionerId,
              rangeStartTs,
              rangeEndTs
            )
          : Promise.resolve([]);

      const staffAvailPromise =
        practitionerId && locationId
          ? loadStaffWeeklyAvailabilityForLocation({
              clinicId,
              practitionerId,
              locationId,
            })
          : practitionerId
            ? loadStaffWeeklyAvailability({ clinicId, practitionerId })
            : Promise.resolve(null);

      const overridesPromise = practitionerId
        ? loadPractitionerOverrides(
            clinicId,
            practitionerId,
            rangeStartTs,
            rangeEndTs,
            locationId
          )
        : Promise.resolve({ unavailable: [], available: [] } as OverrideRanges);

      const [closures, busy, apptBlocks, staffAvail, overrides] = await Promise.all([
        closuresPromise,
        busyPromise,
        apptPromise,
        staffAvailPromise,
        overridesPromise,
      ]);

      // Commit 52: Use only clinic timezone for slot/day logic; client tz is for display only.
      const tz =
        safeStr(staffAvail?.timezone) ||
        safeStr(settings.timezone) ||
        clinicTz ||
        "Europe/Prague";

      const blocked = [
        ...closures.map((c) => ({ startMs: c.fromMs, endMs: c.toMs })),
        ...busy.map((b) => ({ startMs: b.startMs, endMs: b.endMs })),
        ...apptBlocks.map((a) => ({ startMs: a.startMs, endMs: a.endMs })),
        ...overrides.unavailable,
      ];

      const clinicWeekly = normalizeWeeklyHours(settings);
      const locHours =
        locationId && settings.locationOpeningHours?.[locationId]
          ? settings.locationOpeningHours[locationId]
          : null;
      const weekly = computeEffectiveWeeklyHours(
        clinicWeekly,
        locHours,
        practitionerId && staffAvail?.weekly ? staffAvail.weekly : null
      );

      const hasAnyHours = Object.values(weekly).some(
        (arr) => Array.isArray(arr) && arr.length > 0
      );

      const corpSlug = safeStr(data.corpSlug) || undefined;
      const corpCode = safeStr(data.corpCode) || undefined;

      const programs = Array.isArray(settings.corporatePrograms)
        ? settings.corporatePrograms
        : [];

      const dayFlags: Record<string, DayFlag> = {};

      let corpDaySet: Set<string> | null = null;
      let corpUnlocked = false;
      let corpMode: CorporateMode | null = null;
      let corpDisplayName: string | undefined;

      if (corpSlug) {
        const corp = findCorporate(settings, corpSlug);
        if (!corp)
          throw new HttpsError("permission-denied", "Invalid corporate link.");

        corpMode = corp.mode === "CODE_UNLOCK" ? "CODE_UNLOCK" : "LINK_ONLY";
        corpDaySet = new Set(
          Array.isArray(corp.days) ? corp.days.map(String) : []
        );
        corpUnlocked =
          corpMode === "CODE_UNLOCK" ? safeStr(corpCode).length > 0 : true;
        corpDisplayName = safeStr(corp.displayName) || undefined;
      } else {
        const linkOnlyDays = new Set<string>();
        for (const p of programs) {
          const mode = p.mode === "CODE_UNLOCK" ? "CODE_UNLOCK" : "LINK_ONLY";
          if (mode === "LINK_ONLY") {
            (Array.isArray(p.days) ? p.days : []).forEach((d) =>
              linkOnlyDays.add(String(d))
            );
          }
        }
        corpDaySet = linkOnlyDays;
      }

      {
        const seen = new Set<string>();
        for (
          let t = rangeStartDt.getTime();
          t < rangeEndDt.getTime();
          t += 86400000
        ) {
          const dt = new Date(t);
          const ymd = ymdFromDateInTz(dt, tz);
          if (seen.has(ymd)) continue;
          seen.add(ymd);

          if (corpSlug) {
            const isCorp = corpDaySet?.has(ymd) === true;
            dayFlags[ymd] = isCorp
              ? {
                  corporateOnly: true,
                  mode: corpMode,
                  corpSlug,
                  displayName: corpDisplayName,
                }
              : { corporateOnly: false, mode: null };
            continue;
          }

          const isCorp = corpDaySet?.has(ymd) === true;
          dayFlags[ymd] = isCorp
            ? { corporateOnly: true, mode: "LINK_ONLY" }
            : { corporateOnly: false, mode: null };
        }
      }

      if (!hasAnyHours) {
        const result = {
          ok: true,
          clinicId,
          serviceId,
          practitionerId,
          locationId: locationId || null,
          appointmentTypeId: appointmentTypeId || null,
          tz,
          stepMinutes: step,
          corporate: corpSlug
            ? { corpSlug, mode: corpMode, unlocked: corpUnlocked }
            : null,
          weeklyHours: weekly,
          dayFlags,
          slots: [] as Array<{ startMs: number; endMs: number }>,
          openingOnly,
          staffAvailabilityApplied: Boolean(practitionerId && staffAvail?.weekly),
          appointmentsApplied: Boolean(!openingOnly && practitionerId),
        };
        if (!isOpeningWindows) {
          const cacheKey = [
            clinicId,
            locationId ?? "",
            practitionerId ?? "",
            appointmentTypeId ?? "",
            ymdFromDateInTz(rangeStartDt, clinicTz),
          ].join("|");
          slotCache.set(cacheKey, { result, cachedAt: Date.now() });
          evictSlotCacheIfNeeded();
        }
        return result;
      }

      const slots: Array<{ startMs: number; endMs: number }> = [];

      for (
        let t = rangeStartDt.getTime();
        t + step * 60000 <= rangeEndDt.getTime();
        t += step * 60000
      ) {
        const startMs = t;
        const endMs = t + step * 60000;

        if (startMs < nowMs + minNotice * 60000) continue;
        if (startMs > maxMs) continue;

        const startDt = new Date(startMs);
        const endDt = new Date(endMs);

        const ymd = ymdFromDateInTz(startDt, tz);

        if (corpSlug) {
          if (!corpDaySet!.has(ymd)) continue;
          if (!corpUnlocked) continue;
        } else {
          if (corpDaySet!.has(ymd)) continue;
        }

        const dk = dayKeyFromDateInTz(startDt, tz);
        const intervals = Array.isArray((weekly as any)[dk])
          ? (weekly as any)[dk]
          : [];
        if (!intervals.length) continue;

        const startHm = new Intl.DateTimeFormat("en-GB", {
          timeZone: tz,
          hour: "2-digit",
          minute: "2-digit",
          hour12: false,
        }).format(startDt);

        const endHm = new Intl.DateTimeFormat("en-GB", {
          timeZone: tz,
          hour: "2-digit",
          minute: "2-digit",
          hour12: false,
        }).format(endDt);

        const sMin = hmToMinutes(startHm);
        const eMin = hmToMinutes(endHm);
        if (!Number.isFinite(sMin) || !Number.isFinite(eMin)) continue;

        const withinWeekly = intervals.some((it: any) => {
          const a = hmToMinutes(safeStr(it.start));
          const b = hmToMinutes(safeStr(it.end));
          if (!Number.isFinite(a) || !Number.isFinite(b) || b <= a) return false;
          return sMin >= a && eMin <= b;
        });
        const withinOverride = slotContainedInRanges(startMs, endMs, overrides.available);
        if (!withinWeekly && !withinOverride) continue;

        if (overlapsAny(startMs, endMs, blocked)) continue;

        slots.push({ startMs, endMs });
      }

      const result = {
        ok: true,
        clinicId,
        serviceId,
        practitionerId,
        locationId: locationId || null,
        appointmentTypeId: appointmentTypeId || null,
        tz,
        stepMinutes: step,
        corporate: corpSlug
          ? { corpSlug, mode: corpMode, unlocked: corpUnlocked }
          : null,
        weeklyHours: weekly,
        dayFlags,
        slots,
        openingOnly,
        staffAvailabilityApplied: Boolean(practitionerId && staffAvail?.weekly),
        appointmentsApplied: Boolean(!openingOnly && practitionerId),
      };
      if (!isOpeningWindows) {
        const cacheKey = [
          clinicId,
          locationId ?? "",
          practitionerId ?? "",
          appointmentTypeId ?? "",
          ymdFromDateInTz(rangeStartDt, clinicTz),
        ].join("|");
        slotCache.set(cacheKey, { result, cachedAt: Date.now() });
        evictSlotCacheIfNeeded();
      }
      return result;
    } catch (err: any) {
      logger.error("listPublicSlots failed", {
        err: err?.message ?? String(err),
        stack: err?.stack,
        code: err?.code,
      });

      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", "listPublicSlots crashed.");
    }
  }
);

// ─── Month availability (dots on calendar) ───────────────────────────────

type MonthAvailabilityInput = {
  clinicId: string;
  practitionerId: string;
  serviceId?: string;
  /** Location-first booking. Optional. */
  locationId?: string;
  /** Appointment type filter. Optional. */
  appointmentTypeId?: string;
  monthStartMs: number;
  monthEndMs: number;
  tz?: string;
  corpCode?: string;
};

type DayAvailabilityOut = { count: number; corporateOnly: boolean };

export const getPublicMonthAvailabilityFn = onCall(
  { region: "europe-west3", cors: true },
  async (request) => {
    try {
      // Auth optional: public booking page may call without sign-in; still return availability.
      const data = (request.data ?? {}) as Partial<MonthAvailabilityInput>;
      const clinicId = safeStr(data.clinicId);
      const practitionerId = safeStr(data.practitionerId);
      const locationId = safeStr(data.locationId) || undefined;
      const serviceId = safeStr(data.serviceId) || "default";

      if (!clinicId || !practitionerId) {
        throw new HttpsError(
          "invalid-argument",
          "clinicId and practitionerId are required."
        );
      }

      const monthStartMs = typeof data.monthStartMs === "number" ? data.monthStartMs : 0;
      const monthEndMs = typeof data.monthEndMs === "number" ? data.monthEndMs : 0;
      if (!Number.isFinite(monthStartMs) || !Number.isFinite(monthEndMs) || monthEndMs <= monthStartMs) {
        throw new HttpsError("invalid-argument", "Invalid monthStartMs / monthEndMs.");
      }

      const monthStartDt = new Date(monthStartMs);
      const monthEndDt = new Date(monthEndMs);
      const rangeStartTs = admin.firestore.Timestamp.fromDate(monthStartDt);
      const rangeEndTs = admin.firestore.Timestamp.fromDate(monthEndDt);

      const settings = await loadPublicSettingsFromMirror(clinicId);
      const allowed = extractAllowedPractitionerIds(settings);
      if (!allowed.includes(practitionerId)) {
        throw new HttpsError(
          "failed-precondition",
          "Selected practitioner is not available for public booking."
        );
      }

      const tz = safeStr(data.tz) || getTz(settings, "") || "Europe/Prague";
      const minNotice =
        typeof settings.minNoticeMinutes === "number" ? settings.minNoticeMinutes : 60;
      const maxAdvanceDays =
        typeof settings.maxAdvanceDays === "number" ? settings.maxAdvanceDays : 365;
      const nowMs = Date.now();
      const maxMs = nowMs + maxAdvanceDays * 86400000;

      const corpCode = safeStr(data.corpCode) || undefined;
      const programs = Array.isArray(settings.corporatePrograms) ? settings.corporatePrograms : [];
      const corpDaySet: Set<string> = new Set();
      for (const p of programs) {
        const mode = (p as any).mode === "CODE_UNLOCK" ? "CODE_UNLOCK" : "LINK_ONLY";
        if (mode === "LINK_ONLY") {
          (Array.isArray((p as any).days) ? (p as any).days : []).forEach((d: string) =>
            corpDaySet.add(String(d))
          );
        }
      }

      const dayFlags: Record<string, DayFlag> = {};
      for (let t = monthStartDt.getTime(); t < monthEndDt.getTime(); t += 86400000) {
        const dt = new Date(t);
        const ymd = ymdFromDateInTz(dt, tz);
        dayFlags[ymd] = corpDaySet.has(ymd)
          ? { corporateOnly: true, mode: "LINK_ONLY" }
          : { corporateOnly: false, mode: null };
      }

      const staffAvailPromise =
        practitionerId && locationId
          ? loadStaffWeeklyAvailabilityForLocation({
              clinicId,
              practitionerId,
              locationId,
            })
          : practitionerId
            ? loadStaffWeeklyAvailability({ clinicId, practitionerId })
            : Promise.resolve(null);

      const overridesPromiseMonth = loadPractitionerOverrides(
        clinicId,
        practitionerId,
        rangeStartTs,
        rangeEndTs,
        locationId
      );

      const [closures, busy, apptBlocks, staffAvail, overridesMonth] = await Promise.all([
        loadClosures(clinicId, rangeStartTs, rangeEndTs),
        loadBusyBlocks(clinicId, practitionerId, rangeStartTs, rangeEndTs),
        loadAppointmentsAsBlocks(clinicId, practitionerId, rangeStartTs, rangeEndTs),
        staffAvailPromise,
        overridesPromiseMonth,
      ]);

      const blocked = [
        ...closures.map((c) => ({ startMs: c.fromMs, endMs: c.toMs })),
        ...busy.map((b) => ({ startMs: b.startMs, endMs: b.endMs })),
        ...apptBlocks.map((a) => ({ startMs: a.startMs, endMs: a.endMs })),
        ...overridesMonth.unavailable,
      ];

      const clinicWeekly = normalizeWeeklyHours(settings);
      const weekly =
        staffAvail?.weekly
          ? intersectWeeklyHours(clinicWeekly, staffAvail.weekly)
          : clinicWeekly;

      const days: Record<string, DayAvailabilityOut> = {};
      const hourMs = 60 * 60 * 1000;

      for (let t = monthStartDt.getTime(); t + hourMs <= monthEndDt.getTime(); t += hourMs) {
        const startMs = t;
        const endMs = t + hourMs;
        if (startMs < nowMs + minNotice * 60000) continue;
        if (startMs > maxMs) continue;

        const startDt = new Date(startMs);
        const ymd = ymdFromDateInTz(startDt, tz);
        const minuteInTz = Number(
          new Intl.DateTimeFormat("en-GB", {
            timeZone: tz,
            minute: "2-digit",
            hour12: false,
          }).format(startDt)
        );
        if (!Number.isFinite(minuteInTz) || minuteInTz !== 0) continue;

        const isCorpDay = corpDaySet.has(ymd);
        if (isCorpDay && !corpCode) continue;

        const dk = dayKeyFromDateInTz(startDt, tz);
        const intervals = Array.isArray((weekly as any)[dk]) ? (weekly as any)[dk] : [];
        if (!intervals.length) continue;

        const startHm = new Intl.DateTimeFormat("en-GB", {
          timeZone: tz,
          hour: "2-digit",
          minute: "2-digit",
          hour12: false,
        }).format(startDt);
        const endHm = new Intl.DateTimeFormat("en-GB", {
          timeZone: tz,
          hour: "2-digit",
          minute: "2-digit",
          hour12: false,
        }).format(new Date(endMs));

        const sMin = hmToMinutes(startHm);
        const eMin = hmToMinutes(endHm);
        if (!Number.isFinite(sMin) || !Number.isFinite(eMin)) continue;

        const withinWeekly = intervals.some((it: any) => {
          const a = hmToMinutes(safeStr(it.start));
          const b = hmToMinutes(safeStr(it.end));
          if (!Number.isFinite(a) || !Number.isFinite(b) || b <= a) return false;
          return sMin >= a && eMin <= b;
        });
        const withinOverride = slotContainedInRanges(startMs, endMs, overridesMonth.available);
        if (!withinWeekly && !withinOverride) continue;

        if (overlapsAny(startMs, endMs, blocked)) continue;

        const cur = days[ymd];
        const flag = dayFlags[ymd];
        days[ymd] = {
          count: (cur?.count ?? 0) + 1,
          corporateOnly: flag?.corporateOnly ?? false,
        };
      }

      return { days };
    } catch (err: any) {
      logger.error("getPublicMonthAvailability failed", {
        err: err?.message ?? String(err),
        stack: err?.stack,
        code: err?.code,
      });
      if (err instanceof HttpsError) throw err;
      // Return empty days so client can still show calendar without dots
      return { days: {} };
    }
  }
);

/**
 * Returns the public booking practitioner list from the full mirror (server-side read).
 * Use this from the public booking UI instead of reading Firestore directly to avoid
 * client-side "Unexpected state" / assertion errors in the Firestore web SDK.
 *
 * Filters:
 * - locationId: returns only practitioners eligible at that location
 *   (allowedLocationIds empty/undefined = all locations, else must include locationId).
 * - serviceId / appointmentTypeId: returns only practitioners eligible for that service
 *   (serviceIdsAllowed empty/undefined = all services, else must include serviceId).
 *
 * Returns full public-safe projected fields so the UI can display rich practitioner info.
 */
export const getPublicBookingPractitionersFn = onCall(
  { region: "europe-west3", cors: true },
  async (request) => {
    try {
      const clinicId = safeStr((request.data as any)?.clinicId);
      if (!clinicId) {
        throw new HttpsError("invalid-argument", "clinicId is required.");
      }
      const locationId = safeStr((request.data as any)?.locationId) || undefined;
      const serviceId =
        safeStr((request.data as any)?.serviceId) ||
        safeStr((request.data as any)?.appointmentTypeId) ||
        undefined;
      const { practitioners } = await loadFullMirrorExtras(clinicId);

      let list = practitioners;

      if (locationId) {
        list = list.filter((p) => {
          const ids = p.allowedLocationIds;
          if (!ids || ids.length === 0) return true;
          return ids.includes(locationId);
        });
      }

      if (serviceId) {
        list = list.filter((p) => {
          const ids = p.serviceIdsAllowed;
          if (!ids || ids.length === 0) return true;
          return ids.includes(serviceId);
        });
      }

      return {
        practitioners: list.map((p) => ({
          id: p.id,
          displayName: p.displayName ?? "",
          title: p.title ?? null,
          photoUrl: p.photoUrl ?? null,
          bio: p.bio ?? null,
          sortOrder: p.sortOrder ?? 0,
          allowedLocationIds: p.allowedLocationIds ?? [],
          serviceIdsAllowed: p.serviceIdsAllowed ?? [],
        })),
      };
    } catch (err: any) {
      if (err instanceof HttpsError) throw err;
      const msg = err?.message ?? String(err);
      logger.error("getPublicBookingPractitionersFn failed", {
        clinicId: (request.data as any)?.clinicId,
        error: msg,
        code: err?.code,
      });
      return { practitioners: [] };
    }
  }
);

/**
 * Returns the public booking locations list from the full mirror (server-side read).
 * Use from the public booking UI for the location-first selector.
 */
export const getPublicBookingLocationsFn = onCall(
  { region: "europe-west3", cors: true },
  async (request) => {
    try {
      const clinicId = safeStr((request.data as any)?.clinicId);
      if (!clinicId) {
        throw new HttpsError("invalid-argument", "clinicId is required.");
      }
      const fullRef = db.doc(FULL_MIRROR_PATH(clinicId));
      const snap = await fullRef.get();
      if (!snap.exists || !snap.data()) {
        return { locations: [] };
      }
      const d = snap.data() as any;
      const raw = Array.isArray(d?.locations) ? d.locations : [];
      const locations = raw.map((item: any) => ({
        id: safeStr(item?.id) || "",
        name: safeStr(item?.name) || safeStr(item?.id) || "",
      })).filter((x: { id: string }) => x.id.length > 0);
      return { locations };
    } catch (err: any) {
      if (err instanceof HttpsError) throw err;
      const msg = err?.message ?? String(err);
      logger.error("getPublicBookingLocationsFn failed", {
        clinicId: (request.data as any)?.clinicId,
        error: msg,
        code: err?.code,
      });
      return { locations: [] };
    }
  }
);

/**
 * Returns the public booking appointment types list from the full mirror (server-side read).
 * Use from the public booking UI for the appointment-type selector (location-first flow step 2).
 */
export const getPublicBookingAppointmentTypesFn = onCall(
  { region: "europe-west3", cors: true },
  async (request) => {
    try {
      const clinicId = safeStr((request.data as any)?.clinicId);
      if (!clinicId) {
        throw new HttpsError("invalid-argument", "clinicId is required.");
      }
      const fullRef = db.doc(FULL_MIRROR_PATH(clinicId));
      const snap = await fullRef.get();
      if (!snap.exists || !snap.data()) {
        return { appointmentTypes: [] };
      }
      const d = snap.data() as any;
      const raw = Array.isArray(d?.appointmentTypes) ? d.appointmentTypes : [];
      const appointmentTypes = raw.map((item: any) => ({
        id: safeStr(item?.id) || "",
        name: safeStr(item?.name) || safeStr(item?.id) || "",
        defaultDurationMinutes: typeof item?.defaultDurationMinutes === "number" ? item.defaultDurationMinutes : 30,
        description: safeStr(item?.description) || undefined,
        defaultPrice: typeof item?.defaultPrice === "number" ? item.defaultPrice : undefined,
        colorHex: safeStr(item?.colorHex) || undefined,
      })).filter((x: { id: string }) => x.id.length > 0);
      return { appointmentTypes };
    } catch (err: any) {
      if (err instanceof HttpsError) throw err;
      const msg = err?.message ?? String(err);
      logger.error("getPublicBookingAppointmentTypesFn failed", {
        clinicId: (request.data as any)?.clinicId,
        error: msg,
        code: err?.code,
      });
      return { appointmentTypes: [] };
    }
  }
);

/**
 * Diagnostic callable (staff only: settings.read). Returns mirror state and practitioner
 * visibility so you can see why "no clinicians" appears. Call from Flutter or Console.
 */
export const getPublicBookingDiagnosticsFn = onCall(
  { region: "europe-west3", cors: true },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const clinicId = safeStr((request.data as any)?.clinicId);
    if (!clinicId) {
      throw new HttpsError("invalid-argument", "clinicId is required.");
    }
    await requireClinicPermission(db, clinicId, request.auth.uid, "settings.read");

    const fullRef = db.doc(FULL_MIRROR_PATH(clinicId));
    const mirrorSnap = await fullRef.get();
    const mirrorExists = mirrorSnap.exists && !!mirrorSnap.data();
    const mirrorData = mirrorSnap.data() as any;
    const practitionerCountInMirror = Array.isArray(mirrorData?.practitioners)
      ? mirrorData.practitioners.length
      : 0;
    const locationCountInMirror = Array.isArray(mirrorData?.locations)
      ? mirrorData.locations.length
      : 0;

    const [practitionersSnap, membersSnap, membershipsSnap] = await Promise.all([
      db.collection(`clinics/${clinicId}/practitioners`).get(),
      db.collection(`clinics/${clinicId}/members`).get(),
      db.collection(`clinics/${clinicId}/memberships`).get(),
    ]);

    const memberStatusByUid = new Map<string, string>();
    for (const d of membersSnap.docs) {
      const data = d.data() as any;
      const status = (data?.status ?? "").toString().toLowerCase();
      const active = data?.active;
      const s = status || (active === true ? "active" : active === false ? "inactive" : "active");
      memberStatusByUid.set(d.id, s || "active");
    }
    for (const d of membershipsSnap.docs) {
      if (!memberStatusByUid.has(d.id)) {
        const data = d.data() as any;
        const status = (data?.status ?? "").toString().toLowerCase();
        const active = data?.active;
        const s = status || (active === true ? "active" : active === false ? "inactive" : "active");
        memberStatusByUid.set(d.id, s || "active");
      }
    }

    const practitionersInClinic = practitionersSnap.docs.map((d) => {
      const data = d.data() as any;
      const membershipStatus = memberStatusByUid.get(d.id) ?? "none";
      const membershipActive = membershipStatus === "none" || membershipStatus === "active";
      return {
        id: d.id,
        showInPublicBooking: data?.showInPublicBooking === true,
        active: data?.active !== false,
        activeForBooking: data?.activeForBooking !== false,
        membershipStatus,
        membershipActive,
      };
    });

    const withVisibility = practitionersInClinic.filter((p) => p.showInPublicBooking).length;
    const withVisibilityButInactiveMembership = practitionersInClinic.filter(
      (p) => p.showInPublicBooking && !p.membershipActive
    ).length;

    let hint: string | undefined;
    if (practitionerCountInMirror === 0 && withVisibility > 0) {
      hint =
        withVisibilityButInactiveMembership > 0
          ? `${withVisibilityButInactiveMembership} practitioner(s) have showInPublicBooking but inactive/suspended membership. Set membership to Active in Settings → Team, then re-save Public booking.`
          : "Mirror has 0 practitioners but some have showInPublicBooking. Re-save Settings → Public booking to rebuild the mirror.";
    } else if (practitionerCountInMirror === 0 && withVisibility === 0) {
      hint =
        "No practitioners have showInPublicBooking: true. Turn ON in Settings → Public booking and Save.";
    }

    return {
      mirrorExists,
      practitionerCountInMirror,
      locationCountInMirror,
      practitionersInClinicCount: practitionersInClinic.length,
      practitionersWithPublicVisibility: withVisibility,
      practitioners: practitionersInClinic,
      hint,
    };
  }
);
