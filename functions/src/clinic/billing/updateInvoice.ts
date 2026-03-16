import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import { writeAuditEvent } from "../audit/audit";
import {
  db,
  FV,
  asObject,
  billingSettingsGeneralRef,
  invoicesCol,
  requireAuthUid,
  requireBillingWrite,
  requireString,
} from "./common";
import {
  getBillingJurisdiction,
  getClinicCountry,
  type BillingJurisdictionEntry,
  validateInvoiceForIssue,
  validateSellerAgainstJurisdiction,
} from "./jurisdictionRegistry";
import { computeInvoiceTotals, InvoiceLineInput } from "./totals";

type InvoiceStatus = "draft" | "issued" | "paid" | "void";

function parseStatus(value: unknown): InvoiceStatus | undefined {
  if (value === undefined) return undefined;
  const s = String(value).trim();
  if (s === "draft" || s === "issued" || s === "paid" || s === "void") return s;
  throw new HttpsError("invalid-argument", "status must be draft, issued, paid, or void.");
}

function validTransition(before: InvoiceStatus, after: InvoiceStatus): boolean {
  if (before === after) return true;
  if (before === "draft" && (after === "issued" || after === "void")) return true;
  if (before === "issued" && (after === "paid" || after === "void")) return true;
  return false;
}

/** Builds the frozen render snapshot for an issued invoice (Phase 4B contract). */
function buildIssuedSnapshot(
  settings: Record<string, unknown> | null,
  _clinicData: Record<string, unknown> | null,
  jurisdiction: BillingJurisdictionEntry | null,
  invoiceAtIssue: Record<string, unknown>,
  lineItems: Record<string, unknown>[]
): Record<string, unknown> {
  const s = settings ?? {};
  const sellerIdentity = {
    businessDisplayName: s.businessDisplayName ?? null,
    businessLegalName: s.businessLegalName ?? null,
    businessAddress: s.businessAddress ?? null,
    businessCountry: s.businessCountry ?? null,
    taxId: s.taxId ?? null,
    registrationNumber: s.registrationNumber ?? null,
    businessPhone: s.businessPhone ?? null,
    businessEmail: s.businessEmail ?? null,
    businessWebsite: s.businessWebsite ?? null,
  };
  const buyerIdentity = {
    patientId: invoiceAtIssue.patientId ?? null,
    buyerName: invoiceAtIssue.buyerName ?? null,
    buyerAddress: invoiceAtIssue.buyerAddress ?? null,
    buyerVatId: invoiceAtIssue.buyerVatId ?? null,
  };
  const numberingResult = {
    displayNumber: invoiceAtIssue.displayNumber ?? invoiceAtIssue.invoiceNumber ?? null,
  };
  const taxProfileSnapshot = {
    taxInclusivePricing: s.taxInclusivePricing === true,
    defaultTaxLabel: jurisdiction?.defaultTaxLabel ?? "Tax",
    invoiceTitleMode: jurisdiction?.invoiceTitleMode ?? "Invoice",
  };
  const currencyLocale = {
    currency: invoiceAtIssue.currency ?? s.currency ?? "USD",
    locale: s.defaultLocale ?? null,
  };
  const footerTemplateSnapshot = {
    defaultFooterText: s.defaultFooterText ?? null,
    defaultInvoiceNotes: s.defaultInvoiceNotes ?? null,
    invoiceTitle: s.invoiceTitle ?? null,
    showLogoOnInvoice: s.showLogoOnInvoice === true,
    showPractitionerOnInvoice: s.showPractitionerOnInvoice === true,
    showBusinessContactOnInvoice: s.showBusinessContactOnInvoice === true,
    groupTaxLinesOnInvoice: s.groupTaxLinesOnInvoice === true,
  };
  const lineItemPricingSnapshot = lineItems.map((line) => ({
    itemId: line.itemId,
    description: line.description,
    quantity: line.quantity,
    unitPrice: line.unitPrice,
    taxRate: line.taxRate,
    lineNet: line.lineNet,
    taxAmount: line.taxAmount,
    total: line.total,
    pricingSource: line.pricingSource ?? null,
    pricingSourceSnapshot: line.pricingSourceSnapshot ?? null,
  }));
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

export async function updateInvoice(request: { auth?: { uid?: string }; data?: unknown }) {
  const uid = requireAuthUid(request);
  const data = asObject(request.data);
  const clinicId = requireString(data.clinicId, "clinicId", 2, 120);
  const invoiceId = requireString(data.invoiceId, "invoiceId", 1, 120);
  await requireBillingWrite(clinicId, uid);

  const ref = invoicesCol(clinicId).doc(invoiceId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Invoice not found.");
  const existing = snap.data() || {};
  const beforeStatus = String(existing.status ?? "draft") as InvoiceStatus;

  const patch = asObject(data.patch);
  const maybeStatus = parseStatus(patch.status);
  if (maybeStatus && !validTransition(beforeStatus, maybeStatus)) {
    throw new HttpsError("failed-precondition", `Invalid status transition: ${beforeStatus} -> ${maybeStatus}`);
  }

  const update: Record<string, unknown> = { updatedAt: FV.serverTimestamp() };
  const changes: Record<string, unknown> = {};

  const isAlreadyIssuedOrFinal = beforeStatus === "issued" || beforeStatus === "paid" || beforeStatus === "void";
  if ((patch.lineItems !== undefined || patch.invoiceDiscount !== undefined) && !isAlreadyIssuedOrFinal) {
    const lineItems = (patch.lineItems ?? existing.lineItems) as InvoiceLineInput[];
    const invoiceDiscount = Number(patch.invoiceDiscount ?? existing.discountTotal ?? 0);
    const settingsRef = billingSettingsGeneralRef(clinicId);
    const settingsSnap = await settingsRef.get();
    const settings = settingsSnap.exists ? (settingsSnap.data() || {}) as Record<string, unknown> : {};
    const taxInclusive = settings.taxInclusivePricing === true;
    const totals = computeInvoiceTotals(lineItems, invoiceDiscount, { taxInclusive });
    update.lineItems = totals.lineItems;
    update.subtotal = totals.subtotal;
    update.discountTotal = totals.discountTotal;
    update.taxTotal = totals.taxTotal;
    update.total = totals.total;
    const amountPaid = Number(existing.amountPaid ?? 0);
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
    const balanceDue = Number(update.balanceDue ?? existing.balanceDue ?? 0);
    if (maybeStatus === "paid" && balanceDue > 0) {
      throw new HttpsError("failed-precondition", "Cannot mark invoice as paid while balanceDue > 0.");
    }
    if (maybeStatus === "issued") {
      const clinicRef = db.doc(`clinics/${clinicId}`);
      const clinicSnap = await clinicRef.get();
      const clinicData = clinicSnap.exists ? (clinicSnap.data() || {}) as Record<string, unknown> : null;
      const country = getClinicCountry(clinicData);
      const jurisdiction = country ? getBillingJurisdiction(country) : null;
      const settingsRef = billingSettingsGeneralRef(clinicId);
      const settingsSnap = await settingsRef.get();
      const settingsData = settingsSnap.exists ? (settingsSnap.data() || {}) as Record<string, unknown> : null;
      if (jurisdiction) {
        const sellerMissing = validateSellerAgainstJurisdiction(jurisdiction, settingsData);
        const invoiceMissing = validateInvoiceForIssue({ ...existing, ...update } as Record<string, unknown>, jurisdiction);
        if (sellerMissing.length > 0 || invoiceMissing.length > 0) {
          const parts: string[] = [];
          if (sellerMissing.length > 0) parts.push(`Missing seller: ${sellerMissing.join(", ")}`);
          if (invoiceMissing.length > 0) parts.push(`Missing invoice: ${invoiceMissing.join(", ")}`);
          throw new HttpsError("failed-precondition", `Cannot issue invoice. ${parts.join(". ")} Local accountant review recommended for your jurisdiction.`);
        }
      }
      // Issued invoice render snapshot contract: freeze at issue time so settings changes never rewrite this invoice.
      const issuedAt = admin.firestore.Timestamp.now();
      const invoiceAtIssue = { ...existing, ...update } as Record<string, unknown>;
      const lineItems = (invoiceAtIssue.lineItems ?? []) as Record<string, unknown>[];
      update.issuedAt = issuedAt;
      update.issuedSnapshot = buildIssuedSnapshot(settingsData, clinicData, jurisdiction, invoiceAtIssue, lineItems);
    }
    update.status = maybeStatus;
    changes.status = { before: beforeStatus, after: maybeStatus };
  }

  if (patch.dueDate !== undefined) {
    let dueDate: admin.firestore.Timestamp;
    const raw = patch.dueDate;
    if (raw && typeof (raw as { toDate?: () => Date }).toDate === "function") {
      dueDate = raw as admin.firestore.Timestamp;
    } else if (raw instanceof Date) {
      dueDate = admin.firestore.Timestamp.fromDate(raw);
    } else if (typeof raw === "number" && Number.isFinite(raw)) {
      dueDate = admin.firestore.Timestamp.fromMillis(raw);
    } else if (typeof raw === "string") {
      const d = new Date(raw);
      if (!Number.isFinite(d.getTime())) throw new HttpsError("invalid-argument", "dueDate must be a valid date.");
      dueDate = admin.firestore.Timestamp.fromDate(d);
    } else {
      throw new HttpsError("invalid-argument", "dueDate must be a Timestamp, Date, or ISO date string.");
    }
    const dueDateMs = dueDate.toMillis();
    const todayStart = new Date();
    todayStart.setUTCHours(0, 0, 0, 0);
    if (dueDateMs < todayStart.getTime()) {
      throw new HttpsError("invalid-argument", "dueDate cannot be in the past.");
    }
    update.dueDate = dueDate;
    changes.dueDate = { before: existing.dueDate, after: dueDate };
  }

  if (Object.keys(changes).length === 0) {
    throw new HttpsError("invalid-argument", "No valid invoice patch fields.");
  }

  await ref.update(update);
  await writeAuditEvent(ref.firestore, clinicId, {
    type: "billing.invoice.updated",
    actorUid: uid,
    patientId: String(existing.patientId ?? "").trim() || undefined,
    appointmentId: String(existing.appointmentId ?? "").trim() || undefined,
    metadata: { invoiceId, changes },
  });
  return { ok: true, invoiceId };
}
