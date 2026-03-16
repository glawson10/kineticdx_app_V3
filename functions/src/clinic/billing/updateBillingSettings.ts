import { HttpsError } from "firebase-functions/v2/https";
import { writeSettingsAuditEvent } from "../audit/audit";
import {
  db,
  FV,
  asBoolean,
  asInteger,
  asObject,
  billingSettingsGeneralRef,
  optionalString,
  requireAuthUid,
  requireBillingWrite,
  requireString,
} from "./common";
import {
  getClinicCountry,
  getDefaultTaxInclusiveForCountry,
} from "./jurisdictionRegistry";

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
const NEXT_INVOICE_NUMBER_MAX = 1_000_000;
const STRING_FIELD_MAX = 500;
const TAX_ID_MAX = 50;
const LOCALE_MAX = 20;
const INVOICE_TITLE_MAX = 80;

function validatePatch(patchIn: Record<string, unknown>): Record<string, unknown> {
  const patch: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(patchIn)) {
    if (!ALLOWED_KEYS.has(k)) continue;
    if (k === "invoicePrefix") {
      const s = v === null || v === undefined ? "" : String(v).trim();
      if (s.length > INVOICE_PREFIX_MAX) {
        throw new HttpsError("invalid-argument", `invoicePrefix must be <= ${INVOICE_PREFIX_MAX} characters.`);
      }
      patch[k] = s;
    } else if (k === "nextInvoiceNumber") {
      const n = asInteger(v, "nextInvoiceNumber", 0, NEXT_INVOICE_NUMBER_MAX);
      if (n === undefined) throw new HttpsError("invalid-argument", "nextInvoiceNumber must be an integer >= 0.");
      patch[k] = n;
    } else if (k === "defaultDueDays") {
      const n = asInteger(v, "defaultDueDays", 0, DEFAULT_DUE_DAYS_MAX);
      if (n === undefined) throw new HttpsError("invalid-argument", "defaultDueDays must be an integer between 0 and 365.");
      patch[k] = n;
    } else if (k === "currency") {
      const s = optionalString(v, "currency", CURRENCY_MAX);
      patch[k] = s === undefined || s === "" ? null : s;
    } else if (k === "taxInclusivePricing") {
      const b = asBoolean(v, "taxInclusivePricing");
      if (b === undefined) throw new HttpsError("invalid-argument", "taxInclusivePricing must be boolean.");
      patch[k] = b;
    } else if (k === "schemaVersion") {
      const n = asInteger(v, "schemaVersion", 1, 10);
      if (n !== undefined) patch[k] = n;
    } else if (
      k === "businessDisplayName" || k === "businessLegalName" || k === "businessAddress" ||
      k === "defaultFooterText" || k === "defaultInvoiceNotes"
    ) {
      const s = optionalString(v, k, STRING_FIELD_MAX);
      patch[k] = s === undefined || s === "" ? null : s;
    } else if (k === "businessCountry" || k === "businessPhone" || k === "businessEmail" || k === "businessWebsite") {
      const s = optionalString(v, k, STRING_FIELD_MAX);
      patch[k] = s === undefined || s === "" ? null : s;
    } else if (k === "registrationNumber" || k === "taxId") {
      const s = optionalString(v, k, TAX_ID_MAX);
      patch[k] = s === undefined || s === "" ? null : s;
    } else if (k === "defaultLocale") {
      const s = optionalString(v, k, LOCALE_MAX);
      patch[k] = s === undefined || s === "" ? null : s;
    } else if (k === "invoiceTitle") {
      const s = optionalString(v, k, INVOICE_TITLE_MAX);
      patch[k] = s === undefined || s === "" ? null : s;
    } else if (
      k === "showLogoOnInvoice" || k === "showPractitionerOnInvoice" ||
      k === "showBusinessContactOnInvoice" || k === "groupTaxLinesOnInvoice"
    ) {
      const b = asBoolean(v, k);
      if (b !== undefined) patch[k] = b;
    }
  }
  return patch;
}

export async function updateBillingSettings(request: { auth?: { uid?: string }; data?: unknown }) {
  const uid = requireAuthUid(request);
  const data = asObject(request.data);
  const clinicId = requireString(data.clinicId, "clinicId", 2, 120);
  await requireBillingWrite(clinicId, uid);

  const patchIn = asObject(data.patch);
  let patch = validatePatch(patchIn);

  const ref = billingSettingsGeneralRef(clinicId);
  const before = await ref.get();
  const existing = (before.exists ? before.data() || {} : {}) as Record<string, unknown>;

  // Default taxInclusivePricing from jurisdiction registry when neither existing nor patch set it.
  if (
    patch.taxInclusivePricing === undefined &&
    existing.taxInclusivePricing === undefined
  ) {
    const clinicRef = db.doc(`clinics/${clinicId}`);
    const clinicSnap = await clinicRef.get();
    const clinicData = clinicSnap.exists ? (clinicSnap.data() || {}) as Record<string, unknown> : null;
    const country = getClinicCountry(clinicData);
    const defaultTaxInclusive = getDefaultTaxInclusiveForCountry(country);
    if (defaultTaxInclusive !== undefined) {
      patch = { ...patch, taxInclusivePricing: defaultTaxInclusive };
    }
  }

  if (Object.keys(patch).length === 0) {
    throw new HttpsError("invalid-argument", "No allowed billing settings fields provided.");
  }

  const now = FV.serverTimestamp();
  const writeData: Record<string, unknown> = { ...patch, updatedAt: now, updatedByUid: uid };
  if (Object.keys(patch).some((key) => key.startsWith("business") || key.startsWith("default") || key.startsWith("invoiceTitle") || key.startsWith("show") || key === "registrationNumber" || key === "taxId" || key === "schemaVersion")) {
    writeData.schemaVersion = 2;
  }
  await ref.set(writeData, { merge: true });

  const changes: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(patch)) {
    changes[k] = { before: (existing as Record<string, unknown>)[k], after: v };
  }
  await writeSettingsAuditEvent(
    ref.firestore,
    clinicId,
    "settings.billing.updated",
    uid,
    ref.path,
    "general",
    changes
  );
  return { ok: true };
}
