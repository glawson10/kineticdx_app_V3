"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.updateBillingSettings = updateBillingSettings;
const https_1 = require("firebase-functions/v2/https");
const audit_1 = require("../audit/audit");
const common_1 = require("./common");
const jurisdictionRegistry_1 = require("./jurisdictionRegistry");
const ALLOWED_KEYS = new Set([
    "invoicePrefix",
    "nextInvoiceNumber",
    "defaultDueDays",
    "currency",
    "taxInclusivePricing",
    "schemaVersion",
    "businessDisplayName",
    "businessLegalName",
    "businessAddress",
    "businessCountry",
    "registrationNumber",
    "taxId",
    "businessPhone",
    "businessEmail",
    "businessWebsite",
    "defaultFooterText",
    "defaultInvoiceNotes",
    "defaultLocale",
    "invoiceTitle",
    "showLogoOnInvoice",
    "showPractitionerOnInvoice",
    "showBusinessContactOnInvoice",
    "groupTaxLinesOnInvoice",
]);
const INVOICE_PREFIX_MAX = 20;
const CURRENCY_MAX = 10;
const DEFAULT_DUE_DAYS_MAX = 365;
const NEXT_INVOICE_NUMBER_MAX = 1000000;
const STRING_FIELD_MAX = 500;
const TAX_ID_MAX = 50;
const LOCALE_MAX = 20;
const INVOICE_TITLE_MAX = 80;
function validatePatch(patchIn) {
    const patch = {};
    for (const [k, v] of Object.entries(patchIn)) {
        if (!ALLOWED_KEYS.has(k))
            continue;
        if (k === "invoicePrefix") {
            const s = v === null || v === undefined ? "" : String(v).trim();
            if (s.length > INVOICE_PREFIX_MAX) {
                throw new https_1.HttpsError("invalid-argument", `invoicePrefix must be <= ${INVOICE_PREFIX_MAX} characters.`);
            }
            patch[k] = s;
        }
        else if (k === "nextInvoiceNumber") {
            const n = (0, common_1.asInteger)(v, "nextInvoiceNumber", 0, NEXT_INVOICE_NUMBER_MAX);
            if (n === undefined)
                throw new https_1.HttpsError("invalid-argument", "nextInvoiceNumber must be an integer >= 0.");
            patch[k] = n;
        }
        else if (k === "defaultDueDays") {
            const n = (0, common_1.asInteger)(v, "defaultDueDays", 0, DEFAULT_DUE_DAYS_MAX);
            if (n === undefined)
                throw new https_1.HttpsError("invalid-argument", "defaultDueDays must be an integer between 0 and 365.");
            patch[k] = n;
        }
        else if (k === "currency") {
            const s = (0, common_1.optionalString)(v, "currency", CURRENCY_MAX);
            patch[k] = s === undefined || s === "" ? null : s;
        }
        else if (k === "taxInclusivePricing") {
            const b = (0, common_1.asBoolean)(v, "taxInclusivePricing");
            if (b === undefined)
                throw new https_1.HttpsError("invalid-argument", "taxInclusivePricing must be boolean.");
            patch[k] = b;
        }
        else if (k === "schemaVersion") {
            const n = (0, common_1.asInteger)(v, "schemaVersion", 1, 10);
            if (n !== undefined)
                patch[k] = n;
        }
        else if (k === "businessDisplayName" || k === "businessLegalName" || k === "businessAddress" ||
            k === "defaultFooterText" || k === "defaultInvoiceNotes") {
            const s = (0, common_1.optionalString)(v, k, STRING_FIELD_MAX);
            patch[k] = s === undefined || s === "" ? null : s;
        }
        else if (k === "businessCountry" || k === "businessPhone" || k === "businessEmail" || k === "businessWebsite") {
            const s = (0, common_1.optionalString)(v, k, STRING_FIELD_MAX);
            patch[k] = s === undefined || s === "" ? null : s;
        }
        else if (k === "registrationNumber" || k === "taxId") {
            const s = (0, common_1.optionalString)(v, k, TAX_ID_MAX);
            patch[k] = s === undefined || s === "" ? null : s;
        }
        else if (k === "defaultLocale") {
            const s = (0, common_1.optionalString)(v, k, LOCALE_MAX);
            patch[k] = s === undefined || s === "" ? null : s;
        }
        else if (k === "invoiceTitle") {
            const s = (0, common_1.optionalString)(v, k, INVOICE_TITLE_MAX);
            patch[k] = s === undefined || s === "" ? null : s;
        }
        else if (k === "showLogoOnInvoice" || k === "showPractitionerOnInvoice" ||
            k === "showBusinessContactOnInvoice" || k === "groupTaxLinesOnInvoice") {
            const b = (0, common_1.asBoolean)(v, k);
            if (b !== undefined)
                patch[k] = b;
        }
    }
    return patch;
}
async function updateBillingSettings(request) {
    const uid = (0, common_1.requireAuthUid)(request);
    const data = (0, common_1.asObject)(request.data);
    const clinicId = (0, common_1.requireString)(data.clinicId, "clinicId", 2, 120);
    await (0, common_1.requireBillingWrite)(clinicId, uid);
    const patchIn = (0, common_1.asObject)(data.patch);
    let patch = validatePatch(patchIn);
    const ref = (0, common_1.billingSettingsGeneralRef)(clinicId);
    const before = await ref.get();
    const existing = (before.exists ? before.data() || {} : {});
    // Default taxInclusivePricing from jurisdiction registry when neither existing nor patch set it.
    if (patch.taxInclusivePricing === undefined &&
        existing.taxInclusivePricing === undefined) {
        const clinicRef = common_1.db.doc(`clinics/${clinicId}`);
        const clinicSnap = await clinicRef.get();
        const clinicData = clinicSnap.exists ? (clinicSnap.data() || {}) : null;
        const country = (0, jurisdictionRegistry_1.getClinicCountry)(clinicData);
        const defaultTaxInclusive = (0, jurisdictionRegistry_1.getDefaultTaxInclusiveForCountry)(country);
        if (defaultTaxInclusive !== undefined) {
            patch = { ...patch, taxInclusivePricing: defaultTaxInclusive };
        }
    }
    if (Object.keys(patch).length === 0) {
        throw new https_1.HttpsError("invalid-argument", "No allowed billing settings fields provided.");
    }
    const now = common_1.FV.serverTimestamp();
    const writeData = { ...patch, updatedAt: now, updatedByUid: uid };
    if (Object.keys(patch).some((key) => key.startsWith("business") || key.startsWith("default") || key.startsWith("invoiceTitle") || key.startsWith("show") || key === "registrationNumber" || key === "taxId" || key === "schemaVersion")) {
        writeData.schemaVersion = 2;
    }
    await ref.set(writeData, { merge: true });
    const changes = {};
    for (const [k, v] of Object.entries(patch)) {
        changes[k] = { before: existing[k], after: v };
    }
    await (0, audit_1.writeSettingsAuditEvent)(ref.firestore, clinicId, "settings.billing.updated", uid, ref.path, "general", changes);
    return { ok: true };
}
//# sourceMappingURL=updateBillingSettings.js.map