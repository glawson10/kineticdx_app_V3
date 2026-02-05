// functions/src/public/listPublicSlots.ts
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/logger";
import { enforceRateLimit } from "./rateLimit";

// ✅ Adjust this import path to match your project
// e.g. "../clinic/writePublicBookingMirror" or "../clinic/publicProjectionWriter"
import { writePublicBookingMirror } from "../clinic/writePublicBookingMirror";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

type Input = {
  clinicId: string;
  serviceId?: string;
  practitionerId?: string;
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

// ✅ NEW: self-healing loader for public settings
async function loadPublicSettingsOrRebuildMirror(clinicId: string): Promise<PublicSettings> {
  const mirrorRef = db.doc(
    `clinics/${clinicId}/public/config/publicBooking/publicBooking`
  );

  const mirrorSnap = await mirrorRef.get();
  if (mirrorSnap.exists) {
    const d = (mirrorSnap.data() ?? {}) as PublicSettings;

    // If it looks healthy, use it.
    // (We consider it healthy if it has at least one of weeklyHours/openingHours.)
    const hasHours =
      (d.weeklyHours && typeof d.weeklyHours === "object") ||
      (d.openingHours && typeof d.openingHours === "object");

    if (hasHours) return d;

    logger.warn("Public booking mirror exists but appears incomplete; attempting rebuild", {
      clinicId,
      hasWeeklyHours: !!d.weeklyHours,
      hasOpeningHours: !!d.openingHours,
    });
  }

  // If mirror missing OR incomplete -> rebuild from settings
  const settingsRef = db.doc(`clinics/${clinicId}/settings/publicBooking`);
  const settingsSnap = await settingsRef.get();

  if (!settingsSnap.exists) {
    throw new HttpsError(
      "failed-precondition",
      "Public booking not configured (missing settings/publicBooking)."
    );
  }

  const rawSettings = (settingsSnap.data() ?? {}) as any;

  // This writes the mirror + returns the projection
  const projection = await writePublicBookingMirror(clinicId, rawSettings);

  return (projection ?? {}) as PublicSettings;
}

export const listPublicSlotsFn = onCall(
  { region: "europe-west3", cors: true },
  async (request) => {
    try {
      const data = (request.data ?? {}) as Partial<Input>;

      const clinicId = safeStr(data.clinicId);
      const serviceId = safeStr(data.serviceId);
      const practitionerId = safeStr(data.practitionerId);

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

      // ✅ Use self-healing settings loader
      const settings = await loadPublicSettingsOrRebuildMirror(clinicId);

      // Validate practitionerId against allowlist (only if practitionerId provided)
      if (practitionerId) {
        const allowed = extractAllowedPractitionerIds(settings);
        const ok = allowed.includes(practitionerId);

        if (!ok) {
          throw new HttpsError(
            "failed-precondition",
            "Selected practitioner is not available for public booking."
          );
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
