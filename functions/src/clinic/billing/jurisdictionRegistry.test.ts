import { describe, expect, it } from "@jest/globals";
import {
  getBillingJurisdiction,
  getClinicCountry,
  validateInvoiceForIssue,
  validateSellerAgainstJurisdiction,
} from "./jurisdictionRegistry";

describe("jurisdictionRegistry", () => {
  describe("getBillingJurisdiction", () => {
    it("returns null for invalid or missing country", () => {
      expect(getBillingJurisdiction(null)).toBeNull();
      expect(getBillingJurisdiction(undefined)).toBeNull();
      expect(getBillingJurisdiction("")).toBeNull();
      expect(getBillingJurisdiction("X")).toBeNull();
      expect(getBillingJurisdiction("USA")).toBeNull();
    });

    it("returns entry for valid country code (case-insensitive)", () => {
      const gb = getBillingJurisdiction("GB");
      expect(gb).not.toBeNull();
      expect(gb!.defaultTaxLabel).toBe("VAT");
      expect(gb!.invoiceTitleMode).toBe("VAT Invoice");
      expect(getBillingJurisdiction("gb")).toEqual(gb);
    });

    it("returns Tax Invoice for AU and NZ", () => {
      expect(getBillingJurisdiction("AU")!.invoiceTitleMode).toBe("Tax Invoice");
      expect(getBillingJurisdiction("NZ")!.invoiceTitleMode).toBe("Tax Invoice");
    });

    it("returns Invoice for US and CA", () => {
      expect(getBillingJurisdiction("US")!.invoiceTitleMode).toBe("Invoice");
      expect(getBillingJurisdiction("CA")!.invoiceTitleMode).toBe("Invoice");
    });
  });

  describe("getClinicCountry", () => {
    it("returns null for null or empty data", () => {
      expect(getClinicCountry(null)).toBeNull();
      expect(getClinicCountry({})).toBeNull();
    });

    it("reads from profile.country", () => {
      expect(getClinicCountry({ profile: { country: "CZ" } })).toBe("CZ");
      expect(getClinicCountry({ profile: { country: " cz " } })).toBe("CZ");
    });

    it("falls back to root country", () => {
      expect(getClinicCountry({ country: "GB" })).toBe("GB");
    });
  });

  describe("validateSellerAgainstJurisdiction", () => {
    it("returns empty when all required seller fields present", () => {
      const j = getBillingJurisdiction("GB")!;
      const missing = validateSellerAgainstJurisdiction(j, {
        businessDisplayName: "Acme Ltd",
        businessAddress: "1 High St",
        taxId: "GB123456789",
      });
      expect(missing).toEqual([]);
    });

    it("returns missing labels when fields empty", () => {
      const j = getBillingJurisdiction("GB")!;
      const missing = validateSellerAgainstJurisdiction(j, {
        businessDisplayName: "Acme",
        taxId: "",
      });
      expect(missing).toContain("Business address");
      expect(missing).toContain("VAT/GST/ABN/Business number");
    });
  });

  describe("validateInvoiceForIssue", () => {
    it("returns empty when invoice has number, date, line items, total", () => {
      const j = getBillingJurisdiction("GB")!;
      const missing = validateInvoiceForIssue(
        {
          displayNumber: "INV-001",
          createdAt: { toDate: () => new Date() },
          lineItems: [{ description: "Consult", quantity: 1, unitPrice: 100 }],
          total: 100,
        },
        j
      );
      expect(missing).toEqual([]);
    });

    it("returns missing when invoice number absent", () => {
      const j = getBillingJurisdiction("GB")!;
      const missing = validateInvoiceForIssue(
        {
          createdAt: { toDate: () => new Date() },
          lineItems: [{}],
          total: 50,
        },
        j
      );
      expect(missing).toContain("Invoice number");
    });

    it("returns missing when line items empty", () => {
      const j = getBillingJurisdiction("GB")!;
      const missing = validateInvoiceForIssue(
        {
          displayNumber: "INV-001",
          createdAt: { toDate: () => new Date() },
          lineItems: [],
          total: 0,
        },
        j
      );
      expect(missing).toContain("At least one line item");
    });
  });
});
