// functions/src/public/listPublicSlots.ts
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/logger";
import { enforceRateLimit } from "./rateLimit";
import { requireClinicPermission } from "../clinic/permissions";

// Commit 17: Availability reads only from public/config/publicBooking/config (no writePublicBookingMirror / private settings).

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

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
};

type PublicSettings = {
  timezone?: string;
  slotStepMinutes?: number;
  minNoticeMinutes?: number;
  maxAdvanceDays?: number;

  // Clinic hours (public booking settings)
  weeklyHours?: Record<string, Array<{ start: string; end: string }>>;
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

function intersectWeeklyHours(
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

/** Load booking rules + weeklyHours from mirror config doc only. Uses defaults if missing. */
async function loadPublicConfigFromMirror(clinicId: string): Promise<{
  timezone: string;
  slotStepMinutes: number;
  minNoticeMinutes: number;
  maxAdvanceDays: number;
  weeklyHours: Record<string, Array<{ start: string; end: string }>>;
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
    };
  }

  const d = configSnap.data() as any;
  const jurisdiction = d?.jurisdiction && typeof d.jurisdiction === "object" ? d.jurisdiction : {};
  const rules = d?.bookingRules && typeof d.bookingRules === "object" ? d.bookingRules : {};
  const wh = d?.weeklyHours && typeof d.weeklyHours === "object" ? d.weeklyHours : {};

  const timezone = safeStr(jurisdiction.timezone) || "UTC";
  const slotStepMinutes =
    typeof rules.slotStepMinutes === "number" && [5, 10, 15, 20, 30].includes(rules.slotStepMinutes)
      ? rules.slotStepMinutes
      : 15;
  const minNoticeMinutes =
    typeof rules.minNoticeMinutes === "number" && rules.minNoticeMinutes >= 0
      ? rules.minNoticeMinutes
      : 0;
  const maxAdvanceDays =
    typeof rules.maxAdvanceDays === "number" && rules.maxAdvanceDays >= 7 && rules.maxAdvanceDays <= 365
      ? rules.maxAdvanceDays
      : 90;

  const weeklyHours = defaultWeeklyHours();
  for (const day of DAY_KEYS) {
    const v = wh[day];
    if (Array.isArray(v)) {
      weeklyHours[day] = v
        .filter((it: any) => it && typeof it === "object" && safeStr(it.start) && safeStr(it.end))
        .map((it: any) => ({ start: safeStr(it.start), end: safeStr(it.end) }));
    }
  }

  return {
    timezone,
    slotStepMinutes,
    minNoticeMinutes,
    maxAdvanceDays,
    weeklyHours,
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
        practitioners.push({
          id,
          displayName: safeStr((item as any).displayName),
          serviceIdsAllowed: (item as any).serviceIdsAllowed,
          sortOrder: (item as any).sortOrder,
          allowedLocationIds,
        });
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

      // Validate practitionerId against allowlist (only if practitionerId provided AND not openingWindows)
      // For openingWindows (internal calendar), we allow any practitioner - they just need to exist in the clinic
      const isOpeningWindows = purpose === "openingWindows";
      
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

      const staffAvailPromise = practitionerId
        ? loadStaffWeeklyAvailability({ clinicId, practitionerId })
        : Promise.resolve(null);

      const [closures, busy, apptBlocks, staffAvail] = await Promise.all([
        closuresPromise,
        busyPromise,
        apptPromise,
        staffAvailPromise,
      ]);

      const tzOverride = safeStr((data as any).tz);
      const tz =
        tzOverride ||
        safeStr(staffAvail?.timezone) ||
        safeStr(settings.timezone) ||
        clinicTz ||
        "Europe/Prague";

      const blocked = [
        ...closures.map((c) => ({ startMs: c.fromMs, endMs: c.toMs })),
        ...busy.map((b) => ({ startMs: b.startMs, endMs: b.endMs })),
        ...apptBlocks.map((a) => ({ startMs: a.startMs, endMs: a.endMs })),
      ];

      const clinicWeekly = normalizeWeeklyHours(settings);

      const weekly =
        practitionerId && staffAvail?.weekly
          ? intersectWeeklyHours(clinicWeekly, staffAvail.weekly)
          : clinicWeekly;

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
        return {
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
          slots: [],
          openingOnly,
          staffAvailabilityApplied: Boolean(practitionerId && staffAvail?.weekly),
          appointmentsApplied: Boolean(!openingOnly && practitionerId),
        };
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

        const within = intervals.some((it: any) => {
          const a = hmToMinutes(safeStr(it.start));
          const b = hmToMinutes(safeStr(it.end));
          if (!Number.isFinite(a) || !Number.isFinite(b) || b <= a) return false;
          return sMin >= a && eMin <= b;
        });
        if (!within) continue;

        if (overlapsAny(startMs, endMs, blocked)) continue;

        slots.push({ startMs, endMs });
      }

      return {
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

      const [closures, busy, apptBlocks, staffAvail] = await Promise.all([
        loadClosures(clinicId, rangeStartTs, rangeEndTs),
        loadBusyBlocks(clinicId, practitionerId, rangeStartTs, rangeEndTs),
        loadAppointmentsAsBlocks(clinicId, practitionerId, rangeStartTs, rangeEndTs),
        loadStaffWeeklyAvailability({ clinicId, practitionerId }),
      ]);

      const blocked = [
        ...closures.map((c) => ({ startMs: c.fromMs, endMs: c.toMs })),
        ...busy.map((b) => ({ startMs: b.startMs, endMs: b.endMs })),
        ...apptBlocks.map((a) => ({ startMs: a.startMs, endMs: a.endMs })),
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

        const within = intervals.some((it: any) => {
          const a = hmToMinutes(safeStr(it.start));
          const b = hmToMinutes(safeStr(it.end));
          if (!Number.isFinite(a) || !Number.isFinite(b) || b <= a) return false;
          return sMin >= a && eMin <= b;
        });
        if (!within) continue;

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
 * When locationId is provided, returns only practitioners eligible at that location
 * (allowedLocationIds empty/undefined = all locations, else must include locationId).
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
      const { practitioners } = await loadFullMirrorExtras(clinicId);

      let list = practitioners;
      if (locationId) {
        list = practitioners.filter((p) => {
          const ids = p.allowedLocationIds;
          if (!ids || ids.length === 0) return true;
          return ids.includes(locationId);
        });
      }

      return {
        practitioners: list.map((p) => ({
          id: p.id,
          displayName: p.displayName ?? "",
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
      // Return empty list so UI shows "No practitioners" + hint instead of "[internal] internal"
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
        showInOnlineBooking: data?.showInOnlineBooking === true,
        active: data?.active !== false,
        activeForBooking: data?.activeForBooking !== false,
        membershipStatus,
        membershipActive,
      };
    });

    const withVisibility = practitionersInClinic.filter((p) => p.showInOnlineBooking).length;
    const withVisibilityButInactiveMembership = practitionersInClinic.filter(
      (p) => p.showInOnlineBooking && !p.membershipActive
    ).length;

    let hint: string | undefined;
    if (practitionerCountInMirror === 0 && withVisibility > 0) {
      hint =
        withVisibilityButInactiveMembership > 0
          ? `${withVisibilityButInactiveMembership} practitioner(s) have showInOnlineBooking but inactive/suspended membership. Set membership to Active in Settings → Team, then re-save Online booking.`
          : "Mirror has 0 practitioners but some have showInOnlineBooking. Re-save Settings → Public booking or Online booking to rebuild the mirror.";
    } else if (practitionerCountInMirror === 0 && withVisibility === 0) {
      hint =
        "No practitioners have showInOnlineBooking: true. Turn ON in Settings → Online booking and Save.";
    }

    return {
      mirrorExists,
      practitionerCountInMirror,
      locationCountInMirror,
      practitionersInClinicCount: practitionersInClinic.length,
      practitionersWithShowInOnlineBooking: withVisibility,
      practitioners: practitionersInClinic,
      hint,
    };
  }
);
