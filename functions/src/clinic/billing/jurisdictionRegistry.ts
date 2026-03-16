/**
 * Read-only billing jurisdiction registry keyed by ISO 3166-1 alpha-2.
 * Used to default tax calculation method, display labels, and issue-time validation by clinic country.
 * See docs/BILLING_JURISDICTION_REGISTRY.md.
 */

export type TaxCalculationMethod = "inclusive" | "exclusive";

/** Invoice title mode for document heading (e.g. "Invoice" vs "Tax Invoice"). */
export type InvoiceTitleMode = "Invoice" | "Tax Invoice" | "VAT Invoice";

export type BillingJurisdictionEntry = {
  taxCalculationMethod: TaxCalculationMethod;
  defaultTaxLabel: string;
  /** Fields that must be present or validated before issuing (e.g. supplierVatId, invoiceNumber). */
  requiredInvoiceFields: string[];
  /** Suggested invoice document title for this jurisdiction. */
  invoiceTitleMode: InvoiceTitleMode;
  /** Seller fields required at issue (e.g. businessName, address, taxId). */
  requiredSellerFields: string[];
  /** Buyer fields required when B2B / reverse charge (e.g. buyerVatId). */
  requiredBuyerFieldsWhenB2B: string[];
  /** Whether to show a reverse-charge notice when applicable. */
  requiresReverseChargeNote: boolean;
  /** Retention guidance in years. */
  retentionYears: number;
};

/** EU common baseline (used for EU countries not explicitly overridden). */
const EU_BASELINE: BillingJurisdictionEntry = {
  taxCalculationMethod: "inclusive",
  defaultTaxLabel: "VAT",
  requiredInvoiceFields: ["invoiceNumber", "issueDate", "supplierName", "supplierAddress", "supplierVatId", "customerName", "customerAddress", "lineItemDescription", "lineItemQuantity", "lineItemUnitPrice", "taxRate", "taxAmount", "total"],
  invoiceTitleMode: "VAT Invoice",
  requiredSellerFields: ["businessDisplayName", "businessAddress", "taxId"],
  requiredBuyerFieldsWhenB2B: ["buyerVatId"],
  requiresReverseChargeNote: true,
  retentionYears: 10,
};

/** Registry key = ISO 3166-1 alpha-2 uppercase. */
const REGISTRY: Record<string, BillingJurisdictionEntry> = {
  AU: {
    taxCalculationMethod: "inclusive",
    defaultTaxLabel: "GST",
    requiredInvoiceFields: ["invoiceNumber", "issueDate", "supplierName", "supplierAbn", "lineItemDescription", "lineItemQuantity", "lineItemPrice", "gstAmount", "total"],
    invoiceTitleMode: "Tax Invoice",
    requiredSellerFields: ["businessDisplayName", "taxId"],
    requiredBuyerFieldsWhenB2B: [],
    requiresReverseChargeNote: false,
    retentionYears: 5,
  },
  NZ: {
    taxCalculationMethod: "inclusive",
    defaultTaxLabel: "GST",
    requiredInvoiceFields: ["invoiceNumber", "issueDate", "supplierName", "supplierGstNumber", "lineItemDescription", "gstAmountOrIncluded", "total"],
    invoiceTitleMode: "Tax Invoice",
    requiredSellerFields: ["businessDisplayName", "taxId"],
    requiredBuyerFieldsWhenB2B: [],
    requiresReverseChargeNote: false,
    retentionYears: 7,
  },
  GB: {
    taxCalculationMethod: "inclusive",
    defaultTaxLabel: "VAT",
    requiredInvoiceFields: ["invoiceNumber", "issueDate", "supplierName", "supplierAddress", "supplierVatNumber", "customerName", "customerAddress", "lineItemDescription", "quantity", "unitPrice", "vatRate", "vatAmount", "totalVat", "total"],
    invoiceTitleMode: "VAT Invoice",
    requiredSellerFields: ["businessDisplayName", "businessAddress", "taxId"],
    requiredBuyerFieldsWhenB2B: ["buyerVatId"],
    requiresReverseChargeNote: true,
    retentionYears: 6,
  },
  UK: {
    taxCalculationMethod: "inclusive",
    defaultTaxLabel: "VAT",
    requiredInvoiceFields: ["invoiceNumber", "issueDate", "supplierName", "supplierAddress", "supplierVatNumber", "customerName", "customerAddress", "lineItemDescription", "quantity", "unitPrice", "vatRate", "vatAmount", "totalVat", "total"],
    invoiceTitleMode: "VAT Invoice",
    requiredSellerFields: ["businessDisplayName", "businessAddress", "taxId"],
    requiredBuyerFieldsWhenB2B: ["buyerVatId"],
    requiresReverseChargeNote: true,
    retentionYears: 6,
  },
  US: {
    taxCalculationMethod: "exclusive",
    defaultTaxLabel: "Sales tax",
    requiredInvoiceFields: ["invoiceNumber", "issueDate", "supplierName", "supplierAddress", "customerName", "customerAddress", "lineItemDescription", "quantity", "unitPrice", "total"],
    invoiceTitleMode: "Invoice",
    requiredSellerFields: ["businessDisplayName", "businessAddress"],
    requiredBuyerFieldsWhenB2B: [],
    requiresReverseChargeNote: false,
    retentionYears: 7,
  },
  CA: {
    taxCalculationMethod: "exclusive",
    defaultTaxLabel: "GST/HST",
    requiredInvoiceFields: ["invoiceNumber", "issueDate", "supplierName", "supplierBusinessNumber", "customerName", "lineItemDescription", "quantity", "unitPrice", "taxRate", "taxAmount", "total"],
    invoiceTitleMode: "Invoice",
    requiredSellerFields: ["businessDisplayName", "taxId"],
    requiredBuyerFieldsWhenB2B: [],
    requiresReverseChargeNote: false,
    retentionYears: 6,
  },
  CZ: {
    ...EU_BASELINE,
    requiredInvoiceFields: [...EU_BASELINE.requiredInvoiceFields, "supplierRegistrationNumber"],
    requiredSellerFields: ["businessDisplayName", "businessAddress", "taxId", "registrationNumber"],
    retentionYears: 10,
  },
  DE: EU_BASELINE,
  FR: EU_BASELINE,
  IE: EU_BASELINE,
  ES: EU_BASELINE,
  IT: EU_BASELINE,
  NL: EU_BASELINE,
  PL: EU_BASELINE,
  PT: EU_BASELINE,
  CH: {
    ...EU_BASELINE,
    retentionYears: 10,
  },
  AT: EU_BASELINE,
  BE: EU_BASELINE,
};

/**
 * Returns the jurisdiction entry for a country code, or null if not in registry.
 * @param countryCode - ISO 3166-1 alpha-2 (case-insensitive; normalized to uppercase).
 */
export function getBillingJurisdiction(countryCode: string | null | undefined): BillingJurisdictionEntry | null {
  if (countryCode == null || typeof countryCode !== "string") return null;
  const key = countryCode.trim().toUpperCase();
  if (key.length !== 2 || !/^[A-Z]{2}$/.test(key)) return null;
  return REGISTRY[key] ?? null;
}

/**
 * Resolves clinic country from the clinic document (profile.country or root country).
 */
export function getClinicCountry(clinicData: Record<string, unknown> | null): string | null {
  if (!clinicData) return null;
  const profile = clinicData.profile as Record<string, unknown> | undefined;
  const fromProfile = profile?.country;
  const fromRoot = clinicData.country;
  const raw = fromProfile ?? fromRoot;
  if (raw == null || typeof raw !== "string") return null;
  const s = (raw as string).trim().toUpperCase();
  return s.length === 2 && /^[A-Z]{2}$/.test(s) ? s : null;
}

/**
 * Returns taxInclusivePricing default from registry for the given country, or undefined if unknown.
 */
export function getDefaultTaxInclusiveForCountry(countryCode: string | null | undefined): boolean | undefined {
  const entry = getBillingJurisdiction(countryCode);
  if (!entry) return undefined;
  return entry.taxCalculationMethod === "inclusive";
}

/**
 * Validates that seller settings satisfy jurisdiction required seller fields.
 * Returns an array of missing field keys (human-readable); empty if valid.
 */
export function validateSellerAgainstJurisdiction(
  jurisdiction: BillingJurisdictionEntry,
  settings: Record<string, unknown> | null
): string[] {
  const missing: string[] = [];
  const s = settings ?? {};
  for (const field of jurisdiction.requiredSellerFields) {
    const value = s[field];
    if (value == null || String(value).trim() === "") {
      const label = field === "taxId" ? "VAT/GST/ABN/Business number" : field === "businessDisplayName" ? "Business display name" : field === "businessAddress" ? "Business address" : field === "registrationNumber" ? "Registration number" : field;
      missing.push(label);
    }
  }
  return missing;
}

/**
 * Validates minimal invoice data for issuance (invoice number, date, line items, totals).
 * Returns an array of missing requirement descriptions; empty if valid.
 */
export function validateInvoiceForIssue(
  invoice: Record<string, unknown>,
  _jurisdiction: BillingJurisdictionEntry
): string[] {
  const missing: string[] = [];
  const number = invoice.invoiceNumber ?? invoice.displayNumber;
  if (number == null || String(number).trim() === "") missing.push("Invoice number");
  const issueDate = invoice.issueDate ?? invoice.createdAt;
  if (issueDate == null) missing.push("Issue date");
  const lineItems = invoice.lineItems;
  if (!Array.isArray(lineItems) || lineItems.length === 0) missing.push("At least one line item");
  const total = invoice.total;
  if (total == null || !Number.isFinite(Number(total))) missing.push("Total amount");
  return missing;
}
