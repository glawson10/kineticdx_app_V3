"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.issueCreditNote = issueCreditNote;
const https_1 = require("firebase-functions/v2/https");
const audit_1 = require("../audit/audit");
const common_1 = require("./common");
async function issueCreditNote(request) {
    var _a, _b, _c, _d, _e, _f;
    const uid = (0, common_1.requireAuthUid)(request);
    const data = (0, common_1.asObject)(request.data);
    const clinicId = (0, common_1.requireString)(data.clinicId, "clinicId", 2, 120);
    const invoiceId = (0, common_1.requireString)(data.invoiceId, "invoiceId", 1, 120);
    const amount = (0, common_1.requireNonNegativeNumber)(data.amount, "amount");
    const reason = (0, common_1.requireString)(data.reason, "reason", 2, 500);
    if (amount <= 0)
        throw new https_1.HttpsError("invalid-argument", "amount must be > 0.");
    await (0, common_1.requireBillingWrite)(clinicId, uid);
    const invoiceRef = (0, common_1.invoicesCol)(clinicId).doc(invoiceId);
    const invoiceSnap = await invoiceRef.get();
    if (!invoiceSnap.exists)
        throw new https_1.HttpsError("not-found", "Invoice not found.");
    const invoice = invoiceSnap.data() || {};
    const total = (0, common_1.roundMoney)(Number((_a = invoice.total) !== null && _a !== void 0 ? _a : 0));
    const currentCredit = (0, common_1.roundMoney)(Number((_b = invoice.creditTotal) !== null && _b !== void 0 ? _b : 0));
    const currentPaid = (0, common_1.roundMoney)(Number((_c = invoice.amountPaid) !== null && _c !== void 0 ? _c : 0));
    const nextCredit = (0, common_1.roundMoney)(currentCredit + amount);
    if (nextCredit > total) {
        throw new https_1.HttpsError("failed-precondition", "Credit total cannot exceed invoice total.");
    }
    const nextTotal = (0, common_1.roundMoney)(total - amount);
    const balanceDue = Math.max(0, (0, common_1.roundMoney)(nextTotal - currentPaid));
    const nextStatus = balanceDue <= 0 ? "paid" : String((_d = invoice.status) !== null && _d !== void 0 ? _d : "issued");
    const paymentStatus = balanceDue <= 0 ? "paid" : currentPaid > 0 ? "partial" : "unpaid";
    const now = common_1.FV.serverTimestamp();
    const noteRef = (0, common_1.creditNotesCol)(clinicId).doc();
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
    await (0, audit_1.writeAuditEvent)(noteRef.firestore, clinicId, {
        type: "billing.creditNote.issued",
        actorUid: uid,
        patientId: String((_e = invoice.patientId) !== null && _e !== void 0 ? _e : "").trim() || undefined,
        appointmentId: String((_f = invoice.appointmentId) !== null && _f !== void 0 ? _f : "").trim() || undefined,
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
//# sourceMappingURL=issueCreditNote.js.map