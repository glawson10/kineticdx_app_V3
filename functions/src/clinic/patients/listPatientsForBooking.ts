/**
 * listPatientsForBookingFn
 * Server-side read of patients for the Find patient dialog (booking flow).
 * Requires patients.read. Returns a list of { id, firstName, lastName, dateOfBirth, phone, email, address }
 * so the client does not depend on Firestore rules or indexes for this query.
 */

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { requireClinicPermission } from "../permissions";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

function safeStr(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

function getNested(data: Record<string, unknown>, path: string): unknown {
  const parts = path.split(".");
  let cur: unknown = data;
  for (const p of parts) {
    if (cur == null || typeof cur !== "object") return undefined;
    cur = (cur as Record<string, unknown>)[p];
  }
  return cur;
}

function toDateOfBirth(v: unknown): string | null {
  if (v == null) return null;
  if (v instanceof admin.firestore.Timestamp) {
    const d = v.toDate();
    return d.toISOString().slice(0, 10);
  }
  if (typeof v === "string") {
    const parsed = new Date(v);
    if (!Number.isNaN(parsed.getTime())) return parsed.toISOString().slice(0, 10);
  }
  return null;
}

type PatientRow = {
  id: string;
  firstName: string;
  lastName: string;
  dateOfBirth: string | null;
  phone: string;
  email: string;
  address: string;
  isArchived: boolean;
  isMerged: boolean;
  isDeleted: boolean;
};

function docToRow(doc: admin.firestore.DocumentSnapshot): PatientRow {
  const data = (doc.data() || {}) as Record<string, unknown>;

  const identity = (data.identity as Record<string, unknown>) || {};
  const contact = (data.contact as Record<string, unknown>) || {};

  const firstName =
    safeStr(getNested(data, "identity.firstName") ?? data.firstName) ||
    safeStr(identity.firstName);
  const lastName =
    safeStr(getNested(data, "identity.lastName") ?? data.lastName) ||
    safeStr(identity.lastName);

  const dobRaw =
    getNested(data, "identity.dateOfBirth") ??
    data.dateOfBirth ??
    data.dob;
  const dateOfBirth = toDateOfBirth(dobRaw);

  const email =
    safeStr(getNested(data, "contact.email") ?? data.email) ||
    safeStr(contact.email);
  const phone =
    safeStr(getNested(data, "contact.phone") ?? data.phone) ||
    safeStr(contact.phone);

  const addressObj = (contact.address as Record<string, unknown>) || {};
  const addressFlat = safeStr(data.address);
  const address =
    addressFlat ||
    [addressObj.line1, addressObj.line2, addressObj.city, addressObj.postcode]
      .filter(Boolean)
      .map((x) => String(x).trim())
      .join(", ") ||
    "";

  const status = (data.status as Record<string, unknown>) || {};
  const isArchived =
    status.archived === true || data.archived === true;
  const isMerged =
    safeStr(data.mergedIntoPatientId).length > 0;
  const isDeleted = data.deletedAt != null;

  return {
    id: doc.id,
    firstName: firstName || "",
    lastName: lastName || "",
    dateOfBirth,
    phone: phone || "",
    email: email || "",
    address: address || "",
    isArchived,
    isMerged,
    isDeleted,
  };
}

export const listPatientsForBookingFn = onCall(
  { region: "europe-west3", cors: true },
  async (request: CallableRequest) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }

    const clinicId = safeStr((request.data as any)?.clinicId);
    if (!clinicId) {
      throw new HttpsError("invalid-argument", "clinicId is required.");
    }

    await requireClinicPermission(db, clinicId, request.auth.uid, "patients.read");

    const patientsRef = db.collection(`clinics/${clinicId}/patients`);
    const snap = await patientsRef
      .orderBy("lastName")
      .limit(300)
      .get();

    const patients = snap.docs.map(docToRow);

    return { patients };
  }
);
