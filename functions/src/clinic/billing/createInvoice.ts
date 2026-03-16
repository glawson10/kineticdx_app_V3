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
import { computeInvoiceTotals, InvoiceLineInput } from "./totals";

type InvoiceStatus = "draft" | "issued" | "paid" | "void";

const DEFAULT_NEXT_INVOICE_NUMBER = 1;
const DEFAULT_DUE_DAYS = 30;
const DEFAULT_CURRENCY = "USD";

function parseStatus(value: unknown): InvoiceStatus {
  const s = String(value ?? "draft").trim();
  if (s === "draft" || s === "issued" || s === "paid" || s === "void") return s;
  throw new HttpsError("invalid-argument", "status must be draft, issued, paid, or void.");
}

function resolveCurrency(settingsCurrency: unknown, clinicData: Record<string, unknown> | null): string {
  const s = settingsCurrency != null ? String(settingsCurrency).trim() : "";
  if (s) return s;
  const profile = clinicData?.profile as Record<string, unknown> | undefined;
  const fromProfile = profile?.currency ?? profile?.currencyCode;
  const fromRoot = clinicData?.currencyCode ?? clinicData?.currency;
  const c = fromProfile != null ? String(fromProfile).trim() : (fromRoot != null ? String(fromRoot).trim() : "");
  return c || DEFAULT_CURRENCY;
}

export async function createInvoice(request: { auth?: { uid?: string }; data?: unknown }) {
  const uid = requireAuthUid(request);
  const data = asObject(request.data);
  const clinicId = requireString(data.clinicId, "clinicId", 2, 120);
  await requireBillingWrite(clinicId, uid);

  const patientId = requireString(data.patientId, "patientId", 1, 120);
  const appointmentIdRaw = String(data.appointmentId ?? "").trim();
  const appointmentId = appointmentIdRaw.length > 0 ? appointmentIdRaw : null;
  const inputItems = (data.lineItems as InvoiceLineInput[]) ?? [];
  const invoiceDiscount = Number(data.invoiceDiscount ?? 0);

  const status: InvoiceStatus = parseStatus(data.status ?? "draft");

  const settingsRef = billingSettingsGeneralRef(clinicId);
  const clinicRef = db.doc(`clinics/${clinicId}`);
  const invoicesRef = invoicesCol(clinicId);
  let invoiceId!: string;
  let totalsOut: { total: number; taxTotal: number; discountTotal: number; lineItems: unknown[] } = {
    total: 0,
    taxTotal: 0,
    discountTotal: 0,
    lineItems: [],
  };

  await db.runTransaction(async (tx) => {
    const [settingsSnap, clinicSnap] = await Promise.all([
      tx.get(settingsRef),
      tx.get(clinicRef),
    ]);
    const settings = settingsSnap.exists ? (settingsSnap.data() || {}) as Record<string, unknown> : {};
    const clinicData = clinicSnap.exists ? (clinicSnap.data() || {}) as Record<string, unknown> : null;

    const taxInclusive = settings.taxInclusivePricing === true;
    const totals = computeInvoiceTotals(inputItems, invoiceDiscount, { taxInclusive });
    totalsOut = totals;

    const invoicePrefix = (settings.invoicePrefix != null ? String(settings.invoicePrefix) : "").trim();
    const nextNum = typeof settings.nextInvoiceNumber === "number" && Number.isInteger(settings.nextInvoiceNumber) && settings.nextInvoiceNumber >= 0
      ? settings.nextInvoiceNumber
      : DEFAULT_NEXT_INVOICE_NUMBER;
    const defaultDueDays = typeof settings.defaultDueDays === "number" && Number.isInteger(settings.defaultDueDays) && settings.defaultDueDays >= 0
      ? Math.min(365, settings.defaultDueDays)
      : DEFAULT_DUE_DAYS;

    const currency = resolveCurrency(settings.currency, clinicData);
    const nowDate = new Date();
    const dueDate = admin.firestore.Timestamp.fromMillis(
      nowDate.getTime() + defaultDueDays * 86_400_000
    );
    const displayNumber = invoicePrefix + nextNum;

    const ref = invoicesRef.doc();
    invoiceId = ref.id;
    const doc = {
      patientId,
      appointmentId,
      status: status === "paid" ? "issued" : status,
      lineItems: totals.lineItems,
      subtotal: totals.subtotal,
      discountTotal: totals.discountTotal,
      taxTotal: totals.taxTotal,
      total: totals.total,
      amountPaid: 0,
      balanceDue: totals.total,
      paymentStatus: "unpaid",
      dueDate,
      displayNumber,
      currency,
      createdAt: FV.serverTimestamp(),
      updatedAt: FV.serverTimestamp(),
    };
    tx.set(ref, doc);
    tx.set(settingsRef, { nextInvoiceNumber: nextNum + 1, updatedAt: FV.serverTimestamp(), updatedByUid: uid }, { merge: true });
  });

  const ref = invoicesCol(clinicId).doc(invoiceId);
  await writeAuditEvent(ref.firestore, clinicId, {
    type: "billing.invoice.created",
    actorUid: uid,
    patientId,
    appointmentId: appointmentId ?? undefined,
    metadata: {
      invoiceId,
      status: status === "paid" ? "issued" : status,
      total: totalsOut.total,
      taxTotal: totalsOut.taxTotal,
      discountTotal: totalsOut.discountTotal,
      lineItemCount: totalsOut.lineItems.length,
    },
  });
  return { ok: true, invoiceId };
}
