"use strict";
/**
 * Read-only billing jurisdiction registry keyed by ISO 3166-1 alpha-2.
 * Used to default tax calculation method, display labels, and issue-time validation by clinic country.
 * See docs/BILLING_JURISDICTION_REGISTRY.md.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.getBillingJurisdiction = getBillingJurisdiction;
exports.getClinicCountry = getClinicCountry;
exports.getDefaultTaxInclusiveForCountry = getDefaultTaxInclusiveForCountry;
exports.validateSellerAgainstJurisdiction = validateSellerAgainstJurisdiction;
exports.validateInvoiceForIssue = validateInvoiceForIssue;
/** EU common baseline (used for EU countries not explicitly overridden). */
const EU_BASELINE = {
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
const REGISTRY = {
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
function getBillingJurisdiction(countryCode) {
    var _a;
    if (countryCode == null || typeof countryCode !== "string")
        return null;
    const key = countryCode.trim().toUpperCase();
    if (key.length !== 2 || !/^[A-Z]{2}$/.test(key))
        return null;
    return (_a = REGISTRY[key]) !== null && _a !== void 0 ? _a : null;
}
/**
 * Resolves clinic country from the clinic document (profile.country or root country).
 */
function getClinicCountry(clinicData) {
    if (!clinicData)
        return null;
    const profile = clinicData.profile;
    const fromProfile = profile === null || profile === void 0 ? void 0 : profile.country;
    const fromRoot = clinicData.country;
    const raw = fromProfile !== null && fromProfile !== void 0 ? fromProfile : fromRoot;
    if (raw == null || typeof raw !== "string")
        return null;
    const s = raw.trim().toUpperCase();
    return s.length === 2 && /^[A-Z]{2}$/.test(s) ? s : null;
}
/**
 * Returns taxInclusivePricing default from registry for the given country, or undefined if unknown.
 */
function getDefaultTaxInclusiveForCountry(countryCode) {
    const entry = getBillingJurisdiction(countryCode);
    if (!entry)
        return undefined;
    return entry.taxCalculationMethod === "inclusive";
}
/**
 * Validates that seller settings satisfy jurisdiction required seller fields.
 * Returns an array of missing field keys (human-readable); empty if valid.
 */
function validateSellerAgainstJurisdiction(jurisdiction, settings) {
    const missing = [];
    const s = settings !== null && settings !== void 0 ? settings : {};
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
function validateInvoiceForIssue(invoice, _jurisdiction) {
    var _a, _b;
    const missing = [];
    const number = (_a = invoice.invoiceNumber) !== null && _a !== void 0 ? _a : invoice.displayNumber;
    if (number == null || String(number).trim() === "")
        missing.push("Invoice number");
    const issueDate = (_b = invoice.issueDate) !== null && _b !== void 0 ? _b : invoice.createdAt;
    if (issueDate == null)
        missing.push("Issue date");
    const lineItems = invoice.lineItems;
    if (!Array.isArray(lineItems) || lineItems.length === 0)
        missing.push("At least one line item");
    const total = invoice.total;
    if (total == null || !Number.isFinite(Number(total)))
        missing.push("Total amount");
    return missing;
}
//# sourceMappingURL=jurisdictionRegistry.js.map