/**
 * Commit 48: Single helper to load and normalize booking rules from
 * clinics/{clinicId}/public/config/publicBooking/config.
 * Reused by listPublicSlots and onBookingRequestCreate to prevent drift.
 */
import * as admin from "firebase-admin";

function safeStr(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

export type PublicBookingRules = {
  timezone: string;
  minNoticeMinutes: number;
  maxAdvanceDays: number;
  requireEmail: boolean;
  requirePhone: boolean;
  allowNewPatients: boolean;
};

const DEFAULT_RULES: PublicBookingRules = {
  timezone: "Europe/Prague",
  minNoticeMinutes: 0,
  maxAdvanceDays: 90,
  requireEmail: true,
  requirePhone: false,
  allowNewPatients: true,
};

/**
 * Normalize booking rules from a config doc data object (so listPublicSlots
 * can pass doc.data() and reuse the same logic).
 */
export function normalizeBookingRulesFromConfigDoc(data: unknown): PublicBookingRules {
  if (!data || typeof data !== "object") return { ...DEFAULT_RULES };
  const d = data as Record<string, unknown>;
  const jurisdiction =
    d?.jurisdiction && typeof d.jurisdiction === "object"
      ? (d.jurisdiction as Record<string, unknown>)
      : {};
  const rules =
    d?.bookingRules && typeof d.bookingRules === "object"
      ? (d.bookingRules as Record<string, unknown>)
      : {};
  const timezone = safeStr(jurisdiction.timezone) || DEFAULT_RULES.timezone;
  const minNoticeMinutes =
    typeof rules.minNoticeMinutes === "number" && rules.minNoticeMinutes >= 0
      ? rules.minNoticeMinutes
      : DEFAULT_RULES.minNoticeMinutes;
  const maxAdvanceDays =
    typeof rules.maxAdvanceDays === "number" &&
    rules.maxAdvanceDays >= 7 &&
    rules.maxAdvanceDays <= 365
      ? rules.maxAdvanceDays
      : DEFAULT_RULES.maxAdvanceDays;
  const requireEmail =
    rules.requireEmail === true || rules.requireEmail !== false;
  const requirePhone = rules.requirePhone === true;
  const allowNewPatients =
    rules.allowNewPatients === true || rules.allowNewPatients !== false;
  return {
    timezone,
    minNoticeMinutes,
    maxAdvanceDays,
    requireEmail,
    requirePhone,
    allowNewPatients,
  };
}

const CONFIG_DOC_PATH = (clinicId: string) =>
  `clinics/${clinicId}/public/config/publicBooking/config`;

/**
 * Load and normalize booking rules from the public config doc.
 */
export async function loadPublicBookingRules(
  db: admin.firestore.Firestore,
  clinicId: string
): Promise<PublicBookingRules> {
  const snap = await db.doc(CONFIG_DOC_PATH(clinicId)).get();
  if (!snap.exists || !snap.data()) return { ...DEFAULT_RULES };
  return normalizeBookingRulesFromConfigDoc(snap.data());
}
