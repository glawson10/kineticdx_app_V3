import { randomUUID } from "crypto";
import { HttpsError } from "firebase-functions/v2/https";
import {
  FV,
  asObject,
  invoicesCol,
  requireAuthUid,
  requireBillingWrite,
  requireString,
} from "./common";

export async function createInvoicePaymentLink(request: { auth?: { uid?: string }; data?: unknown }) {
  const uid = requireAuthUid(request);
  const data = asObject(request.data);
  const clinicId = requireString(data.clinicId, "clinicId", 2, 120);
  const invoiceId = requireString(data.invoiceId, "invoiceId", 1, 120);
  await requireBillingWrite(clinicId, uid);

  const ref = invoicesCol(clinicId).doc(invoiceId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Invoice not found.");

  const token = randomUUID().replace(/-/g, "");
  const expiresAt = new Date(Date.now() + 1000 * 60 * 60 * 24 * 7); // 7 days
  await ref.update({
    paymentLinkToken: token,
    paymentLinkExpiresAt: expiresAt,
    updatedAt: FV.serverTimestamp(),
  });
  return { ok: true, invoiceId, token, expiresAt };
}
