import { HttpsError } from "firebase-functions/v2/https";
import { writeAuditEvent } from "../audit/audit";
import {
  FV,
  asObject,
  paymentTypesCol,
  paymentsCol,
  invoicesCol,
  requireAuthUid,
  requireBillingWrite,
  requireNonNegativeNumber,
  requireString,
  roundMoney,
} from "./common";

function paymentStatus(amountPaid: number, total: number): "unpaid" | "partial" | "paid" {
  if (amountPaid <= 0) return "unpaid";
  if (amountPaid < total) return "partial";
  return "paid";
}

export async function recordPayment(request: { auth?: { uid?: string }; data?: unknown }) {
  const uid = requireAuthUid(request);
  const data = asObject(request.data);
  const clinicId = requireString(data.clinicId, "clinicId", 2, 120);
  const invoiceId = requireString(data.invoiceId, "invoiceId", 1, 120);
  const paymentTypeId = requireString(data.paymentTypeId, "paymentTypeId", 1, 120);
  const amount = requireNonNegativeNumber(data.amount, "amount");
  if (amount <= 0) throw new HttpsError("invalid-argument", "amount must be > 0.");

  await requireBillingWrite(clinicId, uid);
  const paymentTypeSnap = await paymentTypesCol(clinicId).doc(paymentTypeId).get();
  if (!paymentTypeSnap.exists) throw new HttpsError("invalid-argument", "paymentTypeId not found.");

  const invoiceRef = invoicesCol(clinicId).doc(invoiceId);
  const invoiceSnap = await invoiceRef.get();
  if (!invoiceSnap.exists) throw new HttpsError("not-found", "Invoice not found.");
  const invoice = invoiceSnap.data() || {};
  const total = roundMoney(Number(invoice.total ?? 0));
  const currentPaid = roundMoney(Number(invoice.amountPaid ?? 0));
  const remaining = roundMoney(total - currentPaid);
  if (amount > remaining) {
    throw new HttpsError("failed-precondition", "Payment amount exceeds invoice balance.");
  }

  const now = FV.serverTimestamp();
  const paymentRef = paymentsCol(clinicId).doc();
  const nextPaid = roundMoney(currentPaid + amount);
  const nextBalance = roundMoney(total - nextPaid);
  const nextPaymentStatus = paymentStatus(nextPaid, total);
  const nextStatus =
    nextBalance <= 0 ? "paid" :
    String(invoice.status ?? "draft") === "draft" ? "issued" :
    String(invoice.status ?? "issued");

  await paymentRef.set({
    invoiceId,
    amount,
    paymentTypeId,
    createdAt: now,
    createdByUid: uid,
  });

  await invoiceRef.update({
    amountPaid: nextPaid,
    balanceDue: nextBalance,
    paymentStatus: nextPaymentStatus,
    status: nextStatus,
    updatedAt: now,
  });

  await writeAuditEvent(paymentRef.firestore, clinicId, {
    type: "billing.payment.recorded",
    actorUid: uid,
    patientId: String(invoice.patientId ?? "").trim() || undefined,
    appointmentId: String(invoice.appointmentId ?? "").trim() || undefined,
    metadata: {
      paymentId: paymentRef.id,
      invoiceId,
      amount,
      paymentTypeId,
      amountPaid: nextPaid,
      balanceDue: nextBalance,
      status: nextStatus,
    },
  });
  return { ok: true, paymentId: paymentRef.id, invoiceId, balanceDue: nextBalance };
}
