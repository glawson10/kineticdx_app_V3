/**
 * Paths for projection targets (public mirror docs).
 * Private sources are in clinic/paths.ts (e.g. settingsPublicBooking).
 */

/**
 * Minimal public booking config doc (Commit 16 schema v1).
 * Written by projection trigger only; clients read-only.
 */
export function publicBookingConfigDocPath(clinicId: string): string {
  return `clinics/${clinicId}/public/config/publicBooking/config`;
}
