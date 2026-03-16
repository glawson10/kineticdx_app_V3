/**
 * Pure duration rounding for pricing (Phase 6A). No Firestore dependency so tests can run without Firebase.
 */

export type DurationRoundingPolicy =
  | "actual"
  | "scheduled"
  | "roundUpTo"
  | "minimumBillable";

function roundMoney(n: number): number {
  return Math.round(n * 100) / 100;
}

/**
 * Rounds duration according to policy. Returns billable minutes.
 */
export function roundDuration(
  durationMinutes: number,
  policy: DurationRoundingPolicy | undefined,
  options: {
    roundUpToMinutes?: number;
    minimumBillableMinutes?: number;
    scheduledDurationMinutes?: number;
  } = {}
): number {
  const { roundUpToMinutes = 15, minimumBillableMinutes = 15, scheduledDurationMinutes } = options;
  if (!Number.isFinite(durationMinutes) || durationMinutes < 0) return 0;

  switch (policy) {
    case "scheduled":
      if (Number.isFinite(scheduledDurationMinutes) && scheduledDurationMinutes! >= 0) {
        return Math.round(scheduledDurationMinutes! * 100) / 100;
      }
      return roundMoney(durationMinutes);
    case "roundUpTo":
      if (roundUpToMinutes <= 0) return roundMoney(durationMinutes);
      const roundedUp = Math.ceil(durationMinutes / roundUpToMinutes) * roundUpToMinutes;
      return roundMoney(roundedUp);
    case "minimumBillable":
      const min = minimumBillableMinutes > 0 ? minimumBillableMinutes : 15;
      return roundMoney(Math.max(durationMinutes, min));
    case "actual":
    default:
      return roundMoney(durationMinutes);
  }
}
