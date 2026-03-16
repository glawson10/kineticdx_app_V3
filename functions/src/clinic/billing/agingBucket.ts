/**
 * Pure function: returns the aging bucket for a due date relative to now.
 * Used by getAgedReceivables and by tests without requiring Firestore.
 */

export type BucketKey = "current" | "days30" | "days60" | "days90plus";

export function getAgingBucket(now: Date, dueDate: Date): BucketKey {
  const ageDays = Math.floor((now.getTime() - dueDate.getTime()) / 86_400_000);
  if (ageDays <= 0) return "current";
  if (ageDays <= 30) return "days30";
  if (ageDays <= 60) return "days60";
  return "days90plus";
}
