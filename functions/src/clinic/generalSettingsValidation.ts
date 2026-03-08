/**
 * Validation helpers for clinic general settings (updateClinicProfile).
 */

import { HttpsError } from "firebase-functions/v2/https";

/**
 * Validate IANA-style timezone. Throws if invalid; otherwise no-op.
 * Accepts common forms (e.g. Europe/London, UTC, America/New_York).
 */
export function validateTimezone(tz: string): void {
  if (typeof tz !== "string" || tz.trim().length === 0) {
    throw new HttpsError("invalid-argument", "Timezone must be a non-empty string.");
  }
  if (tz.length > 64) {
    throw new HttpsError("invalid-argument", "Timezone must be at most 64 characters.");
  }
  // Basic sanity: allow letters, digits, /, _, +, -
  if (!/^[A-Za-z0-9/_+\-]+$/.test(tz.trim())) {
    throw new HttpsError("invalid-argument", "Timezone contains invalid characters.");
  }
}

/**
 * Simple email format check. Returns true if format looks valid.
 */
export function validateEmail(email: string): boolean {
  if (typeof email !== "string") return false;
  const s = email.trim();
  if (s.length === 0 || s.length > 254) return false;
  // RFC 5322 simplified
  const local = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return local.test(s);
}

/**
 * Validate session timeout minutes. Throws if invalid; null means use default/no limit.
 */
export function validateSessionTimeoutMinutes(n: number | null): void {
  if (n === null || n === undefined) return;
  if (typeof n !== "number" || !Number.isFinite(n)) {
    throw new HttpsError("invalid-argument", "Session timeout must be a number.");
  }
  if (n < 5 || n > 10080) {
    throw new HttpsError(
      "invalid-argument",
      "Session timeout must be between 5 and 10080 minutes (1 week)."
    );
  }
}

/**
 * Returns true if string looks like a valid URL (http/https or has a dot for domain).
 * Used for landingUrl, websiteUrl.
 */
export function looksLikeUrl(s: string): boolean {
  const t = s.trim();
  if (t.length === 0) return true;
  const lower = t.toLowerCase();
  if (lower.startsWith("http://") || lower.startsWith("https://")) return true;
  if (t.includes(" ") || t.length > 2048) return false;
  return t.includes(".");
}
