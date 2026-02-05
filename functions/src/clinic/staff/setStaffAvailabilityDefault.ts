// functions/src/clinic/staff/setStaffAvailabilityDefault.ts
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/logger";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

type Interval = { start: string; end: string };

type Input = {
  clinicId: string;
  uid: string;
  timezone: string;
  weekly: Record<string, Interval[]>;
};

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

function readBoolOrUndefined(v: any): boolean | undefined {
  if (v === true) return true;
  if (v === false) return false;
  return undefined;
}

function isMemberActiveLike(data: Record<string, any>): boolean {
  const status = safeStr((data as any).status);
  if (status === "suspended") return false;
  if (status === "invited") return false;

  const active = readBoolOrUndefined((data as any).active);
  if (active !== undefined) return active;

  return true;
}

function getPermissionsMap(data: Record<string, any>): Record<string, any> {
  const p = (data as any).permissions;
  if (p && typeof p === "object" && !Array.isArray(p)) return p;
  return {};
}

async function getMembershipWithFallback(params: {
  clinicId: string;
  uid: string;
}): Promise<Record<string, any> | null> {
  const canonical = await db
    .doc(`clinics/${params.clinicId}/members/${params.uid}`)
    .get();
  if (canonical.exists) return canonical.data() ?? {};

  const legacy = await db
    .doc(`clinics/${params.clinicId}/memberships/${params.uid}`)
    .get();
  if (legacy.exists) return legacy.data() ?? {};

  return null;
}

function ensurePlainObject(v: any, label: string): Record<string, any> {
  if (!v || typeof v !== "object" || Array.isArray(v)) {
    throw new HttpsError("invalid-argument", `${label} must be an object.`);
  }
  return v;
}

const DAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;

function parseHHMM(s: string): number {
  const m = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(safeStr(s));
  if (!m) {
    throw new HttpsError("invalid-argument", `Invalid time "${s}" (HH:mm).`);
  }
  return Number(m[1]) * 60 + Number(m[2]);
}

function validateIntervals(day: string, arr: any): Interval[] {
  if (!Array.isArray(arr)) {
    throw new HttpsError("invalid-argument", `weekly.${day} must be an array.`);
  }

  const out: Interval[] = [];

  for (let i = 0; i < arr.length; i++) {
    const it = arr[i];
    const start = safeStr(it?.start);
    const end = safeStr(it?.end);
    if (!start || !end) {
      throw new HttpsError(
        "invalid-argument",
        `weekly.${day}[${i}] requires start and end`
      );
    }

    const s = parseHHMM(start);
    const e = parseHHMM(end);
    if (e <= s) {
      throw new HttpsError(
        "invalid-argument",
        `weekly.${day}[${i}] end must be after start`
      );
    }

    out.push({ start, end });
  }

  // overlap check
  const mins = out
    .map((x) => ({ s: parseHHMM(x.start), e: parseHHMM(x.end) }))
    .sort((a, b) => a.s - b.s);

  for (let i = 1; i < mins.length; i++) {
    if (mins[i].s < mins[i - 1].e) {
      throw new HttpsError(
        "invalid-argument",
        `weekly.${day} has overlapping intervals`
      );
    }
  }

  return out;
}

function sanitizeWeekly(raw: any): Record<string, Interval[]> {
  const obj = ensurePlainObject(raw, "weekly");
  const out: Record<string, Interval[]> = {};

  for (const d of DAYS) {
    out[d] = validateIntervals(d, (obj as any)[d] ?? []);
  }

  return out;
}

export async function setStaffAvailabilityDefault(
  req: CallableRequest<Input>
) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = safeStr(req.data?.clinicId);
  const targetUid = safeStr(req.data?.uid);
  const timezone = safeStr(req.data?.timezone);

  if (!clinicId || !targetUid || !timezone) {
    throw new HttpsError("invalid-argument", "Missing required fields.");
  }

  const actorUid = req.auth.uid;

  const actorMembership = await getMembershipWithFallback({
    clinicId,
    uid: actorUid,
  });
  if (!actorMembership || !isMemberActiveLike(actorMembership)) {
    throw new HttpsError("permission-denied", "Not allowed.");
  }

  const perms = getPermissionsMap(actorMembership);
  if (perms["members.manage"] !== true) {
    throw new HttpsError("permission-denied", "Insufficient permissions.");
  }

  const targetMembership = await getMembershipWithFallback({
    clinicId,
    uid: targetUid,
  });
  if (!targetMembership) {
    throw new HttpsError("not-found", "Target staff not in clinic.");
  }

  const weekly = sanitizeWeekly(req.data?.weekly);

  const ref = db.doc(
    `clinics/${clinicId}/staffProfiles/${targetUid}/availability/default`
  );

  const snap = await ref.get();
  const now = admin.firestore.FieldValue.serverTimestamp();

  await ref.set(
    {
      timezone,
      weekly,
      updatedAt: now,
      updatedByUid: actorUid,
      ...(snap.exists
        ? {}
        : { createdAt: now, createdByUid: actorUid }),
    },
    { merge: false } // ✅ AUTHORITATIVE REPLACE
  );

  logger.info("setStaffAvailabilityDefault: ok", {
    clinicId,
    actorUid,
    targetUid,
    created: !snap.exists,
  });

  return { ok: true, uid: targetUid };
}
