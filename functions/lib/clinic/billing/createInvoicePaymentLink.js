"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createInvoicePaymentLink = createInvoicePaymentLink;
const crypto_1 = require("crypto");
const https_1 = require("firebase-functions/v2/https");
const common_1 = require("./common");
async function createInvoicePaymentLink(request) {
    const uid = (0, common_1.requireAuthUid)(request);
    const data = (0, common_1.asObject)(request.data);
    const clinicId = (0, common_1.requireString)(data.clinicId, "clinicId", 2, 120);
    const invoiceId = (0, common_1.requireString)(data.invoiceId, "invoiceId", 1, 120);
    await (0, common_1.requireBillingWrite)(clinicId, uid);
    const ref = (0, common_1.invoicesCol)(clinicId).doc(invoiceId);
    const snap = await ref.get();
    if (!snap.exists)
        throw new https_1.HttpsError("not-found", "Invoice not found.");
    const token = (0, crypto_1.randomUUID)().replace(/-/g, "");
    const expiresAt = new Date(Date.now() + 1000 * 60 * 60 * 24 * 7); // 7 days
    await ref.update({
        paymentLinkToken: token,
        paymentLinkExpiresAt: expiresAt,
        updatedAt: common_1.FV.serverTimestamp(),
    });
    return { ok: true, invoiceId, token, expiresAt };
}
//# sourceMappingURL=createInvoicePaymentLink.js.map