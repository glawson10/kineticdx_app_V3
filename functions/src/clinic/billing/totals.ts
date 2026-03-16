import { HttpsError } from "firebase-functions/v2/https";

export type InvoiceLineType = "service" | "product";

/** Optional snapshot at line level: which pricing rule produced this line (Phase 6A). Never used to rewrite issued invoices. */
export type PricingSourceSnapshot = {
  source: string;
  durationMinutes?: number;
  rateOrFixed?: number;
  description?: string;
};

export type InvoiceLineInput = {
  type: InvoiceLineType;
  itemId: string;
  description: string;
  quantity: number;
  unitPrice: number;
  taxRate: number;
  discount?: number;
  /** When line was populated from pricing engine: source identifier (e.g. clientOverride, clinicFallback). */
  pricingSource?: string;
  /** Frozen snapshot of the rule that produced this line; stored at issue time and never rewritten. */
  pricingSourceSnapshot?: PricingSourceSnapshot;
};

export type InvoiceLineComputed = InvoiceLineInput & {
  lineNet: number;
  taxAmount: number;
  total: number;
};

export type InvoiceTotals = {
  lineItems: InvoiceLineComputed[];
  subtotal: number;
  discountTotal: number;
  taxTotal: number;
  total: number;
};

function roundMoney(n: number): number {
  return Math.round(n * 100) / 100;
}

function assertFiniteNumber(value: unknown, label: string): number {
  const n = Number(value);
  if (!Number.isFinite(n)) throw new HttpsError("invalid-argument", `${label} must be a finite number.`);
  return n;
}

function normalizeLine(line: InvoiceLineInput, idx: number, taxInclusive: boolean): InvoiceLineComputed {
  const itemId = String(line.itemId ?? "").trim();
  const description = String(line.description ?? "").trim();
  const type = String(line.type ?? "") as InvoiceLineType;
  if (!(type === "service" || type === "product")) {
    throw new HttpsError("invalid-argument", `lineItems[${idx}].type must be service or product.`);
  }
  if (!itemId) throw new HttpsError("invalid-argument", `lineItems[${idx}].itemId is required.`);
  if (!description) throw new HttpsError("invalid-argument", `lineItems[${idx}].description is required.`);

  const quantity = assertFiniteNumber(line.quantity, `lineItems[${idx}].quantity`);
  const unitPrice = assertFiniteNumber(line.unitPrice, `lineItems[${idx}].unitPrice`);
  const taxRate = assertFiniteNumber(line.taxRate, `lineItems[${idx}].taxRate`);
  const discount = line.discount === undefined ? 0 : assertFiniteNumber(line.discount, `lineItems[${idx}].discount`);

  if (quantity <= 0) throw new HttpsError("invalid-argument", `lineItems[${idx}].quantity must be > 0.`);
  if (unitPrice < 0) throw new HttpsError("invalid-argument", `lineItems[${idx}].unitPrice must be >= 0.`);
  if (taxRate < 0 || taxRate > 100) {
    throw new HttpsError("invalid-argument", `lineItems[${idx}].taxRate must be between 0 and 100.`);
  }
  if (discount < 0) throw new HttpsError("invalid-argument", `lineItems[${idx}].discount must be >= 0.`);

  let lineNet: number;
  let taxAmount: number;
  let total: number;
  let clampedDiscount: number;

  if (taxInclusive) {
    const totalInclusive = roundMoney(quantity * unitPrice);
    clampedDiscount = Math.min(roundMoney(discount), totalInclusive);
    const afterDiscount = roundMoney(totalInclusive - clampedDiscount);
    if (taxRate === 0) {
      lineNet = afterDiscount;
      taxAmount = 0;
      total = afterDiscount;
    } else {
      lineNet = roundMoney(afterDiscount / (1 + taxRate / 100));
      taxAmount = roundMoney(afterDiscount - lineNet);
      total = afterDiscount;
    }
  } else {
    const gross = roundMoney(quantity * unitPrice);
    clampedDiscount = Math.min(roundMoney(discount), gross);
    lineNet = roundMoney(gross - clampedDiscount);
    taxAmount = roundMoney(lineNet * (taxRate / 100));
    total = roundMoney(lineNet + taxAmount);
  }

  if (total < 0) throw new HttpsError("invalid-argument", `lineItems[${idx}] total cannot be negative.`);

  const out: InvoiceLineComputed = {
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
  if (line.pricingSource !== undefined) out.pricingSource = line.pricingSource;
  if (line.pricingSourceSnapshot !== undefined) out.pricingSourceSnapshot = line.pricingSourceSnapshot;
  return out;
}

export type ComputeInvoiceTotalsOptions = {
  /** When true, line unitPrice is treated as including tax (VAT/GST inclusive). */
  taxInclusive?: boolean;
};

export function computeInvoiceTotals(
  lineItems: InvoiceLineInput[],
  invoiceDiscount = 0,
  options: ComputeInvoiceTotalsOptions = {}
): InvoiceTotals {
  if (!Array.isArray(lineItems) || lineItems.length === 0) {
    throw new HttpsError("invalid-argument", "lineItems is required.");
  }
  const taxInclusive = options.taxInclusive === true;
  const computed = lineItems.map((line, idx) => normalizeLine(line, idx, taxInclusive));

  const preInvoiceDiscountSubtotal = roundMoney(computed.reduce((acc, line) => acc + line.lineNet, 0));
  const lineDiscountTotal = roundMoney(computed.reduce((acc, line) => acc + (line.discount ?? 0), 0));

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
    throw new HttpsError("invalid-argument", "Invoice totals cannot be negative.");
  }
  return {
    lineItems: rescaledLines,
    subtotal,
    discountTotal: effectiveDiscount,
    taxTotal,
    total,
  };
}
