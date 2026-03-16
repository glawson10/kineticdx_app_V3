import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import { requireAnyClinicPermission } from "../permissions";

export const db = admin.firestore();
export const FV = admin.firestore.FieldValue;

export const BILLING_READ_KEYS = ["manageBilling", "billing.manage", "billing.read", "viewFinancialReports"];
export const BILLING_WRITE_KEYS = ["manageBilling", "billing.manage", "billing.write", "settings.write"];
export const BILLING_REFUND_KEYS = ["issueRefunds", "billing.refunds", "billing.manage", "manageBilling"];

export async function requireBillingRead(clinicId: string, uid: string): Promise<void> {
  await requireAnyClinicPermission(db, clinicId, uid, BILLING_READ_KEYS);
}

export async function requireBillingWrite(clinicId: string, uid: string): Promise<void> {
  await requireAnyClinicPermission(db, clinicId, uid, BILLING_WRITE_KEYS);
}

export async function requireBillingRefund(clinicId: string, uid: string): Promise<void> {
  await requireAnyClinicPermission(db, clinicId, uid, BILLING_REFUND_KEYS);
}

export function asObject(v: unknown): Record<string, unknown> {
  return (v && typeof v === "object") ? (v as Record<string, unknown>) : {};
}

export function requireAuthUid(request: { auth?: { uid?: string } }): string {
  const uid = String(request.auth?.uid ?? "").trim();
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  return uid;
}

export function requireString(value: unknown, name: string, min = 1, max = 200): string {
  const s = String(value ?? "").trim();
  if (!s) throw new HttpsError("invalid-argument", `${name} is required.`);
  if (s.length < min || s.length > max) {
    throw new HttpsError("invalid-argument", `${name} must be ${min}-${max} characters.`);
  }
  return s;
}

export function optionalString(value: unknown, name: string, max = 200): string | undefined {
  if (value === undefined) return undefined;
  if (value === null) return "";
  const s = String(value).trim();
  if (s.length > max) throw new HttpsError("invalid-argument", `${name} must be <= ${max} characters.`);
  return s;
}

export function requireBoolean(value: unknown, name: string): boolean {
  if (typeof value !== "boolean") throw new HttpsError("invalid-argument", `${name} must be boolean.`);
  return value;
}

export function asBoolean(value: unknown, name: string): boolean | undefined {
  if (value === undefined) return undefined;
  if (typeof value !== "boolean") throw new HttpsError("invalid-argument", `${name} must be boolean.`);
  return value;
}

export function asNonNegativeNumber(value: unknown, name: string, max = 1_000_000_000): number | undefined {
  if (value === undefined) return undefined;
  const n = Number(value);
  if (!Number.isFinite(n) || n < 0 || n > max) {
    throw new HttpsError("invalid-argument", `${name} must be a non-negative number.`);
  }
  return roundMoney(n);
}

export function requireNonNegativeNumber(value: unknown, name: string, max = 1_000_000_000): number {
  const out = asNonNegativeNumber(value, name, max);
  if (out === undefined) throw new HttpsError("invalid-argument", `${name} is required.`);
  return out;
}

export function asInteger(value: unknown, name: string, min = 0, max = 1_000_000): number | undefined {
  if (value === undefined) return undefined;
  const n = Number(value);
  if (!Number.isInteger(n) || n < min || n > max) {
    throw new HttpsError("invalid-argument", `${name} must be an integer between ${min} and ${max}.`);
  }
  return n;
}

export function roundMoney(n: number): number {
  return Math.round(n * 100) / 100;
}

export function taxesCol(clinicId: string) {
  return db.collection("clinics").doc(clinicId).collection("taxes");
}

export function paymentTypesCol(clinicId: string) {
  return db.collection("clinics").doc(clinicId).collection("paymentTypes");
}

export function billableItemsCol(clinicId: string) {
  return db.collection("clinics").doc(clinicId).collection("billableItems");
}

export function productsCol(clinicId: string) {
  return db.collection("clinics").doc(clinicId).collection("products");
}

export function invoicesCol(clinicId: string) {
  return db.collection("clinics").doc(clinicId).collection("invoices");
}

export function paymentsCol(clinicId: string) {
  return db.collection("clinics").doc(clinicId).collection("payments");
}

export function creditNotesCol(clinicId: string) {
  return db.collection("clinics").doc(clinicId).collection("creditNotes");
}

export function refundsCol(clinicId: string) {
  return db.collection("clinics").doc(clinicId).collection("refunds");
}

/** Billing general settings doc: clinics/{clinicId}/billing/_/settings/general. Created on first update or first invoice. */
export function billingSettingsGeneralRef(clinicId: string) {
  return db.doc(`clinics/${clinicId}/billing/_/settings/general`);
}

/** Clinic-level pricing config: default fallback + duration rounding. clinics/{clinicId}/billing/_/settings/pricing */
export function billingPricingSettingsRef(clinicId: string) {
  return db.doc(`clinics/${clinicId}/billing/_/settings/pricing`);
}

/** Practitioner hourly rate: clinics/{clinicId}/billing/_/practitionerRates/{practitionerId} */
export function billingPractitionerRatesCol(clinicId: string) {
  return db.collection("clinics").doc(clinicId).collection("billing").doc("_").collection("practitionerRates");
}

/** Client pricing override: clinics/{clinicId}/billing/_/clientPricingOverrides/{patientId} */
export function billingClientPricingOverridesCol(clinicId: string) {
  return db.collection("clinics").doc(clinicId).collection("billing").doc("_").collection("clientPricingOverrides");
}

/** Appointment-type practitioner override price: clinics/{clinicId}/billing/_/appointmentTypePractitionerPrices/{appointmentTypeId} */
export function billingAppointmentTypePractitionerPricesCol(clinicId: string) {
  return db.collection("clinics").doc(clinicId).collection("billing").doc("_").collection("appointmentTypePractitionerPrices");
}
