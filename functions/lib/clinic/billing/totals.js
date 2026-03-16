"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.computeInvoiceTotals = computeInvoiceTotals;
const https_1 = require("firebase-functions/v2/https");
function roundMoney(n) {
    return Math.round(n * 100) / 100;
}
function assertFiniteNumber(value, label) {
    const n = Number(value);
    if (!Number.isFinite(n))
        throw new https_1.HttpsError("invalid-argument", `${label} must be a finite number.`);
    return n;
}
function normalizeLine(line, idx, taxInclusive) {
    var _a, _b, _c;
    const itemId = String((_a = line.itemId) !== null && _a !== void 0 ? _a : "").trim();
    const description = String((_b = line.description) !== null && _b !== void 0 ? _b : "").trim();
    const type = String((_c = line.type) !== null && _c !== void 0 ? _c : "");
    if (!(type === "service" || type === "product")) {
        throw new https_1.HttpsError("invalid-argument", `lineItems[${idx}].type must be service or product.`);
    }
    if (!itemId)
        throw new https_1.HttpsError("invalid-argument", `lineItems[${idx}].itemId is required.`);
    if (!description)
        throw new https_1.HttpsError("invalid-argument", `lineItems[${idx}].description is required.`);
    const quantity = assertFiniteNumber(line.quantity, `lineItems[${idx}].quantity`);
    const unitPrice = assertFiniteNumber(line.unitPrice, `lineItems[${idx}].unitPrice`);
    const taxRate = assertFiniteNumber(line.taxRate, `lineItems[${idx}].taxRate`);
    const discount = line.discount === undefined ? 0 : assertFiniteNumber(line.discount, `lineItems[${idx}].discount`);
    if (quantity <= 0)
        throw new https_1.HttpsError("invalid-argument", `lineItems[${idx}].quantity must be > 0.`);
    if (unitPrice < 0)
        throw new https_1.HttpsError("invalid-argument", `lineItems[${idx}].unitPrice must be >= 0.`);
    if (taxRate < 0 || taxRate > 100) {
        throw new https_1.HttpsError("invalid-argument", `lineItems[${idx}].taxRate must be between 0 and 100.`);
    }
    if (discount < 0)
        throw new https_1.HttpsError("invalid-argument", `lineItems[${idx}].discount must be >= 0.`);
    let lineNet;
    let taxAmount;
    let total;
    let clampedDiscount;
    if (taxInclusive) {
        const totalInclusive = roundMoney(quantity * unitPrice);
        clampedDiscount = Math.min(roundMoney(discount), totalInclusive);
        const afterDiscount = roundMoney(totalInclusive - clampedDiscount);
        if (taxRate === 0) {
            lineNet = afterDiscount;
            taxAmount = 0;
            total = afterDiscount;
        }
        else {
            lineNet = roundMoney(afterDiscount / (1 + taxRate / 100));
            taxAmount = roundMoney(afterDiscount - lineNet);
            total = afterDiscount;
        }
    }
    else {
        const gross = roundMoney(quantity * unitPrice);
        clampedDiscount = Math.min(roundMoney(discount), gross);
        lineNet = roundMoney(gross - clampedDiscount);
        taxAmount = roundMoney(lineNet * (taxRate / 100));
        total = roundMoney(lineNet + taxAmount);
    }
    if (total < 0)
        throw new https_1.HttpsError("invalid-argument", `lineItems[${idx}] total cannot be negative.`);
    const out = {
        type,
        itemId,
        description,
        quantity: roundMoney(quantity),
        unitPrice: roundMoney(unitPrice),
        taxRate: roundMoney(taxRate),
        discount: clampedDiscount,
        lineNet,
        taxAmount,
        total,
    };
    if (line.pricingSource !== undefined)
        out.pricingSource = line.pricingSource;
    if (line.pricingSourceSnapshot !== undefined)
        out.pricingSourceSnapshot = line.pricingSourceSnapshot;
    return out;
}
function computeInvoiceTotals(lineItems, invoiceDiscount = 0, options = {}) {
    if (!Array.isArray(lineItems) || lineItems.length === 0) {
        throw new https_1.HttpsError("invalid-argument", "lineItems is required.");
    }
    const taxInclusive = options.taxInclusive === true;
    const computed = lineItems.map((line, idx) => normalizeLine(line, idx, taxInclusive));
    const preInvoiceDiscountSubtotal = roundMoney(computed.reduce((acc, line) => acc + line.lineNet, 0));
    const lineDiscountTotal = roundMoney(computed.reduce((acc, line) => { var _a; return acc + ((_a = line.discount) !== null && _a !== void 0 ? _a : 0); }, 0));
    const safeInvoiceDiscount = roundMoney(Math.max(0, Number(invoiceDiscount || 0)));
    const invoiceLevelDiscount = Math.min(safeInvoiceDiscount, preInvoiceDiscountSubtotal);
    const subtotal = roundMoney(preInvoiceDiscountSubtotal - invoiceLevelDiscount);
    const effectiveDiscount = roundMoney(lineDiscountTotal + invoiceLevelDiscount);
    const ratio = preInvoiceDiscountSubtotal > 0 ? (subtotal / preInvoiceDiscountSubtotal) : 0;
    let taxTotal = 0;
    const rescaledLines = computed.map((line) => {
        const rescaledNet = roundMoney(line.lineNet * ratio);
        const taxAmount = taxInclusive
            ? roundMoney(line.taxAmount * ratio)
            : roundMoney(rescaledNet * (line.taxRate / 100));
        taxTotal = roundMoney(taxTotal + taxAmount);
        return { ...line, lineNet: rescaledNet, taxAmount, total: roundMoney(rescaledNet + taxAmount) };
    });
    const total = roundMoney(subtotal + taxTotal);
    if (subtotal < 0 || taxTotal < 0 || total < 0) {
        throw new https_1.HttpsError("invalid-argument", "Invoice totals cannot be negative.");
    }
    return {
        lineItems: rescaledLines,
        subtotal,
        discountTotal: effectiveDiscount,
        taxTotal,
        total,
    };
}
//# sourceMappingURL=totals.js.map