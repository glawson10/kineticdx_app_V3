import { getAgingBucket, type BucketKey } from "./agingBucket";
import {
  asObject,
  invoicesCol,
  requireAuthUid,
  requireBillingRead,
  requireString,
  roundMoney,
} from "./common";

export type { BucketKey } from "./agingBucket";
export { getAgingBucket } from "./agingBucket";

export async function getAgedReceivables(request: { auth?: { uid?: string }; data?: unknown }) {
  const uid = requireAuthUid(request);
  const data = asObject(request.data);
  const clinicId = requireString(data.clinicId, "clinicId", 2, 120);
  await requireBillingRead(clinicId, uid);

  const now = new Date();
  const buckets: Record<BucketKey, number> = {
    current: 0,
    days30: 0,
    days60: 0,
    days90plus: 0,
  };

  const snap = await invoicesCol(clinicId).get();
  for (const doc of snap.docs) {
    const d = doc.data() as Record<string, unknown>;
    const balance = Number(d.balanceDue ?? 0);
    const status = String(d.status ?? "");
    if (status === "void" || balance <= 0) continue;
    const dueRaw = (d.dueDate ?? d.dueAt) as { toDate?: () => Date } | undefined;
    const dueDate = dueRaw?.toDate ? dueRaw.toDate() : null;
    if (!dueDate) {
      buckets.current = roundMoney(buckets.current + balance);
      continue;
    }
    const bucket = getAgingBucket(now, dueDate);
    buckets[bucket] = roundMoney(buckets[bucket] + balance);
  }

  return { ok: true, clinicId, buckets };
}
