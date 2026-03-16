"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createStripePaymentIntent = createStripePaymentIntent;
const common_1 = require("./common");
const createInvoicePaymentLink_1 = require("./createInvoicePaymentLink");
async function createStripePaymentIntent(request) {
    // Stripe integration is deferred; return payment-link token as fallback checkout handle.
    const res = await (0, createInvoicePaymentLink_1.createInvoicePaymentLink)(request);
    const data = (0, common_1.asObject)(request.data);
    return {
        ok: true,
        invoiceId: data.invoiceId,
        paymentLinkToken: res.token,
        paymentLinkExpiresAt: res.expiresAt,
        mode: "payment-link-fallback",
    };
}
//# sourceMappingURL=createStripePaymentIntent.js.map