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

import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import PDFDocument from "pdfkit";
import { asObject, invoicesCol, requireAuthUid, requireBillingRead, requireString } from "./common";

export async function generateInvoicePdf(request: { auth?: { uid?: string }; data?: unknown }) {
  const uid = requireAuthUid(request);
  const data = asObject(request.data);
  const clinicId = requireString(data.clinicId, "clinicId", 2, 120);
  const invoiceId = requireString(data.invoiceId, "invoiceId", 1, 120);
  await requireBillingRead(clinicId, uid);
  const snap = await invoicesCol(clinicId).doc(invoiceId).get();
  if (!snap.exists) throw new HttpsError("not-found", "Invoice not found.");
  const doc = snap.data() as Record<string, unknown>;
  const status = String(doc.status ?? "");

  if (status !== "issued" && status !== "paid") {
    throw new HttpsError("failed-precondition", "PDF is only available for issued or paid invoices.");
  }

  const issuedSnapshot = doc.issuedSnapshot as Record<string, unknown> | undefined;
  if (!issuedSnapshot || typeof issuedSnapshot !== "object") {
    throw new HttpsError(
      "failed-precondition",
      "Issued invoice is missing snapshot; PDF cannot be generated. Financial documents must not be regenerated from live settings."
    );
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

function safeStr(v: unknown): string {
  if (v == null) return "";
  return String(v).trim();
}

function safeNum(v: unknown): number {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

/**
 * Build PDF buffer from issuedSnapshot only. No live settings, no recomputation.
 */
function buildPdfFromSnapshot(snap: Record<string, unknown>): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const buffers: Buffer[] = [];
    const pdf = new PDFDocument({ margin: 50, size: "A4" });
    pdf.on("data", buffers.push.bind(buffers));
    pdf.on("end", () => resolve(Buffer.concat(buffers)));
    pdf.on("error", reject);

    const seller = (snap.sellerIdentity ?? {}) as Record<string, unknown>;
    const buyer = (snap.buyerIdentity ?? {}) as Record<string, unknown>;
    const numbering = (snap.numberingResult ?? {}) as Record<string, unknown>;
    const currencyLocale = (snap.currencyLocale ?? {}) as Record<string, unknown>;
    const taxBreakdown = (snap.taxBreakdownSnapshot ?? {}) as Record<string, unknown>;
    const lineItems = (snap.lineItemPricingSnapshot ?? []) as Record<string, unknown>[];

    const currency = safeStr(currencyLocale.currency) || "USD";
    const displayNumber = safeStr(numbering.displayNumber) || "—";

    pdf.fontSize(20).text("Invoice", { continued: false });
    pdf.fontSize(10).text(`Number: ${displayNumber}`, { continued: false });
    pdf.moveDown();

    const sellerName = safeStr(seller.businessDisplayName) || safeStr(seller.businessLegalName) || "Seller";
    pdf.fontSize(12).text(sellerName);
    if (safeStr(seller.businessAddress)) pdf.text(safeStr(seller.businessAddress));
    if (safeStr(seller.businessCountry)) pdf.text(safeStr(seller.businessCountry));
    if (safeStr(seller.taxId)) pdf.text(`Tax ID: ${safeStr(seller.taxId)}`);
    pdf.moveDown();

    pdf.fontSize(10).text("Bill to:", { continued: false });
    const buyerName = safeStr(buyer.buyerName) || safeStr(buyer.patientId) || "—";
    pdf.text(buyerName);
    if (safeStr(buyer.buyerAddress)) pdf.text(safeStr(buyer.buyerAddress));
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
    if (discountTotal > 0) pdf.text(`Discount: ${discountTotal.toFixed(2)} ${currency}`, { align: "right" });
    pdf.text(`Tax: ${taxTotal.toFixed(2)} ${currency}`, { align: "right" });
    pdf.fontSize(11).text(`Total: ${total.toFixed(2)} ${currency}`, { align: "right" });

    pdf.end();
  });
}

export async function getInvoicePdfDownloadUrl(request: { auth?: { uid?: string }; data?: unknown }) {
  const uid = requireAuthUid(request);
  const data = asObject(request.data);
  const clinicId = requireString(data.clinicId, "clinicId", 2, 120);
  const invoiceId = requireString(data.invoiceId, "invoiceId", 1, 120);
  await requireBillingRead(clinicId, uid);
  const snap = await invoicesCol(clinicId).doc(invoiceId).get();
  if (!snap.exists) throw new HttpsError("not-found", "Invoice not found.");
  const doc = snap.data() as Record<string, unknown>;
  const status = String(doc.status ?? "");
  if (status !== "issued" && status !== "paid") {
    throw new HttpsError("failed-precondition", "PDF download is only available for issued or paid invoices.");
  }
  const issuedSnapshot = doc.issuedSnapshot;
  if (!issuedSnapshot || typeof issuedSnapshot !== "object") {
    throw new HttpsError(
      "failed-precondition",
      "Issued invoice is missing snapshot; PDF cannot be generated."
    );
  }
  const storagePath = `clinics/${clinicId}/billing/invoices/${invoiceId}/invoice.pdf`;
  const bucket = admin.storage().bucket();
  const file = bucket.file(storagePath);
  const [exists] = await file.exists();
  if (!exists) {
    throw new HttpsError("failed-precondition", "PDF not yet generated. Request PDF generation first.");
  }
  const [signedUrl] = await file.getSignedUrl({
    action: "read",
    expires: Date.now() + 15 * 60 * 1000,
  });
  return { ok: true, invoiceId, url: signedUrl };
}
