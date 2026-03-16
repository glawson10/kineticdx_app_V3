"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.BILLING_REFUND_KEYS = exports.BILLING_WRITE_KEYS = exports.BILLING_READ_KEYS = exports.FV = exports.db = void 0;
exports.requireBillingRead = requireBillingRead;
exports.requireBillingWrite = requireBillingWrite;
exports.requireBillingRefund = requireBillingRefund;
exports.asObject = asObject;
exports.requireAuthUid = requireAuthUid;
exports.requireString = requireString;
exports.optionalString = optionalString;
exports.requireBoolean = requireBoolean;
exports.asBoolean = asBoolean;
exports.asNonNegativeNumber = asNonNegativeNumber;
exports.requireNonNegativeNumber = requireNonNegativeNumber;
exports.asInteger = asInteger;
exports.roundMoney = roundMoney;
exports.taxesCol = taxesCol;
exports.paymentTypesCol = paymentTypesCol;
exports.billableItemsCol = billableItemsCol;
exports.productsCol = productsCol;
exports.invoicesCol = invoicesCol;
exports.paymentsCol = paymentsCol;
exports.creditNotesCol = creditNotesCol;
exports.refundsCol = refundsCol;
exports.billingSettingsGeneralRef = billingSettingsGeneralRef;
exports.billingPricingSettingsRef = billingPricingSettingsRef;
exports.billingPractitionerRatesCol = billingPractitionerRatesCol;
exports.billingClientPricingOverridesCol = billingClientPricingOverridesCol;
exports.billingAppointmentTypePractitionerPricesCol = billingAppointmentTypePractitionerPricesCol;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const permissions_1 = require("../permissions");
exports.db = admin.firestore();
exports.FV = admin.firestore.FieldValue;
exports.BILLING_READ_KEYS = ["manageBilling", "billing.manage", "billing.read", "viewFinancialReports"];
exports.BILLING_WRITE_KEYS = ["manageBilling", "billing.manage", "billing.write", "settings.write"];
exports.BILLING_REFUND_KEYS = ["issueRefunds", "billing.refunds", "billing.manage", "manageBilling"];
async function requireBillingRead(clinicId, uid) {
    await (0, permissions_1.requireAnyClinicPermission)(exports.db, clinicId, uid, exports.BILLING_READ_KEYS);
}
async function requireBillingWrite(clinicId, uid) {
    await (0, permissions_1.requireAnyClinicPermission)(exports.db, clinicId, uid, exports.BILLING_WRITE_KEYS);
}
async function requireBillingRefund(clinicId, uid) {
    await (0, permissions_1.requireAnyClinicPermission)(exports.db, clinicId, uid, exports.BILLING_REFUND_KEYS);
}
function asObject(v) {
    return (v && typeof v === "object") ? v : {};
}
function requireAuthUid(request) {
    var _a, _b;
    const uid = String((_b = (_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid) !== null && _b !== void 0 ? _b : "").trim();
    if (!uid) {
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    }
    return uid;
}
function requireString(value, name, min = 1, max = 200) {
    const s = String(value !== null && value !== void 0 ? value : "").trim();
    if (!s)
        throw new https_1.HttpsError("invalid-argument", `${name} is required.`);
    if (s.length < min || s.length > max) {
        throw new https_1.HttpsError("invalid-argument", `${name} must be ${min}-${max} characters.`);
    }
    return s;
}
function optionalString(value, name, max = 200) {
    if (value === undefined)
        return undefined;
    if (value === null)
        return "";
    const s = String(value).trim();
    if (s.length > max)
        throw new https_1.HttpsError("invalid-argument", `${name} must be <= ${max} characters.`);
    return s;
}
function requireBoolean(value, name) {
    if (typeof value !== "boolean")
        throw new https_1.HttpsError("invalid-argument", `${name} must be boolean.`);
    return value;
}
function asBoolean(value, name) {
    if (value === undefined)
        return undefined;
    if (typeof value !== "boolean")
        throw new https_1.HttpsError("invalid-argument", `${name} must be boolean.`);
    return value;
}
function asNonNegativeNumber(value, name, max = 1000000000) {
    if (value === undefined)
        return undefined;
    const n = Number(value);
    if (!Number.isFinite(n) || n < 0 || n > max) {
        throw new https_1.HttpsError("invalid-argument", `${name} must be a non-negative number.`);
    }
    return roundMoney(n);
}
function requireNonNegativeNumber(value, name, max = 1000000000) {
    const out = asNonNegativeNumber(value, name, max);
    if (out === undefined)
        throw new https_1.HttpsError("invalid-argument", `${name} is required.`);
    return out;
}
function asInteger(value, name, min = 0, max = 1000000) {
    if (value === undefined)
        return undefined;
    const n = Number(value);
    if (!Number.isInteger(n) || n < min || n > max) {
        throw new https_1.HttpsError("invalid-argument", `${name} must be an integer between ${min} and ${max}.`);
    }
    return n;
}
function roundMoney(n) {
    return Math.round(n * 100) / 100;
}
function taxesCol(clinicId) {
    return exports.db.collection("clinics").doc(clinicId).collection("taxes");
}
function paymentTypesCol(clinicId) {
    return exports.db.collection("clinics").doc(clinicId).collection("paymentTypes");
}
function billableItemsCol(clinicId) {
    return exports.db.collection("clinics").doc(clinicId).collection("billableItems");
}
function productsCol(clinicId) {
    return exports.db.collection("clinics").doc(clinicId).collection("products");
}
function invoicesCol(clinicId) {
    return exports.db.collection("clinics").doc(clinicId).collection("invoices");
}
function paymentsCol(clinicId) {
    return exports.db.collection("clinics").doc(clinicId).collection("payments");
}
function creditNotesCol(clinicId) {
    return exports.db.collection("clinics").doc(clinicId).collection("creditNotes");
}
function refundsCol(clinicId) {
    return exports.db.collection("clinics").doc(clinicId).collection("refunds");
}
/** Billing general settings doc: clinics/{clinicId}/billing/_/settings/general. Created on first update or first invoice. */
function billingSettingsGeneralRef(clinicId) {
    return exports.db.doc(`clinics/${clinicId}/billing/_/settings/general`);
}
/** Clinic-level pricing config: default fallback + duration rounding. clinics/{clinicId}/billing/_/settings/pricing */
function billingPricingSettingsRef(clinicId) {
    return exports.db.doc(`clinics/${clinicId}/billing/_/settings/pricing`);
}
/** Practitioner hourly rate: clinics/{clinicId}/billing/_/practitionerRates/{practitionerId} */
function billingPractitionerRatesCol(clinicId) {
    return exports.db.collection("clinics").doc(clinicId).collection("billing").doc("_").collection("practitionerRates");
}
/** Client pricing override: clinics/{clinicId}/billing/_/clientPricingOverrides/{patientId} */
function billingClientPricingOverridesCol(clinicId) {
    return exports.db.collection("clinics").doc(clinicId).collection("billing").doc("_").collection("clientPricingOverrides");
}
/** Appointment-type practitioner override price: clinics/{clinicId}/billing/_/appointmentTypePractitionerPrices/{appointmentTypeId} */
function billingAppointmentTypePractitionerPricesCol(clinicId) {
    return exports.db.collection("clinics").doc(clinicId).collection("billing").doc("_").collection("appointmentTypePractitionerPrices");
}
//# sourceMappingURL=common.js.map