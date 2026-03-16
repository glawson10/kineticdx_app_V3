import { asObject, db, requireAuthUid, requireBillingRead, requireString } from "./common";
import { getBillingJurisdiction as getJurisdiction, getClinicCountry } from "./jurisdictionRegistry";

/**
 * Returns billing jurisdiction hints for the clinic's country (for UI: tax label, calculation method).
 * Requires billing read permission.
 */
export async function getBillingJurisdiction(request: { auth?: { uid?: string }; data?: unknown }) {
  const uid = requireAuthUid(request);
  const data = asObject(request.data);
  const clinicId = requireString(data.clinicId, "clinicId", 2, 120);
  await requireBillingRead(clinicId, uid);

  const clinicRef = db.doc(`clinics/${clinicId}`);
  const clinicSnap = await clinicRef.get();
  const clinicData = clinicSnap.exists ? (clinicSnap.data() || {}) as Record<string, unknown> : null;
  const country = getClinicCountry(clinicData);
  const entry = getJurisdiction(country);

  if (!entry) {
    return {
      country: country ?? null,
      taxCalculationMethod: null,
      defaultTaxLabel: null,
      requiredInvoiceFields: [] as string[],
      invoiceTitleMode: null,
      requiredSellerFields: [] as string[],
      requiredBuyerFieldsWhenB2B: [] as string[],
      requiresReverseChargeNote: false,
      retentionYears: null,
    };
  }

  return {
    country,
    taxCalculationMethod: entry.taxCalculationMethod,
    defaultTaxLabel: entry.defaultTaxLabel,
    requiredInvoiceFields: entry.requiredInvoiceFields,
    invoiceTitleMode: entry.invoiceTitleMode,
    requiredSellerFields: entry.requiredSellerFields,
    requiredBuyerFieldsWhenB2B: entry.requiredBuyerFieldsWhenB2B,
    requiresReverseChargeNote: entry.requiresReverseChargeNote,
    retentionYears: entry.retentionYears,
  };
}
