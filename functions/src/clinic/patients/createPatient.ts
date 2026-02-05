// functions/src/clinic/patients/createPatient.ts
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

type Input = {
  clinicId: string;

  firstName: string;
  lastName: string;

  // Accept multiple keys (back-compat)
  dob?: string; // YYYY-MM-DD or ISO
  dateOfBirth?: string; // YYYY-MM-DD or ISO
  dateOfBirthIso?: string; // YYYY-MM-DD

  phone?: string;
  email?: string;
  address?: string;
};

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

function normalizeEmail(v: unknown): string {
  const s = safeStr(v).toLowerCase();
  return s;
}

function readBoolOrUndefined(v: any): boolean | undefined {
  if (v === true) return true;
  if (v === false) return false;
  return undefined;
}

function isMemberActiveLike(data: Record<string, any>): boolean {
  const status = safeStr(data.status);
  if (status === "suspended") return false;
  if (status === "invited") return false;

  const active = readBoolOrUndefined(data.active);
  if (active !== undefined) return active;

  return true;
}

function getPermissionsMap(data: Record<string, any>): Record<string, any> {
  const p = data.permissions;
  if (p && typeof p === "object") return p as Record<string, any>;
  return {};
}

async function getMembershipDataWithFallback(
  db: FirebaseFirestore.Firestore,
  clinicId: string,
  uid: string
): Promise<Record<string, any> | null> {
  const canonRef = db.collection("clinics").doc(clinicId).collection("memberships").doc(uid);
  const canonSnap = await canonRef.get();
  if (canonSnap.exists) return (canonSnap.data() || {}) as Record<string, any>;

  const legacyRef = db.collection("clinics").doc(clinicId).collection("members").doc(uid);
  const legacySnap = await legacyRef.get();
  if (legacySnap.exists) return (legacySnap.data() || {}) as Record<string, any>;

  return null;
}

async function assertPatientWritePerm(db: FirebaseFirestore.Firestore, clinicId: string, uid: string) {
  const data = await getMembershipDataWithFallback(db, clinicId, uid);
  if (!data) throw new HttpsError("permission-denied", "Not a clinic member.");

  if (!isMemberActiveLike(data)) {
    throw new HttpsError("permission-denied", "Membership not active.");
  }

  const perms = getPermissionsMap(data);
  if (perms["patients.write"] !== true) {
    // Owner/manager shortcut (optional):
    const roleId = safeStr(data.roleId ?? data.role).toLowerCase();
    if (roleId !== "owner" && roleId !== "manager") {
      throw new HttpsError("permission-denied", "No patient write permission.");
    }
  }
}

function pickDobString(data: Input): string {
  const s = safeStr(data.dob) || safeStr(data.dateOfBirth) || safeStr(data.dateOfBirthIso);
  return s;
}

function parseDobToDayTimestamp(dob: string): admin.firestore.Timestamp {
  const raw = safeStr(dob);
  if (!raw) throw new HttpsError("invalid-argument", "dob is required.");

  const d = new Date(raw);
  if (Number.isNaN(d.getTime())) throw new HttpsError("invalid-argument", "Invalid dob.");

  const day = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  return admin.firestore.Timestamp.fromDate(day);
}

export async function createPatient(req: CallableRequest<Input>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const data = (req.data ?? {}) as Input;

  const clinicId = safeStr(data.clinicId);
  const firstName = safeStr(data.firstName);
  const lastName = safeStr(data.lastName);

  const dobRaw = pickDobString(data);

  // phone/email optional (public booking might provide them, internal might not yet)
  const phone = safeStr(data.phone);
  const email = normalizeEmail(data.email);

  const address = safeStr(data.address);

  if (!clinicId || !firstName || !lastName) {
    throw new HttpsError("invalid-argument", "clinicId, firstName, lastName are required.");
  }

  const uid = req.auth.uid;
  const db = admin.firestore();

  await assertPatientWritePerm(db, clinicId, uid);

  const dobTs = dobRaw ? parseDobToDayTimestamp(dobRaw) : null;

  const ref = db.collection("clinics").doc(clinicId).collection("patients").doc();
  const now = admin.firestore.FieldValue.serverTimestamp();

  await ref.set({
    clinicId,

    // legacy/simple fields
    firstName,
    lastName,
    dob: dobTs,
    phone: phone || null,
    email: email || null,
    address: address || "",

    // canonical blocks
    identity: {
      firstName,
      lastName,
      preferredName: null,
      dateOfBirth: dobTs,
    },
    contact: {
      phone: phone || null,
      email: email || null,
      preferredMethod: null,
      address: address ? { line1: address } : null,
    },

    emergencyContact: null,
    tags: [],
    alerts: [],
    adminNotes: null,
    status: {
      active: true,
      archived: false,
      archivedAt: null,
    },

    createdByUid: uid,
    createdAt: now,
    updatedByUid: uid,
    updatedAt: now,
    schemaVersion: 1,
  });

  return { ok: true, patientId: ref.id };
}
