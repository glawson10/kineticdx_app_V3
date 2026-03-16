# Billing jurisdiction registry

Contract for the read-only billing jurisdiction registry: how it is keyed, where it lives, and how billing callables use it.

## Purpose

- Provide **defaults and hints** by country (ISO 3166-1 alpha-2) for tax calculation method and display labels.
- Support future **validation** of required invoice fields per jurisdiction (e.g. before issue).
- Clinic-level tax rates (`clinics/{clinicId}/taxes`) remain the source of truth for actual rates; the registry does not store rates.

## Registry location

- **In code:** `functions/src/clinic/billing/jurisdictionRegistry.ts`
- Read-only data: a map keyed by country code. No Firestore collection; no client access.

## Registry shape

Each entry is keyed by **ISO 3166-1 alpha-2** (2-letter uppercase, e.g. `AU`, `US`, `GB`).

| Field | Type | Description |
|-------|------|-------------|
| `taxCalculationMethod` | `"inclusive"` \| `"exclusive"` | Whether tax is typically included in prices (VAT/GST) or added on top (sales tax). |
| `defaultTaxLabel` | string | Display label for tax (e.g. `"GST"`, `"VAT"`, `"Sales tax"`). |
| `requiredInvoiceFields` | string[] | Invoice fields that must be present for compliance (e.g. `invoiceNumber`, `supplierVatId`). |
| `invoiceTitleMode` | `"Invoice"` \| `"Tax Invoice"` \| `"VAT Invoice"` | Suggested document title for the jurisdiction. |
| `requiredSellerFields` | string[] | Billing settings fields required before issue (e.g. `businessDisplayName`, `taxId`). |
| `requiredBuyerFieldsWhenB2B` | string[] | Buyer fields required for B2B / reverse charge (e.g. `buyerVatId`). |
| `requiresReverseChargeNote` | boolean | Whether to show a reverse-charge notice when applicable. |
| `retentionYears` | number | Retention guidance in years. |

## Resolving clinic country

- Clinic document: `clinics/{clinicId}`.
- Country is stored under **profile:** `profile.country` (written by `updateClinicProfile`).
- Normalize to uppercase 2-letter code for lookup; missing or invalid → no registry match.

## How billing uses the registry

1. **updateBillingSettings**  
   When saving billing settings, if the existing general settings doc has no `taxInclusivePricing` and the patch does not set it, the backend loads the clinic doc, reads `profile.country`, looks up the registry, and **defaults** `taxInclusivePricing` from `taxCalculationMethod` (`inclusive` → true, `exclusive` → false). If the clinic has no country or the country is not in the registry, no default is applied.

2. **getBillingJurisdiction** (callable)  
   Returns jurisdiction hints for the clinic’s country: tax label, invoice title mode, required seller/buyer fields, retention. Response includes `invoiceTitleMode`, `requiredSellerFields`, `requiredBuyerFieldsWhenB2B`, `requiresReverseChargeNote`, `retentionYears` (nulls when country missing or not in registry).

3. **issueInvoice**  
   When transitioning an invoice to `issued`, the backend loads the clinic country and billing settings, looks up the jurisdiction, and validates required seller fields (from billing settings) and minimal invoice data (invoice number, issue date, line items, total). If any are missing, issuance fails with a clear message listing them. Local accountant review is recommended for production use in a new jurisdiction.

## Security and scope

- Registry is **read-only** and **global** (not clinic-scoped); it contains no PII and no clinic data.
- All billing **data** remains under `clinics/{clinicId}/...`. Only the **lookup key** (clinic country) comes from the clinic doc.
- Billing callables that read the clinic doc (e.g. for country) already enforce `requireBillingWrite` or `requireBillingRead` as appropriate.
