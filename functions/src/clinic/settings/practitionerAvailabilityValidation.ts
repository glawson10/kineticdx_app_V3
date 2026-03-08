/**
 * Validation helpers for practitioner availability and overrides (Commit 31).
 */

import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";

export const MAX_BLOCKS = 20;
export const MAX_INTERVAL = 365;

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;
const TIME_HHMM = /^([01]?\d|2[0-3]):([0-5]\d)$/;

export type AvailabilityBlock = {
  dayOfWeek: number;
  startTime: string;
  endTime: string;
  bookableOnline?: boolean;
};

/**
 * Assert ISO date string (YYYY-MM-DD).
 */
export function assertIsoDate(val: unknown, field: string): string {
  if (val === null || val === undefined || (typeof val === "string" && val.trim() === "")) {
    throw new HttpsError("invalid-argument", `Missing required field: ${field}`);
  }
  const s = typeof val === "string" ? val.trim() : String(val);
  if (!ISO_DATE.test(s)) {
    throw new HttpsError("invalid-argument", `${field} must be ISO date (YYYY-MM-DD).`);
  }
  return s;
}

/**
 * Assert time string HH:mm (24h).
 */
export function assertTimeHHmm(val: unknown, field: string): string {
  if (val === null || val === undefined) {
    throw new HttpsError("invalid-argument", `Missing required field: ${field}`);
  }
  const s = typeof val === "string" ? val.trim() : String(val);
  if (!TIME_HHMM.test(s)) {
    throw new HttpsError("invalid-argument", `${field} must be time HH:mm (24h).`);
  }
  return s;
}

/**
 * Ensure no overlapping blocks on the same day.
 */
export function assertNoOverlaps(blocks: AvailabilityBlock[]): void {
  const byDay = new Map<number, AvailabilityBlock[]>();
  for (const b of blocks) {
    const list = byDay.get(b.dayOfWeek) ?? [];
    list.push(b);
    byDay.set(b.dayOfWeek, list);
  }
  for (const [, list] of byDay) {
    list.sort((a, b) => a.startTime.localeCompare(b.startTime));
    for (let i = 1; i < list.length; i++) {
      if (list[i].startTime < list[i - 1].endTime) {
        throw new HttpsError(
          "invalid-argument",
          `Overlapping blocks on day ${list[i].dayOfWeek}: ${list[i - 1].startTime}-${list[i - 1].endTime} and ${list[i].startTime}-${list[i].endTime}`
        );
      }
    }
  }
}

/**
 * Parse timestamp from client (seconds or milliseconds or Firestore Timestamp-like).
 */
export function parseTimestampInput(val: unknown, field: string): admin.firestore.Timestamp {
  if (val === null || val === undefined) {
    throw new HttpsError("invalid-argument", `Missing required field: ${field}`);
  }
  if (val && typeof (val as any).toMillis === "function") {
    return val as admin.firestore.Timestamp;
  }
  const n = typeof val === "number" ? val : parseInt(String(val), 10);
  if (!Number.isFinite(n)) {
    throw new HttpsError("invalid-argument", `${field} must be a valid timestamp.`);
  }
  const ms = n > 1e12 ? n : n * 1000;
  return admin.firestore.Timestamp.fromMillis(ms);
}
