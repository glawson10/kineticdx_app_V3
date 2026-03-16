import { asObject } from "./common";
import { createInvoicePaymentLink } from "./createInvoicePaymentLink";

export async function createStripePaymentIntent(request: { auth?: { uid?: string }; data?: unknown }) {
  // Stripe integration is deferred; return payment-link token as fallback checkout handle.
  const res = await createInvoicePaymentLink(request);
  const data = asObject(request.data);
  return {
    ok: true,
    invoiceId: data.invoiceId,
    paymentLinkToken: res.token,
    paymentLinkExpiresAt: res.expiresAt,
    mode: "payment-link-fallback",
  };
}
