# Accounts settings – what each subcategory shows

Accounts settings are under **Clinic Settings > Accounts**. The left rail lists subcategories; the main area shows the selected pane. All config panes (Business Identity through Compliance & Retention) load from the same billing general settings document; **Taxes**, **Payment types**, **Billable items**, and **Products** each load their own catalog data.

---

## Config panes (shared settings document)

These use **billing general settings** (`clinics/{clinicId}/billing/_/settings/general`). If the document does not exist yet (no one has saved billing settings), you see empty fields; saving creates it.

| Subcategory | What you see |
|-------------|----------------|
| **Business Identity** | Display name, legal name, address, country, registration number, VAT/tax ID, phone, email, website. Preview of how the seller block will look on issued invoices. Note: changes affect future invoices only; issued invoices use the snapshot at issue time. |
| **Tax & Jurisdiction** | Tax-inclusive pricing toggle. Note that issued invoices use the snapshot at issue time. |
| **Invoice Numbering** | Invoice prefix and next number. Preview of the next invoice number. |
| **Invoice Defaults** | Default due days, currency, and related defaults for new invoices. |
| **Invoice Template** | Footer text, invoice notes, locale, invoice title, and toggles (show logo, show practitioner, show business contact, group tax lines). |
| **Payment Terms** | Guidance and placeholders for payment terms (content may be minimal). |
| **Compliance & Retention** | Jurisdiction/retention guidance, accountant review recommendation, and note that issued invoices are immutable and use the snapshot at issue time. |

---

## Catalog panes (separate data)

| Subcategory | What you see |
|-------------|----------------|
| **Taxes** | List of tax definitions (name, rate, etc.) for the clinic. Add/edit/inactivate. |
| **Payment types** | List of payment methods (e.g. Card, Cash, Bank transfer). Add/edit/inactivate. |
| **Billable items** | Catalog of services/items that can be added to invoices. |
| **Products** | Catalog of products. |

---

## Loading and errors

- **Loading:** A spinner and “Loading settings…” appear until the first response. Config panes use a **one-time read** (not a long-lived stream) so the first load should complete as soon as the server responds.
- **Timeout:** If you see “Settings load timed out” after ~12 seconds, check your connection and that you have **billing read** permission for the clinic, then use **Retry**.
- **Permission:** If you see a permission-denied style message, you need a role that has billing read (e.g. manage Billing, billing.read, viewFinancialReports) for this clinic.
