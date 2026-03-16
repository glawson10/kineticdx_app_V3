"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getBillingJurisdiction = getBillingJurisdiction;
const common_1 = require("./common");
const jurisdictionRegistry_1 = require("./jurisdictionRegistry");
/**
 * Returns billing jurisdiction hints for the clinic's country (for UI: tax label, calculation method).
 * Requires billing read permission.
 */
async function getBillingJurisdiction(request) {
    const uid = (0, common_1.requireAuthUid)(request);
    const data = (0, common_1.asObject)(request.data);
    const clinicId = (0, common_1.requireString)(data.clinicId, "clinicId", 2, 120);
    await (0, common_1.requireBillingRead)(clinicId, uid);
    const clinicRef = common_1.db.doc(`clinics/${clinicId}`);
    const clinicSnap = await clinicRef.get();
    const clinicData = clinicSnap.exists ? (clinicSnap.data() || {}) : null;
    const country = (0, jurisdictionRegistry_1.getClinicCountry)(clinicData);
    const entry = (0, jurisdictionRegistry_1.getBillingJurisdiction)(country);
    if (!entry) {
        return {
            country: country !== null && country !== void 0 ? country : null,
            taxCalculationMethod: null,
            defaultTaxLabel: null,
            requiredInvoiceFields: [],
            invoiceTitleMode: null,
            requiredSellerFields: [],
            requiredBuyerFieldsWhenB2B: [],
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
//# sourceMappingURL=getBillingJurisdiction.js.map