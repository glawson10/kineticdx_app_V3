import {
  asObject,
  invoicesCol,
  requireAuthUid,
  requireBillingRead,
  requireString,
  roundMoney,
} from "./common";

function startOfDay(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate(), 0, 0, 0, 0);
}

function endOfDay(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate(), 23, 59, 59, 999);
}

function startOfMonth(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), 1, 0, 0, 0, 0);
}

export async function getBillingSummary(request: { auth?: { uid?: string }; data?: unknown }) {
  const uid = requireAuthUid(request);
  const data = asObject(request.data);
  const clinicId = requireString(data.clinicId, "clinicId", 2, 120);
  await requireBillingRead(clinicId, uid);

  const now = new Date();
  const dayStart = startOfDay(now);
  const dayEnd = endOfDay(now);
  const monthStart = startOfMonth(now);

  const invoicesSnap = await invoicesCol(clinicId).get();
  let revenueToday = 0;
  let revenueMonth = 0;
  let outstanding = 0;

  const docs = invoicesSnap.docs;
  for (const doc of docs) {
    const d = doc.data() as Record<string, unknown>;
    const total = Number(d.total ?? 0);
    const balance = Number(d.balanceDue ?? 0);
    const status = String(d.status ?? "");
    const ts = d.updatedAt as { toDate?: () => Date } | undefined;
    const date = ts?.toDate ? ts.toDate() : null;

    if (status === "paid" && date) {
      if (date >= dayStart && date <= dayEnd) revenueToday = roundMoney(revenueToday + total);
      if (date >= monthStart) revenueMonth = roundMoney(revenueMonth + total);
    }
    if (status !== "void" && balance > 0) {
      outstanding = roundMoney(outstanding + balance);
    }
  }

  // Recent activity from same snapshot (no extra listeners): last 5 by updatedAt
  const sorted = [...docs].sort((a, b) => {
    const at = (a.data().updatedAt as { toDate?: () => Date } | undefined)?.toDate?.()?.getTime() ?? 0;
    const bt = (b.data().updatedAt as { toDate?: () => Date } | undefined)?.toDate?.()?.getTime() ?? 0;
    return bt - at;
  });
  const recentActivity = sorted.slice(0, 5).map((docRef) => {
    const d = docRef.data() as Record<string, unknown>;
    const status = String(d.status ?? "");
    const snap = d.issuedSnapshot as Record<string, unknown> | undefined;
    const numResult = snap?.numberingResult as Record<string, unknown> | undefined;
    const displayNumber = numResult?.displayNumber != null ? String(numResult.displayNumber) : (d.displayNumber != null ? String(d.displayNumber) : docRef.id.slice(0, 8));
    const ts = d.updatedAt as { toDate?: () => Date } | undefined;
    const updatedAt = ts?.toDate ? ts.toDate().toISOString() : new Date(0).toISOString();
    return { invoiceId: docRef.id, displayNumber, status, updatedAt };
  });

  return {
    ok: true,
    clinicId,
    revenueToday,
    revenueMonth,
    outstandingInvoices: outstanding,
    recentActivity,
  };
}
