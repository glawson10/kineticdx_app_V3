"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.recordPayment = recordPayment;
const https_1 = require("firebase-functions/v2/https");
const audit_1 = require("../audit/audit");
const common_1 = require("./common");
function paymentStatus(amountPaid, total) {
    if (amountPaid <= 0)
        return "unpaid";
    if (amountPaid < total)
        return "partial";
    return "paid";
}
async function recordPayment(request) {
    var _a, _b, _c, _d, _e, _f;
    const uid = (0, common_1.requireAuthUid)(request);
    const data = (0, common_1.asObject)(request.data);
    const clinicId = (0, common_1.requireString)(data.clinicId, "clinicId", 2, 120);
    const invoiceId = (0, common_1.requireString)(data.invoiceId, "invoiceId", 1, 120);
    const paymentTypeId = (0, common_1.requireString)(data.paymentTypeId, "paymentTypeId", 1, 120);
    const amount = (0, common_1.requireNonNegativeNumber)(data.amount, "amount");
    if (amount <= 0)
        throw new https_1.HttpsError("invalid-argument", "amount must be > 0.");
    await (0, common_1.requireBillingWrite)(clinicId, uid);
    const paymentTypeSnap = await (0, common_1.paymentTypesCol)(clinicId).doc(paymentTypeId).get();
    if (!paymentTypeSnap.exists)
        throw new https_1.HttpsError("invalid-argument", "paymentTypeId not found.");
    const invoiceRef = (0, common_1.invoicesCol)(clinicId).doc(invoiceId);
    const invoiceSnap = await invoiceRef.get();
    if (!invoiceSnap.exists)
        throw new https_1.HttpsError("not-found", "Invoice not found.");
    const invoice = invoiceSnap.data() || {};
    const total = (0, common_1.roundMoney)(Number((_a = invoice.total) !== null && _a !== void 0 ? _a : 0));
    const currentPaid = (0, common_1.roundMoney)(Number((_b = invoice.amountPaid) !== null && _b !== void 0 ? _b : 0));
    const remaining = (0, common_1.roundMoney)(total - currentPaid);
    if (amount > remaining) {
        throw new https_1.HttpsError("failed-precondition", "Payment amount exceeds invoice balance.");
    }
    const now = common_1.FV.serverTimestamp();
    const paymentRef = (0, common_1.paymentsCol)(clinicId).doc();
    const nextPaid = (0, common_1.roundMoney)(currentPaid + amount);
    const nextBalance = (0, common_1.roundMoney)(total - nextPaid);
    const nextPaymentStatus = paymentStatus(nextPaid, total);
    const nextStatus = nextBalance <= 0 ? "paid" :
        String((_c = invoice.status) !== null && _c !== void 0 ? _c : "draft") === "draft" ? "issued" :
            String((_d = invoice.status) !== null && _d !== void 0 ? _d : "issued");
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
    await (0, audit_1.writeAuditEvent)(paymentRef.firestore, clinicId, {
        type: "billing.payment.recorded",
        actorUid: uid,
        patientId: String((_e = invoice.patientId) !== null && _e !== void 0 ? _e : "").trim() || undefined,
        appointmentId: String((_f = invoice.appointmentId) !== null && _f !== void 0 ? _f : "").trim() || undefined,
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
//# sourceMappingURL=recordPayment.js.map