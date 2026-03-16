import { HttpsError } from "firebase-functions/v2/https";
import { writeAuditEvent } from "../audit/audit";
import {
  FV,
  asObject,
  creditNotesCol,
  invoicesCol,
  requireAuthUid,
  requireBillingWrite,
  requireNonNegativeNumber,
  requireString,
  roundMoney,
} from "./common";

export async function issueCreditNote(request: { auth?: { uid?: string }; data?: unknown }) {
  const uid = requireAuthUid(request);
  const data = asObject(request.data);
  const clinicId = requireString(data.clinicId, "clinicId", 2, 120);
  const invoiceId = requireString(data.invoiceId, "invoiceId", 1, 120);
  const amount = requireNonNegativeNumber(data.amount, "amount");
  const reason = requireString(data.reason, "reason", 2, 500);
  if (amount <= 0) throw new HttpsError("invalid-argument", "amount must be > 0.");

  await requireBillingWrite(clinicId, uid);
  const invoiceRef = invoicesCol(clinicId).doc(invoiceId);
  const invoiceSnap = await invoiceRef.get();
  if (!invoiceSnap.exists) throw new HttpsError("not-found", "Invoice not found.");
  const invoice = invoiceSnap.data() || {};

  const total = roundMoney(Number(invoice.total ?? 0));
  const currentCredit = roundMoney(Number(invoice.creditTotal ?? 0));
  const currentPaid = roundMoney(Number(invoice.amountPaid ?? 0));
  const nextCredit = roundMoney(currentCredit + amount);
  if (nextCredit > total) {
    throw new HttpsError("failed-precondition", "Credit total cannot exceed invoice total.");
  }

  const nextTotal = roundMoney(total - amount);
  const balanceDue = Math.max(0, roundMoney(nextTotal - currentPaid));
  const nextStatus = balanceDue <= 0 ? "paid" : String(invoice.status ?? "issued");
  const paymentStatus = balanceDue <= 0 ? "paid" : currentPaid > 0 ? "partial" : "unpaid";

  const now = FV.serverTimestamp();
  const noteRef = creditNotesCol(clinicId).doc();
  await noteRef.set({
    invoiceId,
    amount,
    reason,
    createdAt: now,
    createdByUid: uid,
  });

  await invoiceRef.update({
    total: nextTotal,
    creditTotal: nextCredit,
    balanceDue,
    status: nextStatus,
    paymentStatus,
    updatedAt: now,
  });

  await writeAuditEvent(noteRef.firestore, clinicId, {
    type: "billing.creditNote.issued",
    actorUid: uid,
    patientId: String(invoice.patientId ?? "").trim() || undefined,
    appointmentId: String(invoice.appointmentId ?? "").trim() || undefined,
    metadata: {
      creditNoteId: noteRef.id,
      invoiceId,
      amount,
      reason,
      totalBefore: total,
      totalAfter: nextTotal,
      balanceDue,
    },
  });
  return { ok: true, creditNoteId: noteRef.id, invoiceId, total: nextTotal, balanceDue };
}
