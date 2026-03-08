/**
 * Transitional: mirror practitioners/{id}/availability → staffProfiles/{id}/availability/default
 * so listPublicSlotsFn (which still reads only the legacy path) sees edits from the new Availability UI.
 * See docs/AVAILABILITY_SOURCES.md.
 */

import * as admin from "firebase-admin";
import { logger } from "firebase-functions/logger";

const db = admin.firestore();

const DAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;
/** dayOfWeek 1 = Monday → mon, 7 = Sunday → sun */
const DOW_TO_DAY: Record<number, (typeof DAY_KEYS)[number]> = {
  1: "mon",
  2: "tue",
  3: "wed",
  4: "thu",
  5: "fri",
  6: "sat",
  7: "sun",
};

function hmToMinutes(hhmm: string): number | null {
  const s = String(hhmm ?? "").trim();
  const m = /^([01]?\d|2[0-3]):([0-5]\d)$/.exec(s);
  if (!m) return null;
  return Number(m[1]) * 60 + Number(m[2]);
}

function minutesToHHmm(m: number): string {
  const hh = Math.floor(m / 60);
  const mm = m % 60;
  return `${String(hh).padStart(2, "0")}:${String(mm).padStart(2, "0")}`;
}

type IntervalMin = { a: number; b: number };

function mergeIntervals(list: IntervalMin[]): IntervalMin[] {
  if (list.length === 0) return [];
  const sorted = [...list].sort((x, y) => x.a - y.a);
  const out: IntervalMin[] = [];
  let cur: IntervalMin = sorted[0];

  for (let i = 1; i < sorted.length; i++) {
    const it = sorted[i];
    if (it.a <= cur.b) {
      cur = { a: cur.a, b: Math.max(cur.b, it.b) };
    } else {
      out.push(cur);
      cur = it;
    }
  }
  out.push(cur);
  return out;
}

/**
 * Load all active practitioner availability docs, merge blocks into a single weekly map
 * (union across locations), and write to staffProfiles/{practitionerId}/availability/default.
 * Timezone is left unset so listPublicSlots uses clinic/settings timezone.
 */
export async function mirrorPractitionerAvailabilityToLegacy(
  clinicId: string,
  practitionerId: string
): Promise<void> {
  const availCol = db
    .collection("clinics")
    .doc(clinicId)
    .collection("practitioners")
    .doc(practitionerId)
    .collection("availability");

  const snap = await availCol.get();
  const perDay: Record<string, IntervalMin[]> = Object.fromEntries(
    DAY_KEYS.map((k) => [k, []])
  ) as Record<string, IntervalMin[]>;

  for (const doc of snap.docs) {
    const data = doc.data();
    if (data?.active === false) continue;

    const blocks = Array.isArray(data?.blocks) ? data.blocks : [];
    for (const b of blocks) {
      if (!b || typeof b !== "object") continue;
      const bookableOnline = b.bookableOnline !== false;
      if (!bookableOnline) continue;

      const dayOfWeek = Number(b.dayOfWeek);
      const dayKey = DOW_TO_DAY[dayOfWeek];
      if (!dayKey) continue;

      const startM = hmToMinutes(b.startTime);
      const endM = hmToMinutes(b.endTime);
      if (startM == null || endM == null || endM <= startM) continue;

      perDay[dayKey].push({ a: startM, b: endM });
    }
  }

  const weekly: Record<string, Array<{ start: string; end: string }>> =
    Object.fromEntries(
      DAY_KEYS.map((k) => [
        k,
        mergeIntervals(perDay[k]).map(({ a, b }) => ({
          start: minutesToHHmm(a),
          end: minutesToHHmm(b),
        })),
      ])
    );

  const hasAny = Object.values(weekly).some((arr) => arr.length > 0);
  const legacyRef = db.doc(
    `clinics/${clinicId}/staffProfiles/${practitionerId}/availability/default`
  );

  const now = admin.firestore.FieldValue.serverTimestamp();
  if (hasAny) {
    await legacyRef.set(
      {
        weekly,
        updatedAt: now,
        updatedByMirror: "mirrorPractitionerAvailabilityToLegacy",
      },
      { merge: true }
    );
    logger.info("mirrorPractitionerAvailabilityToLegacy: updated", {
      clinicId,
      practitionerId,
    });
  } else {
    // Do not delete: leave legacy doc unchanged so legacy-only data (setStaffAvailabilityDefault) is preserved.
    logger.info("mirrorPractitionerAvailabilityToLegacy: no active availability (legacy doc unchanged)", {
      clinicId,
      practitionerId,
    });
  }
}
