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
exports.updateInvoice = updateInvoice;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const audit_1 = require("../audit/audit");
const common_1 = require("./common");
const jurisdictionRegistry_1 = require("./jurisdictionRegistry");
const totals_1 = require("./totals");
function parseStatus(value) {
    if (value === undefined)
        return undefined;
    const s = String(value).trim();
    if (s === "draft" || s === "issued" || s === "paid" || s === "void")
        return s;
    throw new https_1.HttpsError("invalid-argument", "status must be draft, issued, paid, or void.");
}
function validTransition(before, after) {
    if (before === after)
        return true;
    if (before === "draft" && (after === "issued" || after === "void"))
        return true;
    if (before === "issued" && (after === "paid" || after === "void"))
        return true;
    return false;
}
/** Builds the frozen render snapshot for an issued invoice (Phase 4B contract). */
function buildIssuedSnapshot(settings, _clinicData, jurisdiction, invoiceAtIssue, lineItems) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q, _r, _s, _t, _u, _v, _w, _x, _y;
    const s = settings !== null && settings !== void 0 ? settings : {};
    const sellerIdentity = {
        businessDisplayName: (_a = s.businessDisplayName) !== null && _a !== void 0 ? _a : null,
        businessLegalName: (_b = s.businessLegalName) !== null && _b !== void 0 ? _b : null,
        businessAddress: (_c = s.businessAddress) !== null && _c !== void 0 ? _c : null,
        businessCountry: (_d = s.businessCountry) !== null && _d !== void 0 ? _d : null,
        taxId: (_e = s.taxId) !== null && _e !== void 0 ? _e : null,
        registrationNumber: (_f = s.registrationNumber) !== null && _f !== void 0 ? _f : null,
        businessPhone: (_g = s.businessPhone) !== null && _g !== void 0 ? _g : null,
        businessEmail: (_h = s.businessEmail) !== null && _h !== void 0 ? _h : null,
        businessWebsite: (_j = s.businessWebsite) !== null && _j !== void 0 ? _j : null,
    };
    const buyerIdentity = {
        patientId: (_k = invoiceAtIssue.patientId) !== null && _k !== void 0 ? _k : null,
        buyerName: (_l = invoiceAtIssue.buyerName) !== null && _l !== void 0 ? _l : null,
        buyerAddress: (_m = invoiceAtIssue.buyerAddress) !== null && _m !== void 0 ? _m : null,
        buyerVatId: (_o = invoiceAtIssue.buyerVatId) !== null && _o !== void 0 ? _o : null,
    };
    const numberingResult = {
        displayNumber: (_q = (_p = invoiceAtIssue.displayNumber) !== null && _p !== void 0 ? _p : invoiceAtIssue.invoiceNumber) !== null && _q !== void 0 ? _q : null,
    };
    const taxProfileSnapshot = {
        taxInclusivePricing: s.taxInclusivePricing === true,
        defaultTaxLabel: (_r = jurisdiction === null || jurisdiction === void 0 ? void 0 : jurisdiction.defaultTaxLabel) !== null && _r !== void 0 ? _r : "Tax",
        invoiceTitleMode: (_s = jurisdiction === null || jurisdiction === void 0 ? void 0 : jurisdiction.invoiceTitleMode) !== null && _s !== void 0 ? _s : "Invoice",
    };
    const currencyLocale = {
        currency: (_u = (_t = invoiceAtIssue.currency) !== null && _t !== void 0 ? _t : s.currency) !== null && _u !== void 0 ? _u : "USD",
        locale: (_v = s.defaultLocale) !== null && _v !== void 0 ? _v : null,
    };
    const footerTemplateSnapshot = {
        defaultFooterText: (_w = s.defaultFooterText) !== null && _w !== void 0 ? _w : null,
        defaultInvoiceNotes: (_x = s.defaultInvoiceNotes) !== null && _x !== void 0 ? _x : null,
        invoiceTitle: (_y = s.invoiceTitle) !== null && _y !== void 0 ? _y : null,
        showLogoOnInvoice: s.showLogoOnInvoice === true,
        showPractitionerOnInvoice: s.showPractitionerOnInvoice === true,
        showBusinessContactOnInvoice: s.showBusinessContactOnInvoice === true,
        groupTaxLinesOnInvoice: s.groupTaxLinesOnInvoice === true,
    };
    const lineItemPricingSnapshot = lineItems.map((line) => {
        var _a, _b;
        return ({
            itemId: line.itemId,
            description: line.description,
            quantity: line.quantity,
            unitPrice: line.unitPrice,
            taxRate: line.taxRate,
            lineNet: line.lineNet,
            taxAmount: line.taxAmount,
            total: line.total,
            pricingSource: (_a = line.pricingSource) !== null && _a !== void 0 ? _a : null,
            pricingSourceSnapshot: (_b = line.pricingSourceSnapshot) !== null && _b !== void 0 ? _b : null,
        });
    });
    const taxBreakdownSnapshot = {
        subtotal: invoiceAtIssue.subtotal,
        discountTotal: invoiceAtIssue.discountTotal,
        taxTotal: invoiceAtIssue.taxTotal,
        total: invoiceAtIssue.total,
    };
    return {
        sellerIdentity,
        buyerIdentity,
        numberingResult,
        taxProfileSnapshot,
        currencyLocale,
        footerTemplateSnapshot,
        lineItemPricingSnapshot,
        taxBreakdownSnapshot,
    };
}
async function updateInvoice(request) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k;
    const uid = (0, common_1.requireAuthUid)(request);
    const data = (0, common_1.asObject)(request.data);
    const clinicId = (0, common_1.requireString)(data.clinicId, "clinicId", 2, 120);
    const invoiceId = (0, common_1.requireString)(data.invoiceId, "invoiceId", 1, 120);
    await (0, common_1.requireBillingWrite)(clinicId, uid);
    const ref = (0, common_1.invoicesCol)(clinicId).doc(invoiceId);
    const snap = await ref.get();
    if (!snap.exists)
        throw new https_1.HttpsError("not-found", "Invoice not found.");
    const existing = snap.data() || {};
    const beforeStatus = String((_a = existing.status) !== null && _a !== void 0 ? _a : "draft");
    const patch = (0, common_1.asObject)(data.patch);
    const maybeStatus = parseStatus(patch.status);
    if (maybeStatus && !validTransition(beforeStatus, maybeStatus)) {
        throw new https_1.HttpsError("failed-precondition", `Invalid status transition: ${beforeStatus} -> ${maybeStatus}`);
    }
    const update = { updatedAt: common_1.FV.serverTimestamp() };
    const changes = {};
    const isAlreadyIssuedOrFinal = beforeStatus === "issued" || beforeStatus === "paid" || beforeStatus === "void";
    if ((patch.lineItems !== undefined || patch.invoiceDiscount !== undefined) && !isAlreadyIssuedOrFinal) {
        const lineItems = ((_b = patch.lineItems) !== null && _b !== void 0 ? _b : existing.lineItems);
        const invoiceDiscount = Number((_d = (_c = patch.invoiceDiscount) !== null && _c !== void 0 ? _c : existing.discountTotal) !== null && _d !== void 0 ? _d : 0);
        const settingsRef = (0, common_1.billingSettingsGeneralRef)(clinicId);
        const settingsSnap = await settingsRef.get();
        const settings = settingsSnap.exists ? (settingsSnap.data() || {}) : {};
        const taxInclusive = settings.taxInclusivePricing === true;
        const totals = (0, totals_1.computeInvoiceTotals)(lineItems, invoiceDiscount, { taxInclusive });
        update.lineItems = totals.lineItems;
        update.subtotal = totals.subtotal;
        update.discountTotal = totals.discountTotal;
        update.taxTotal = totals.taxTotal;
        update.total = totals.total;
        const amountPaid = Number((_e = existing.amountPaid) !== null && _e !== void 0 ? _e : 0);
        update.balanceDue = Math.max(0, Math.round((totals.total - amountPaid) * 100) / 100);
        changes.totals = {
            before: {
                subtotal: existing.subtotal,
                taxTotal: existing.taxTotal,
                total: existing.total,
            },
            after: {
                subtotal: totals.subtotal,
                taxTotal: totals.taxTotal,
                total: totals.total,
            },
        };
    }
    if (maybeStatus !== undefined) {
        const balanceDue = Number((_g = (_f = update.balanceDue) !== null && _f !== void 0 ? _f : existing.balanceDue) !== null && _g !== void 0 ? _g : 0);
        if (maybeStatus === "paid" && balanceDue > 0) {
            throw new https_1.HttpsError("failed-precondition", "Cannot mark invoice as paid while balanceDue > 0.");
        }
        if (maybeStatus === "issued") {
            const clinicRef = common_1.db.doc(`clinics/${clinicId}`);
            const clinicSnap = await clinicRef.get();
            const clinicData = clinicSnap.exists ? (clinicSnap.data() || {}) : null;
            const country = (0, jurisdictionRegistry_1.getClinicCountry)(clinicData);
            const jurisdiction = country ? (0, jurisdictionRegistry_1.getBillingJurisdiction)(country) : null;
            const settingsRef = (0, common_1.billingSettingsGeneralRef)(clinicId);
            const settingsSnap = await settingsRef.get();
            const settingsData = settingsSnap.exists ? (settingsSnap.data() || {}) : null;
            if (jurisdiction) {
                const sellerMissing = (0, jurisdictionRegistry_1.validateSellerAgainstJurisdiction)(jurisdiction, settingsData);
                const invoiceMissing = (0, jurisdictionRegistry_1.validateInvoiceForIssue)({ ...existing, ...update }, jurisdiction);
                if (sellerMissing.length > 0 || invoiceMissing.length > 0) {
                    const parts = [];
                    if (sellerMissing.length > 0)
                        parts.push(`Missing seller: ${sellerMissing.join(", ")}`);
                    if (invoiceMissing.length > 0)
                        parts.push(`Missing invoice: ${invoiceMissing.join(", ")}`);
                    throw new https_1.HttpsError("failed-precondition", `Cannot issue invoice. ${parts.join(". ")} Local accountant review recommended for your jurisdiction.`);
                }
            }
            // Issued invoice render snapshot contract: freeze at issue time so settings changes never rewrite this invoice.
            const issuedAt = admin.firestore.Timestamp.now();
            const invoiceAtIssue = { ...existing, ...update };
            const lineItems = ((_h = invoiceAtIssue.lineItems) !== null && _h !== void 0 ? _h : []);
            update.issuedAt = issuedAt;
            update.issuedSnapshot = buildIssuedSnapshot(settingsData, clinicData, jurisdiction, invoiceAtIssue, lineItems);
        }
        update.status = maybeStatus;
        changes.status = { before: beforeStatus, after: maybeStatus };
    }
    if (patch.dueDate !== undefined) {
        let dueDate;
        const raw = patch.dueDate;
        if (raw && typeof raw.toDate === "function") {
            dueDate = raw;
        }
        else if (raw instanceof Date) {
            dueDate = admin.firestore.Timestamp.fromDate(raw);
        }
        else if (typeof raw === "number" && Number.isFinite(raw)) {
            dueDate = admin.firestore.Timestamp.fromMillis(raw);
        }
        else if (typeof raw === "string") {
            const d = new Date(raw);
            if (!Number.isFinite(d.getTime()))
                throw new https_1.HttpsError("invalid-argument", "dueDate must be a valid date.");
            dueDate = admin.firestore.Timestamp.fromDate(d);
        }
        else {
            throw new https_1.HttpsError("invalid-argument", "dueDate must be a Timestamp, Date, or ISO date string.");
        }
        const dueDateMs = dueDate.toMillis();
        const todayStart = new Date();
        todayStart.setUTCHours(0, 0, 0, 0);
        if (dueDateMs < todayStart.getTime()) {
            throw new https_1.HttpsError("invalid-argument", "dueDate cannot be in the past.");
        }
        update.dueDate = dueDate;
        changes.dueDate = { before: existing.dueDate, after: dueDate };
    }
    if (Object.keys(changes).length === 0) {
        throw new https_1.HttpsError("invalid-argument", "No valid invoice patch fields.");
    }
    await ref.update(update);
    await (0, audit_1.writeAuditEvent)(ref.firestore, clinicId, {
        type: "billing.invoice.updated",
        actorUid: uid,
        patientId: String((_j = existing.patientId) !== null && _j !== void 0 ? _j : "").trim() || undefined,
        appointmentId: String((_k = existing.appointmentId) !== null && _k !== void 0 ? _k : "").trim() || undefined,
        metadata: { invoiceId, changes },
    });
    return { ok: true, invoiceId };
}
//# sourceMappingURL=updateInvoice.js.map