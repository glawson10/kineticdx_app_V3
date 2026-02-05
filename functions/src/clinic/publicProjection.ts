// functions/src/clinic/publicProjection.ts
import * as admin from "firebase-admin";

type AnyMap = Record<string, any>;

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

function safeNum(v: unknown, fallback: number): number {
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? n : fallback;
}

function isObj(v: unknown): v is AnyMap {
  return !!v && typeof v === "object" && !Array.isArray(v);
}

// ---- Time parsing/validation helpers ----
function hmToMinutes(hm: string): number {
  const m = /^(\d{2}):(\d{2})$/.exec((hm ?? "").toString().trim());
  if (!m) return NaN;
  const hh = Number(m[1]);
  const mm = Number(m[2]);
  if (!Number.isFinite(hh) || !Number.isFinite(mm)) return NaN;
  if (hh < 0 || hh > 23 || mm < 0 || mm > 59) return NaN;
  return hh * 60 + mm;
}

const DAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;
export type DayKey = (typeof DAY_KEYS)[number];

export type WeeklyInterval = { start: string; end: string };

export type WeeklyHours = Record<DayKey, WeeklyInterval[]>;

export type WeeklyHoursDayMeta = {
  corporateOnly: boolean;
  requiresCorporateCode: boolean;
  locationLabel: string;
};

export type WeeklyHoursMeta = Record<DayKey, WeeklyHoursDayMeta>;

function initWeeklyHours(): WeeklyHours {
  return { mon: [], tue: [], wed: [], thu: [], fri: [], sat: [], sun: [] };
}

function initWeeklyHoursMeta(): WeeklyHoursMeta {
  const base: WeeklyHoursDayMeta = {
    corporateOnly: false,
    requiresCorporateCode: false,
    locationLabel: "",
  };

  return {
    mon: { ...base },
    tue: { ...base },
    wed: { ...base },
    thu: { ...base },
    fri: { ...base },
    sat: { ...base },
    sun: { ...base },
  };
}

function takeIntervals(list: any[]): WeeklyInterval[] {
  const cleaned: WeeklyInterval[] = [];
  if (!Array.isArray(list)) return cleaned;

  for (const it of list) {
    if (!isObj(it)) continue;
    const start = safeStr(it.start);
    const end = safeStr(it.end);
    if (!start || !end) continue;

    const a = hmToMinutes(start);
    const b = hmToMinutes(end);
    if (!Number.isFinite(a) || !Number.isFinite(b)) continue;
    if (b <= a) continue;

    cleaned.push({ start, end });
  }

  return cleaned;
}

function dayKeyFromRow(row: AnyMap): DayKey | null {
  const rawDay =
    safeStr(row.day) ||
    safeStr(row.dayKey) ||
    safeStr(row.weekday) ||
    safeStr(row.id);

  const dk = rawDay.toLowerCase().slice(0, 3) as DayKey;
  if (!DAY_KEYS.includes(dk)) return null;
  return dk;
}

function boolish(v: any): boolean | null {
  if (v === true) return true;
  if (v === false) return false;
  if (typeof v === "string") {
    const s = v.trim().toLowerCase();
    if (s === "true" || s === "yes" || s === "1") return true;
    if (s === "false" || s === "no" || s === "0") return false;
  }
  if (typeof v === "number") {
    if (v === 1) return true;
    if (v === 0) return false;
  }
  return null;
}

function inferCorporateMetaFromDayRow(row: AnyMap): Partial<WeeklyHoursDayMeta> {
  const corporateOnlyRaw =
    boolish(row.corporateOnly) ??
    boolish(row.corporateDay) ??
    boolish(row.corporate_only) ??
    null;

  const corporateObj = isObj(row.corporate) ? row.corporate : null;
  const corporateOnlyNested =
    corporateObj
      ? (boolish(corporateObj.corporateOnly) ??
          boolish(corporateObj.enabled) ??
          null)
      : null;

  const corporateOnly =
    (corporateOnlyRaw ?? corporateOnlyNested ?? false) === true;

  const code =
    safeStr(row.corporateCode) ||
    safeStr(row.code) ||
    (corporateObj
      ? safeStr(corporateObj.code) || safeStr(corporateObj.corporateCode)
      : "");

  const locationLabel =
    safeStr(row.locationLabel) ||
    safeStr(row.location) ||
    (corporateObj
      ? safeStr(corporateObj.locationLabel) || safeStr(corporateObj.location)
      : "");

  const requiresCorporateCode = corporateOnly && code.trim().length > 0;

  return {
    corporateOnly,
    requiresCorporateCode,
    locationLabel,
  };
}

function inferCorporateMetaFromOpeningHoursDayList(
  openingHoursDaysArr: any[]
): WeeklyHoursMeta {
  const meta = initWeeklyHoursMeta();
  if (!Array.isArray(openingHoursDaysArr)) return meta;

  for (const row of openingHoursDaysArr) {
    if (!isObj(row)) continue;
    const dk = dayKeyFromRow(row);
    if (!dk) continue;

    const inferred = inferCorporateMetaFromDayRow(row);
    meta[dk] = {
      corporateOnly: inferred.corporateOnly ?? meta[dk].corporateOnly,
      requiresCorporateCode:
        inferred.requiresCorporateCode ?? meta[dk].requiresCorporateCode,
      locationLabel: inferred.locationLabel ?? meta[dk].locationLabel,
    };
  }

  return meta;
}

function mergeMeta(
  target: WeeklyHoursMeta,
  patch: Partial<WeeklyHoursMeta>
): WeeklyHoursMeta {
  const out = { ...target };
  for (const day of DAY_KEYS) {
    const p = (patch as any)[day];
    if (!isObj(p)) continue;
    out[day] = {
      corporateOnly: boolish(p.corporateOnly) ?? out[day].corporateOnly,
      requiresCorporateCode:
        boolish(p.requiresCorporateCode) ?? out[day].requiresCorporateCode,
      locationLabel: safeStr(p.locationLabel) || out[day].locationLabel,
    };
  }
  return out;
}

function normalizeWeeklyHoursFromSettings(settings: AnyMap): WeeklyHours {
  const out = initWeeklyHours();

  // 1) Canonical: settings.weeklyHours
  if (isObj(settings.weeklyHours)) {
    for (const day of DAY_KEYS) {
      const v = (settings.weeklyHours as AnyMap)[day];
      if (Array.isArray(v)) out[day] = takeIntervals(v);
      else out[day] = [];
    }
    return out;
  }

  // 2) Legacy: settings.openingHours
  const oh = settings.openingHours;
  if (!isObj(oh)) return out;

  // 2a) openingHours.{mon..sun} = [{start,end}]
  let matchedKeyMap = false;
  for (const day of DAY_KEYS) {
    const v = (oh as AnyMap)[day];
    if (Array.isArray(v)) {
      matchedKeyMap = true;
      out[day] = takeIntervals(v);
    }
  }
  if (matchedKeyMap) return out;

  // 2b) openingHours.days[]
  const daysArr = (oh as AnyMap).days;
  if (!Array.isArray(daysArr)) return out;

  for (const row of daysArr) {
    if (!isObj(row)) continue;

    const dk = dayKeyFromRow(row);
    if (!dk) continue;

    const openFlag =
      row.open === true ||
      row.isOpen === true ||
      row.closed === false ||
      row.isClosed === false;

    const closedFlag =
      row.closed === true ||
      row.isClosed === true ||
      row.open === false ||
      row.isOpen === false;

    if (closedFlag) {
      out[dk] = [];
      continue;
    }

    const intervals =
      (Array.isArray(row.intervals) && row.intervals) ||
      (Array.isArray(row.windows) && row.windows) ||
      (Array.isArray(row.ranges) && row.ranges) ||
      (safeStr(row.start) && safeStr(row.end)
        ? [{ start: row.start, end: row.end }]
        : []) ||
      [];

    const cleaned = takeIntervals(intervals);

    if (openFlag) out[dk] = cleaned;
    else if (cleaned.length > 0) out[dk] = cleaned;
  }

  return out;
}

function normalizeWeeklyHoursMetaFromSettings(settings: AnyMap): WeeklyHoursMeta {
  let meta = initWeeklyHoursMeta();

  // 1) Canonical meta: settings.weeklyHoursMeta
  if (isObj(settings.weeklyHoursMeta)) {
    meta = mergeMeta(meta, settings.weeklyHoursMeta as AnyMap);
  }

  // 2) Legacy: settings.openingHours.days[]
  const oh = settings.openingHours;
  if (isObj(oh) && Array.isArray((oh as AnyMap).days)) {
    const inferred = inferCorporateMetaFromOpeningHoursDayList(
      (oh as AnyMap).days
    );
    meta = mergeMeta(meta, inferred as any);
  }

  return meta;
}

function weeklyHoursToOpeningHours(weeklyHours: WeeklyHours) {
  const days = DAY_KEYS.map((day) => {
    const intervals = weeklyHours[day] ?? [];
    if (intervals.length === 0) {
      return { day, open: false, start: "", end: "" };
    }
    return {
      day,
      open: true,
      start: intervals[0].start,
      end: intervals[0].end,
    };
  });

  return {
    weekStart: "mon" as const,
    daysOrder: "mon" as const,
    days,
  };
}

export type PublicBookingServiceProjection = {
  id: string;
  name: string;
  minutes: number;
  price: any;
  description: string;
};

export type PublicBookingPractitionerProjection = {
  id: string;
  displayName: string;
  serviceIdsAllowed?: string[];
  sortOrder?: number;
};

export type PublicBookingContactProjection = {
  landingUrl: string;
  websiteUrl: string;
  whatsapp: string;
  email: string;
  phone: string;
};

export type PublicBookingProjection = {
  clinicId: string;
  clinicName: string;
  logoUrl: string;

  contact: PublicBookingContactProjection;

  weeklyHours: WeeklyHours;
  weeklyHoursMeta: WeeklyHoursMeta;
  openingHours: ReturnType<typeof weeklyHoursToOpeningHours>;

  bookingRules: AnyMap;
  slotMinutes: number;

  services: PublicBookingServiceProjection[];

  practitioners: PublicBookingPractitionerProjection[];

  updatedAt: any;
};

// --------------------
// Practitioner helpers
// --------------------

function normalizeMembershipStatus(m: AnyMap): string {
  const s = safeStr(m.status).toLowerCase();
  if (s) return s;

  // Back-compat: no status => infer from active bool (or default active)
  if ("active" in m) return m.active === true ? "active" : "inactive";
  return "active"; // missing active treated as active historically
}

function isActiveMembership(m: AnyMap): boolean {
  const status = normalizeMembershipStatus(m);
  return status === "active";
}

function normalizePractitionerDisplayName(pract: AnyMap, membership?: AnyMap) {
  const dn =
    safeStr(pract.displayName) ||
    safeStr(pract.name) ||
    safeStr(membership?.displayName) ||
    safeStr(membership?.name) ||
    "Practitioner";
  return dn;
}

function normalizeServiceIdsAllowed(pract: AnyMap): string[] | undefined {
  const raw = pract.serviceIdsAllowed ?? pract.allowedServiceIds ?? pract.serviceIds;
  if (!Array.isArray(raw)) return undefined;
  const cleaned = raw.map((x: any) => safeStr(x)).filter((x: string) => !!x);
  return cleaned.length ? cleaned : undefined;
}

function normalizeSortOrder(pract: AnyMap): number | undefined {
  const n =
    safeNum(pract.sortOrder, NaN) ||
    safeNum(pract.order, NaN) ||
    safeNum(pract.rank, NaN) ||
    NaN;
  return Number.isFinite(n) ? n : undefined;
}

function isPractitionerActiveForBooking(pract: AnyMap): boolean {
  const v = boolish(pract.activeForBooking);
  if (v === null) return true;
  return v === true;
}

function isPractitionerActive(pract: AnyMap): boolean {
  const v = boolish(pract.active);
  if (v === null) return true;
  return v === true;
}

/**
 * Membership is OPTIONAL:
 * - If membership exists and is NOT active -> exclude
 * - If membership does not exist -> still include (so public booking works)
 */
function buildPublicPractitioners(args: {
  practitioners: Array<{ id: string; data: AnyMap }>;
  memberships: Array<{ id: string; data: AnyMap }>;
}): PublicBookingPractitionerProjection[] {
  const memberById = new Map<string, AnyMap>();
  for (const m of args.memberships ?? []) {
    if (!m || !safeStr(m.id)) continue;
    memberById.set(safeStr(m.id), isObj(m.data) ? m.data : {});
  }

  const out: PublicBookingPractitionerProjection[] = [];

  for (const p of args.practitioners ?? []) {
    const uid = safeStr(p?.id);
    if (!uid) continue;

    const pData = isObj(p.data) ? p.data : {};
    const mem = memberById.get(uid); // may be undefined

    if (mem && !isActiveMembership(mem)) continue;

    if (!isPractitionerActive(pData)) continue;
    if (!isPractitionerActiveForBooking(pData)) continue;

    const proj: PublicBookingPractitionerProjection = {
      id: uid,
      displayName: normalizePractitionerDisplayName(pData, mem),
    };

    const serviceIdsAllowed = normalizeServiceIdsAllowed(pData);
    if (serviceIdsAllowed && serviceIdsAllowed.length) {
      proj.serviceIdsAllowed = serviceIdsAllowed;
    }

    const sortOrder = normalizeSortOrder(pData);
    if (typeof sortOrder === "number" && Number.isFinite(sortOrder)) {
      proj.sortOrder = sortOrder;
    }

    out.push(proj);
  }

  out.sort((a, b) => {
    const ao = a.sortOrder ?? 999999;
    const bo = b.sortOrder ?? 999999;
    if (ao !== bo) return ao - bo;
    return (a.displayName ?? "").localeCompare(b.displayName ?? "");
  });

  return out;
}

function readClinicProfileLike(clinicDoc: AnyMap): AnyMap {
  const profile = isObj(clinicDoc.profile) ? clinicDoc.profile : {};

  const pick = (k: string) => {
    if (clinicDoc[k] !== undefined && clinicDoc[k] !== null) return clinicDoc[k];
    if (profile[k] !== undefined && profile[k] !== null) return profile[k];
    return null;
  };

  return {
    phone: pick("phone"),
    email: pick("email"),
    websiteUrl: pick("websiteUrl"),
    landingUrl: pick("landingUrl"),
    whatsapp: pick("whatsapp"),
  };
}

export function buildPublicBookingProjection(args: {
  clinicId: string;
  clinicName: string;
  logoUrl: string;

  clinicDoc?: AnyMap;

  publicBookingSettingsDoc: AnyMap;

  services: Array<{ id: string; data: AnyMap }>;
  practitioners: Array<{ id: string; data: AnyMap }>;
  memberships: Array<{ id: string; data: AnyMap }>;
}): PublicBookingProjection {
  const now = admin.firestore.FieldValue.serverTimestamp();

  const settings = isObj(args.publicBookingSettingsDoc)
    ? args.publicBookingSettingsDoc
    : {};

  const bookingRules = isObj(settings.bookingRules) ? settings.bookingRules : {};
  const bookingStructure = isObj(settings.bookingStructure)
    ? settings.bookingStructure
    : {};

  const slotMinutes =
    safeNum(bookingStructure.publicSlotMinutes, NaN) ||
    safeNum(bookingStructure.slotMinutes, NaN) ||
    safeNum(bookingStructure.slotStepMinutes, NaN) ||
    60;

  const weeklyHours = normalizeWeeklyHoursFromSettings(settings);
  const weeklyHoursMeta = normalizeWeeklyHoursMetaFromSettings(settings);
  const openingHours = weeklyHoursToOpeningHours(weeklyHours);

  const services: PublicBookingServiceProjection[] = (args.services ?? []).map((s) => {
    const d = isObj(s.data) ? s.data : {};

    const minutes =
      safeNum(d.minutes, NaN) ||
      safeNum(d.defaultMinutes, NaN) ||
      safeNum(d.durationMinutes, NaN) ||
      30;

    const price = d.price ?? d.defaultFee ?? d.fee ?? null;

    return {
      id: s.id,
      name: safeStr(d.name),
      minutes,
      price,
      description: safeStr(d.description),
    };
  });

  const practitioners = buildPublicPractitioners({
    practitioners: args.practitioners ?? [],
    memberships: args.memberships ?? [],
  });

  const clinicDoc = isObj(args.clinicDoc) ? args.clinicDoc : {};
  const c = readClinicProfileLike(clinicDoc);

  const contact: PublicBookingContactProjection = {
    landingUrl: safeStr(c.landingUrl),
    websiteUrl: safeStr(c.websiteUrl),
    whatsapp: safeStr(c.whatsapp),
    email: safeStr(c.email),
    phone: safeStr(c.phone),
  };

  return {
    clinicId: safeStr(args.clinicId),
    clinicName: safeStr(args.clinicName) || "Clinic",
    logoUrl: safeStr(args.logoUrl),

    contact,

    weeklyHours,
    weeklyHoursMeta,
    openingHours,

    bookingRules,
    slotMinutes,

    services,
    practitioners,

    updatedAt: now,
  };
}
