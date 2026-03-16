import { describe, expect, it } from "@jest/globals";
import { computeInvoiceTotals } from "./totals";

describe("computeInvoiceTotals", () => {
  it("computes subtotal, tax, and total", () => {
    const result = computeInvoiceTotals([
      {
        type: "service",
        itemId: "s1",
        description: "Consult",
        quantity: 2,
        unitPrice: 50,
        taxRate: 10,
      },
    ]);
    expect(result.subtotal).toBe(100);
    expect(result.taxTotal).toBe(10);
    expect(result.total).toBe(110);
  });

  it("applies line and invoice discounts", () => {
    const result = computeInvoiceTotals(
      [
        {
          type: "service",
          itemId: "s1",
          description: "Consult",
          quantity: 1,
          unitPrice: 100,
          taxRate: 20,
          discount: 10,
        },
      ],
      20
    );
    expect(result.subtotal).toBe(70);
    expect(result.discountTotal).toBe(30);
    expect(result.taxTotal).toBe(14);
    expect(result.total).toBe(84);
  });

  it("computes tax-inclusive: unit price includes tax", () => {
    const result = computeInvoiceTotals(
      [
        {
          type: "service",
          itemId: "s1",
          description: "Consult",
          quantity: 1,
          unitPrice: 121,
          taxRate: 21,
        },
        {
          type: "service",
          itemId: "s2",
          description: "Follow-up",
          quantity: 2,
          unitPrice: 60.5,
          taxRate: 21,
        },
      ],
      0,
      { taxInclusive: true }
    );
    expect(result.lineItems[0].lineNet).toBe(100);
    expect(result.lineItems[0].taxAmount).toBe(21);
    expect(result.lineItems[0].total).toBe(121);
    expect(result.lineItems[1].lineNet).toBe(100);
    expect(result.lineItems[1].taxAmount).toBe(21);
    expect(result.lineItems[1].total).toBe(121);
    expect(result.subtotal).toBe(200);
    expect(result.taxTotal).toBe(42);
    expect(result.total).toBe(242);
  });

  it("exclusive tax math with multiple lines", () => {
    const result = computeInvoiceTotals(
      [
        { type: "service", itemId: "a", description: "A", quantity: 1, unitPrice: 100, taxRate: 10 },
        { type: "service", itemId: "b", description: "B", quantity: 2, unitPrice: 50, taxRate: 20 },
      ],
      0
    );
    expect(result.lineItems[0].lineNet).toBe(100);
    expect(result.lineItems[0].taxAmount).toBe(10);
    expect(result.lineItems[0].total).toBe(110);
    expect(result.lineItems[1].lineNet).toBe(100);
    expect(result.lineItems[1].taxAmount).toBe(20);
    expect(result.lineItems[1].total).toBe(120);
    expect(result.subtotal).toBe(200);
    expect(result.taxTotal).toBe(30);
    expect(result.total).toBe(230);
  });

  it("mixed tax rates (0% and 20%)", () => {
    const result = computeInvoiceTotals(
      [
        { type: "service", itemId: "zero", description: "Zero", quantity: 1, unitPrice: 50, taxRate: 0 },
        { type: "service", itemId: "vat", description: "VAT", quantity: 1, unitPrice: 60, taxRate: 20 },
      ],
      0
    );
    expect(result.lineItems[0].taxAmount).toBe(0);
    expect(result.lineItems[0].total).toBe(50);
    expect(result.lineItems[1].taxAmount).toBe(12);
    expect(result.lineItems[1].total).toBe(72);
    expect(result.subtotal).toBe(110);
    expect(result.taxTotal).toBe(12);
    expect(result.total).toBe(122);
  });

  it("rounding is consistent end-to-end", () => {
    const result = computeInvoiceTotals(
      [
        { type: "service", itemId: "s1", description: "S1", quantity: 1, unitPrice: 33.33, taxRate: 15 },
        { type: "service", itemId: "s2", description: "S2", quantity: 1, unitPrice: 33.33, taxRate: 15 },
      ],
      0
    );
    expect(result.lineItems[0].lineNet).toBe(33.33);
    expect(result.lineItems[0].taxAmount).toBe(5);
    expect(result.lineItems[0].total).toBe(38.33);
    expect(result.subtotal).toBe(66.66);
    expect(result.taxTotal).toBe(10);
    expect(result.total).toBe(76.66);
  });

  it("preserves pricingSource and pricingSourceSnapshot on lines", () => {
    const result = computeInvoiceTotals(
      [
        {
          type: "service",
          itemId: "s1",
          description: "Consult",
          quantity: 1,
          unitPrice: 100,
          taxRate: 10,
          pricingSource: "appointmentTypeDefault",
          pricingSourceSnapshot: { source: "appointmentTypeDefault", rateOrFixed: 100 },
        },
      ],
      0
    );
    expect(result.lineItems[0].pricingSource).toBe("appointmentTypeDefault");
    expect(result.lineItems[0].pricingSourceSnapshot).toEqual({
      source: "appointmentTypeDefault",
      rateOrFixed: 100,
    });
  });
});
