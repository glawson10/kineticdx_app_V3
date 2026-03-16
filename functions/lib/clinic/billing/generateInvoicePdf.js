"use strict";
/**
 * PDF/export for issued/paid invoices.
 *
 * Output contract: PDF must match the issued invoice detail view for display number,
 * seller details, buyer details, line items, subtotal, tax, total, currency.
 * Same snapshot source, same values.
 *
 * Snapshot safety: If the invoice is issued or paid and issuedSnapshot is missing,
 * the export/PDF path must fail safely (do not silently regenerate from live settings).
 */
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
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateInvoicePdf = generateInvoicePdf;
exports.getInvoicePdfDownloadUrl = getInvoicePdfDownloadUrl;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const pdfkit_1 = __importDefault(require("pdfkit"));
const common_1 = require("./common");
async function generateInvoicePdf(request) {
    var _a;
    const uid = (0, common_1.requireAuthUid)(request);
    const data = (0, common_1.asObject)(request.data);
    const clinicId = (0, common_1.requireString)(data.clinicId, "clinicId", 2, 120);
    const invoiceId = (0, common_1.requireString)(data.invoiceId, "invoiceId", 1, 120);
    await (0, common_1.requireBillingRead)(clinicId, uid);
    const snap = await (0, common_1.invoicesCol)(clinicId).doc(invoiceId).get();
    if (!snap.exists)
        throw new https_1.HttpsError("not-found", "Invoice not found.");
    const doc = snap.data();
    const status = String((_a = doc.status) !== null && _a !== void 0 ? _a : "");
    if (status !== "issued" && status !== "paid") {
        throw new https_1.HttpsError("failed-precondition", "PDF is only available for issued or paid invoices.");
    }
    const issuedSnapshot = doc.issuedSnapshot;
    if (!issuedSnapshot || typeof issuedSnapshot !== "object") {
        throw new https_1.HttpsError("failed-precondition", "Issued invoice is missing snapshot; PDF cannot be generated. Financial documents must not be regenerated from live settings.");
    }
    const pdfBuffer = await buildPdfFromSnapshot(issuedSnapshot);
    const storagePath = `clinics/${clinicId}/billing/invoices/${invoiceId}/invoice.pdf`;
    const bucket = admin.storage().bucket();
    await bucket.file(storagePath).save(pdfBuffer, {
        contentType: "application/pdf",
        resumable: false,
        metadata: { cacheControl: "private, max-age=0, no-store" },
    });
    const generatedAt = new Date().toISOString();
    return { ok: true, invoiceId, storagePath, generatedAt };
}
function safeStr(v) {
    if (v == null)
        return "";
    return String(v).trim();
}
function safeNum(v) {
    const n = Number(v);
    return Number.isFinite(n) ? n : 0;
}
/**
 * Build PDF buffer from issuedSnapshot only. No live settings, no recomputation.
 */
function buildPdfFromSnapshot(snap) {
    return new Promise((resolve, reject) => {
        var _a, _b, _c, _d, _e, _f;
        const buffers = [];
        const pdf = new pdfkit_1.default({ margin: 50, size: "A4" });
        pdf.on("data", buffers.push.bind(buffers));
        pdf.on("end", () => resolve(Buffer.concat(buffers)));
        pdf.on("error", reject);
        const seller = ((_a = snap.sellerIdentity) !== null && _a !== void 0 ? _a : {});
        const buyer = ((_b = snap.buyerIdentity) !== null && _b !== void 0 ? _b : {});
        const numbering = ((_c = snap.numberingResult) !== null && _c !== void 0 ? _c : {});
        const currencyLocale = ((_d = snap.currencyLocale) !== null && _d !== void 0 ? _d : {});
        const taxBreakdown = ((_e = snap.taxBreakdownSnapshot) !== null && _e !== void 0 ? _e : {});
        const lineItems = ((_f = snap.lineItemPricingSnapshot) !== null && _f !== void 0 ? _f : []);
        const currency = safeStr(currencyLocale.currency) || "USD";
        const displayNumber = safeStr(numbering.displayNumber) || "—";
        pdf.fontSize(20).text("Invoice", { continued: false });
        pdf.fontSize(10).text(`Number: ${displayNumber}`, { continued: false });
        pdf.moveDown();
        const sellerName = safeStr(seller.businessDisplayName) || safeStr(seller.businessLegalName) || "Seller";
        pdf.fontSize(12).text(sellerName);
        if (safeStr(seller.businessAddress))
            pdf.text(safeStr(seller.businessAddress));
        if (safeStr(seller.businessCountry))
            pdf.text(safeStr(seller.businessCountry));
        if (safeStr(seller.taxId))
            pdf.text(`Tax ID: ${safeStr(seller.taxId)}`);
        pdf.moveDown();
        pdf.fontSize(10).text("Bill to:", { continued: false });
        const buyerName = safeStr(buyer.buyerName) || safeStr(buyer.patientId) || "—";
        pdf.text(buyerName);
        if (safeStr(buyer.buyerAddress))
            pdf.text(safeStr(buyer.buyerAddress));
        pdf.moveDown();
        let y = pdf.y;
        pdf.fontSize(10).text("Description", 50, y);
        pdf.text("Qty", 320, y);
        pdf.text("Unit", 360, y);
        pdf.text("Total", 450, y);
        pdf.moveTo(50, y + 2).lineTo(550, y + 2).stroke();
        y = pdf.y + 8;
        for (const line of lineItems) {
            const desc = safeStr(line.description) || "—";
            const qty = safeNum(line.quantity);
            const unit = safeNum(line.unitPrice);
            const total = safeNum(line.total);
            pdf.fontSize(9).text(desc.length > 40 ? desc.slice(0, 40) + "…" : desc, 50, y);
            pdf.text(String(qty), 320, y);
            pdf.text(unit.toFixed(2), 360, y);
            pdf.text(total.toFixed(2), 450, y);
            y += 18;
        }
        pdf.y = y + 8;
        const subtotal = safeNum(taxBreakdown.subtotal);
        const discountTotal = safeNum(taxBreakdown.discountTotal);
        const taxTotal = safeNum(taxBreakdown.taxTotal);
        const total = safeNum(taxBreakdown.total);
        pdf.fontSize(10).text(`Subtotal: ${subtotal.toFixed(2)} ${currency}`, { align: "right" });
        if (discountTotal > 0)
            pdf.text(`Discount: ${discountTotal.toFixed(2)} ${currency}`, { align: "right" });
        pdf.text(`Tax: ${taxTotal.toFixed(2)} ${currency}`, { align: "right" });
        pdf.fontSize(11).text(`Total: ${total.toFixed(2)} ${currency}`, { align: "right" });
        pdf.end();
    });
}
async function getInvoicePdfDownloadUrl(request) {
    var _a;
    const uid = (0, common_1.requireAuthUid)(request);
    const data = (0, common_1.asObject)(request.data);
    const clinicId = (0, common_1.requireString)(data.clinicId, "clinicId", 2, 120);
    const invoiceId = (0, common_1.requireString)(data.invoiceId, "invoiceId", 1, 120);
    await (0, common_1.requireBillingRead)(clinicId, uid);
    const snap = await (0, common_1.invoicesCol)(clinicId).doc(invoiceId).get();
    if (!snap.exists)
        throw new https_1.HttpsError("not-found", "Invoice not found.");
    const doc = snap.data();
    const status = String((_a = doc.status) !== null && _a !== void 0 ? _a : "");
    if (status !== "issued" && status !== "paid") {
        throw new https_1.HttpsError("failed-precondition", "PDF download is only available for issued or paid invoices.");
    }
    const issuedSnapshot = doc.issuedSnapshot;
    if (!issuedSnapshot || typeof issuedSnapshot !== "object") {
        throw new https_1.HttpsError("failed-precondition", "Issued invoice is missing snapshot; PDF cannot be generated.");
    }
    const storagePath = `clinics/${clinicId}/billing/invoices/${invoiceId}/invoice.pdf`;
    const bucket = admin.storage().bucket();
    const file = bucket.file(storagePath);
    const [exists] = await file.exists();
    if (!exists) {
        throw new https_1.HttpsError("failed-precondition", "PDF not yet generated. Request PDF generation first.");
    }
    const [signedUrl] = await file.getSignedUrl({
        action: "read",
        expires: Date.now() + 15 * 60 * 1000,
    });
    return { ok: true, invoiceId, url: signedUrl };
}
//# sourceMappingURL=generateInvoicePdf.js.map