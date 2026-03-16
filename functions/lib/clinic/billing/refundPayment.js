"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.refundPayment = refundPayment;
const https_1 = require("firebase-functions/v2/https");
const audit_1 = require("../audit/audit");
const common_1 = require("./common");
async function refundPayment(request) {
    var _a, _b, _c, _d, _e, _f, _g;
    const uid = (0, common_1.requireAuthUid)(request);
    const data = (0, common_1.asObject)(request.data);
    const clinicId = (0, common_1.requireString)(data.clinicId, "clinicId", 2, 120);
    const paymentId = (0, common_1.requireString)(data.paymentId, "paymentId", 1, 120);
    const amount = (0, common_1.requireNonNegativeNumber)(data.amount, "amount");
    const reason = (0, common_1.requireString)(data.reason, "reason", 2, 500);
    if (amount <= 0)
        throw new https_1.HttpsError("invalid-argument", "amount must be > 0.");
    await (0, common_1.requireBillingRefund)(clinicId, uid);
    const paymentRef = (0, common_1.paymentsCol)(clinicId).doc(paymentId);
    const paymentSnap = await paymentRef.get();
    if (!paymentSnap.exists)
        throw new https_1.HttpsError("not-found", "Payment not found.");
    const payment = paymentSnap.data() || {};
    const original = (0, common_1.roundMoney)(Number((_a = payment.amount) !== null && _a !== void 0 ? _a : 0));
    const alreadyRefunded = (0, common_1.roundMoney)(Number((_b = payment.refundedAmount) !== null && _b !== void 0 ? _b : 0));
    const remaining = (0, common_1.roundMoney)(original - alreadyRefunded);
    if (amount > remaining) {
        throw new https_1.HttpsError("failed-precondition", "Refund amount exceeds remaining refundable amount.");
    }
    const invoiceId = String((_c = payment.invoiceId) !== null && _c !== void 0 ? _c : "").trim();
    if (!invoiceId)
        throw new https_1.HttpsError("failed-precondition", "Payment is missing invoiceId.");
    const invoiceRef = (0, common_1.invoicesCol)(clinicId).doc(invoiceId);
    const invoiceSnap = await invoiceRef.get();
    if (!invoiceSnap.exists)
        throw new https_1.HttpsError("not-found", "Invoice not found.");
    const invoice = invoiceSnap.data() || {};
    const invoiceTotal = (0, common_1.roundMoney)(Number((_d = invoice.total) !== null && _d !== void 0 ? _d : 0));
    const amountPaid = (0, common_1.roundMoney)(Number((_e = invoice.amountPaid) !== null && _e !== void 0 ? _e : 0));
    const nextAmountPaid = (0, common_1.roundMoney)(amountPaid - amount);
    const nextBalanceDue = (0, common_1.roundMoney)(Math.max(0, invoiceTotal - nextAmountPaid));
    const nextStatus = nextBalanceDue <= 0 ? "paid" : "issued";
    const paymentStatus = nextBalanceDue <= 0 ? "paid" : nextAmountPaid > 0 ? "partial" : "unpaid";
    const now = common_1.FV.serverTimestamp();
    const refundRef = (0, common_1.refundsCol)(clinicId).doc();
    await refundRef.set({
        paymentId,
        invoiceId,
        amount,
        reason,
        createdAt: now,
        createdByUid: uid,
    });
    await paymentRef.update({
        refundedAmount: (0, common_1.roundMoney)(alreadyRefunded + amount),
        updatedAt: now,
    });
    await invoiceRef.update({
        amountPaid: nextAmountPaid,
        balanceDue: nextBalanceDue,
        status: nextStatus,
        paymentStatus,
        updatedAt: now,
    });
    await (0, audit_1.writeAuditEvent)(refundRef.firestore, clinicId, {
        type: "billing.payment.refunded",
        actorUid: uid,
        patientId: String((_f = invoice.patientId) !== null && _f !== void 0 ? _f : "").trim() || undefined,
        appointmentId: String((_g = invoice.appointmentId) !== null && _g !== void 0 ? _g : "").trim() || undefined,
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
//# sourceMappingURL=refundPayment.js.map