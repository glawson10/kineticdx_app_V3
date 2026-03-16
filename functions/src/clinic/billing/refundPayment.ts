import { HttpsError } from "firebase-functions/v2/https";
import { writeAuditEvent } from "../audit/audit";
import {
  FV,
  asObject,
  invoicesCol,
  paymentsCol,
  refundsCol,
  requireAuthUid,
  requireBillingRefund,
  requireNonNegativeNumber,
  requireString,
  roundMoney,
} from "./common";

export async function refundPayment(request: { auth?: { uid?: string }; data?: unknown }) {
  const uid = requireAuthUid(request);
  const data = asObject(request.data);
  const clinicId = requireString(data.clinicId, "clinicId", 2, 120);
  const paymentId = requireString(data.paymentId, "paymentId", 1, 120);
  const amount = requireNonNegativeNumber(data.amount, "amount");
  const reason = requireString(data.reason, "reason", 2, 500);
  if (amount <= 0) throw new HttpsError("invalid-argument", "amount must be > 0.");
  await requireBillingRefund(clinicId, uid);

  const paymentRef = paymentsCol(clinicId).doc(paymentId);
  const paymentSnap = await paymentRef.get();
  if (!paymentSnap.exists) throw new HttpsError("not-found", "Payment not found.");
  const payment = paymentSnap.data() || {};
  const original = roundMoney(Number(payment.amount ?? 0));
  const alreadyRefunded = roundMoney(Number(payment.refundedAmount ?? 0));
  const remaining = roundMoney(original - alreadyRefunded);
  if (amount > remaining) {
    throw new HttpsError("failed-precondition", "Refund amount exceeds remaining refundable amount.");
  }

  const invoiceId = String(payment.invoiceId ?? "").trim();
  if (!invoiceId) throw new HttpsError("failed-precondition", "Payment is missing invoiceId.");
  const invoiceRef = invoicesCol(clinicId).doc(invoiceId);
  const invoiceSnap = await invoiceRef.get();
  if (!invoiceSnap.exists) throw new HttpsError("not-found", "Invoice not found.");
  const invoice = invoiceSnap.data() || {};

  const invoiceTotal = roundMoney(Number(invoice.total ?? 0));
  const amountPaid = roundMoney(Number(invoice.amountPaid ?? 0));
  const nextAmountPaid = roundMoney(amountPaid - amount);
  const nextBalanceDue = roundMoney(Math.max(0, invoiceTotal - nextAmountPaid));
  const nextStatus = nextBalanceDue <= 0 ? "paid" : "issued";
  const paymentStatus = nextBalanceDue <= 0 ? "paid" : nextAmountPaid > 0 ? "partial" : "unpaid";

  const now = FV.serverTimestamp();
  const refundRef = refundsCol(clinicId).doc();
  await refundRef.set({
    paymentId,
    invoiceId,
    amount,
    reason,
    createdAt: now,
    createdByUid: uid,
  });
  await paymentRef.update({
    refundedAmount: roundMoney(alreadyRefunded + amount),
    updatedAt: now,
  });
  await invoiceRef.update({
    amountPaid: nextAmountPaid,
    balanceDue: nextBalanceDue,
    status: nextStatus,
    paymentStatus,
    updatedAt: now,
  });

  await writeAuditEvent(refundRef.firestore, clinicId, {
    type: "billing.payment.refunded",
    actorUid: uid,
    patientId: String(invoice.patientId ?? "").trim() || undefined,
    appointmentId: String(invoice.appointmentId ?? "").trim() || undefined,
    metadata: {
      refundId: refundRef.id,
      paymentId,
      invoiceId,
      amount,
      reason,
      amountPaidBefore: amountPaid,
      amountPaidAfter: nextAmountPaid,
      balanceDue: nextBalanceDue,
    },
  });
  return { ok: true, refundId: refundRef.id, invoiceId, balanceDue: nextBalanceDue };
}
