"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.createInvoice = createInvoice;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const audit_1 = require("../audit/audit");
const common_1 = require("./common");
const totals_1 = require("./totals");
const DEFAULT_NEXT_INVOICE_NUMBER = 1;
const DEFAULT_DUE_DAYS = 30;
const DEFAULT_CURRENCY = "USD";
function parseStatus(value) {
    const s = String(value !== null && value !== void 0 ? value : "draft").trim();
    if (s === "draft" || s === "issued" || s === "paid" || s === "void")
        return s;
    throw new https_1.HttpsError("invalid-argument", "status must be draft, issued, paid, or void.");
}
function resolveCurrency(settingsCurrency, clinicData) {
    var _a, _b;
    const s = settingsCurrency != null ? String(settingsCurrency).trim() : "";
    if (s)
        return s;
    const profile = clinicData === null || clinicData === void 0 ? void 0 : clinicData.profile;
    const fromProfile = (_a = profile === null || profile === void 0 ? void 0 : profile.currency) !== null && _a !== void 0 ? _a : profile === null || profile === void 0 ? void 0 : profile.currencyCode;
    const fromRoot = (_b = clinicData === null || clinicData === void 0 ? void 0 : clinicData.currencyCode) !== null && _b !== void 0 ? _b : clinicData === null || clinicData === void 0 ? void 0 : clinicData.currency;
    const c = fromProfile != null ? String(fromProfile).trim() : (fromRoot != null ? String(fromRoot).trim() : "");
    return c || DEFAULT_CURRENCY;
}
async function createInvoice(request) {
    var _a, _b, _c, _d;
    const uid = (0, common_1.requireAuthUid)(request);
    const data = (0, common_1.asObject)(request.data);
    const clinicId = (0, common_1.requireString)(data.clinicId, "clinicId", 2, 120);
    await (0, common_1.requireBillingWrite)(clinicId, uid);
    const patientId = (0, common_1.requireString)(data.patientId, "patientId", 1, 120);
    const appointmentIdRaw = String((_a = data.appointmentId) !== null && _a !== void 0 ? _a : "").trim();
    const appointmentId = appointmentIdRaw.length > 0 ? appointmentIdRaw : null;
    const inputItems = (_b = data.lineItems) !== null && _b !== void 0 ? _b : [];
    const invoiceDiscount = Number((_c = data.invoiceDiscount) !== null && _c !== void 0 ? _c : 0);
    const status = parseStatus((_d = data.status) !== null && _d !== void 0 ? _d : "draft");
    const settingsRef = (0, common_1.billingSettingsGeneralRef)(clinicId);
    const clinicRef = common_1.db.doc(`clinics/${clinicId}`);
    const invoicesRef = (0, common_1.invoicesCol)(clinicId);
    let invoiceId;
    let totalsOut = {
        total: 0,
        taxTotal: 0,
        discountTotal: 0,
        lineItems: [],
    };
    await common_1.db.runTransaction(async (tx) => {
        const [settingsSnap, clinicSnap] = await Promise.all([
            tx.get(settingsRef),
            tx.get(clinicRef),
        ]);
        const settings = settingsSnap.exists ? (settingsSnap.data() || {}) : {};
        const clinicData = clinicSnap.exists ? (clinicSnap.data() || {}) : null;
        const taxInclusive = settings.taxInclusivePricing === true;
        const totals = (0, totals_1.computeInvoiceTotals)(inputItems, invoiceDiscount, { taxInclusive });
        totalsOut = totals;
        const invoicePrefix = (settings.invoicePrefix != null ? String(settings.invoicePrefix) : "").trim();
        const nextNum = typeof settings.nextInvoiceNumber === "number" && Number.isInteger(settings.nextInvoiceNumber) && settings.nextInvoiceNumber >= 0
            ? settings.nextInvoiceNumber
            : DEFAULT_NEXT_INVOICE_NUMBER;
        const defaultDueDays = typeof settings.defaultDueDays === "number" && Number.isInteger(settings.defaultDueDays) && settings.defaultDueDays >= 0
            ? Math.min(365, settings.defaultDueDays)
            : DEFAULT_DUE_DAYS;
        const currency = resolveCurrency(settings.currency, clinicData);
        const nowDate = new Date();
        const dueDate = admin.firestore.Timestamp.fromMillis(nowDate.getTime() + defaultDueDays * 86400000);
        const displayNumber = invoicePrefix + nextNum;
        const ref = invoicesRef.doc();
        invoiceId = ref.id;
        const doc = {
            patientId,
            appointmentId,
            status: status === "paid" ? "issued" : status,
            lineItems: totals.lineItems,
            subtotal: totals.subtotal,
            discountTotal: totals.discountTotal,
            taxTotal: totals.taxTotal,
            total: totals.total,
            amountPaid: 0,
            balanceDue: totals.total,
            paymentStatus: "unpaid",
            dueDate,
            displayNumber,
            currency,
            createdAt: common_1.FV.serverTimestamp(),
            updatedAt: common_1.FV.serverTimestamp(),
        };
        tx.set(ref, doc);
        tx.set(settingsRef, { nextInvoiceNumber: nextNum + 1, updatedAt: common_1.FV.serverTimestamp(), updatedByUid: uid }, { merge: true });
    });
    const ref = (0, common_1.invoicesCol)(clinicId).doc(invoiceId);
    await (0, audit_1.writeAuditEvent)(ref.firestore, clinicId, {
        type: "billing.invoice.created",
        actorUid: uid,
        patientId,
        appointmentId: appointmentId !== null && appointmentId !== void 0 ? appointmentId : undefined,
        metadata: {
            invoiceId,
            status: status === "paid" ? "issued" : status,
            total: totalsOut.total,
            taxTotal: totalsOut.taxTotal,
            discountTotal: totalsOut.discountTotal,
            lineItemCount: totalsOut.lineItems.length,
        },
    });
    return { ok: true, invoiceId };
}
//# sourceMappingURL=createInvoice.js.map