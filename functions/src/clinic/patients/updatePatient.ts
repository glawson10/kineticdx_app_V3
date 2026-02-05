import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

type UpdateInput = {
  clinicId: string;
  patientId: string;

  // Patch fields (all optional)
  firstName?: string;
  lastName?: string;
  preferredName?: string | null;
  dateOfBirth?: string | null; // ISO or YYYY-MM-DD
  email?: string | null;
  phone?: string | null;
  preferredMethod?: "sms" | "email" | "call" | null;

  address?: {
    line1?: string | null;
    line2?: string | null;
    city?: string | null;
    postcode?: string | null;
    country?: string | null;
  } | null;

  emergencyContact?: {
    name?: string | null;
    relationship?: string | null;
    phone?: string | null;
  } | null;

  tags?: string[]; // replace whole list
  alerts?: string[]; // replace whole list
  adminNotes?: string | null;

  active?: boolean;
  archived?: boolean;
};

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

function normalizeEmail(v: unknown): string {
  const s = safeStr(v);
  return s ? s.toLowerCase() : "";
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

  return true; // missing active => active
}

function getPermissionsMap(data: Record<string, any>): Record<string, any> {
  const p = data.permissions;
  if (p && typeof p === "object") return p as Record<string, any>;
  return {};
}

async function getMembershipDataWithFallback(
  db: FirebaseFirestore.Firestore,
  clinicId: string,
  uid: string,
): Promise<Record<string, any> | null> {
  const canonRef = db.collection("clinics").doc(clinicId).collection("memberships").doc(uid);
  const canonSnap = await canonRef.get();
  if (canonSnap.exists) return (canonSnap.data() || {}) as Record<string, any>;

  const legacyRef = db.collection("clinics").doc(clinicId).collection("members").doc(uid);
  const legacySnap = await legacyRef.get();
  if (legacySnap.exists) return (legacySnap.data() || {}) as Record<string, any>;

  return null;
}

async function assertPatientWritePerm(
  db: FirebaseFirestore.Firestore,
  clinicId: string,
  uid: string,
) {
  const data = await getMembershipDataWithFallback(db, clinicId, uid);
  if (!data) throw new HttpsError("permission-denied", "Not a clinic member.");

  if (!isMemberActiveLike(data)) {
    throw new HttpsError("permission-denied", "Membership not active.");
  }

  const perms = getPermissionsMap(data);
  if (perms["patients.write"] !== true) {
    throw new HttpsError("permission-denied", "No patient write permission.");
  }
}

function parseDobToTimestampOrNull(dobIsoOrNull?: string | null) {
  if (dobIsoOrNull === undefined) return undefined; // not provided
  if (dobIsoOrNull === null) return null;

  const raw = safeStr(dobIsoOrNull);
  if (!raw) return null;

  const d = new Date(raw);
  if (Number.isNaN(d.getTime())) throw new HttpsError("invalid-argument", "Invalid dateOfBirth.");

  // Keep exact timestamp semantics for update (you can day-normalize if you prefer)
  return admin.firestore.Timestamp.fromDate(d);
}

export async function updatePatient(req: CallableRequest<UpdateInput>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = safeStr(req.data?.clinicId);
  const patientId = safeStr(req.data?.patientId);

  if (!clinicId || !patientId) {
    throw new HttpsError("invalid-argument", "clinicId and patientId required.");
  }

  const db = admin.firestore();
  const uid = req.auth.uid;

  await assertPatientWritePerm(db, clinicId, uid);

  const patientRef = db.collection("clinics").doc(clinicId).collection("patients").doc(patientId);
  const snap = await patientRef.get();
  if (!snap.exists) throw new HttpsError("not-found", "Patient not found.");

  const patch: Record<string, any> = {};
  const setIf = (path: string, value: any) => {
    if (value !== undefined) patch[path] = value;
  };

  // Identity
  if (req.data.firstName !== undefined) {
    const v = safeStr(req.data.firstName);
    setIf("identity.firstName", v);
    setIf("firstName", v); // legacy mirror
  }
  if (req.data.lastName !== undefined) {
    const v = safeStr(req.data.lastName);
    setIf("identity.lastName", v);
    setIf("lastName", v); // legacy mirror
  }

  setIf(
    "identity.preferredName",
    req.data.preferredName === undefined
      ? undefined
      : (req.data.preferredName?.toString().trim() ?? null),
  );

  const dobTs = parseDobToTimestampOrNull(req.data.dateOfBirth);
  if (dobTs !== undefined) {
    setIf("identity.dateOfBirth", dobTs);
    setIf("dob", dobTs); // legacy mirror
  }

  // Contact
  if (req.data.email !== undefined) {
    const e = req.data.email === null ? null : normalizeEmail(req.data.email);
    setIf("contact.email", e);
    setIf("email", e); // legacy mirror
  }
  if (req.data.phone !== undefined) {
    const p = req.data.phone === null ? null : safeStr(req.data.phone);
    setIf("contact.phone", p);
    setIf("phone", p); // legacy mirror
  }
  setIf("contact.preferredMethod", req.data.preferredMethod);

  // Address (partial)
  if (req.data.address !== undefined) {
    const a = req.data.address;
    if (a === null) {
      patch["contact.address"] = null;
    } else {
      setIf("contact.address.line1", a.line1 === undefined ? undefined : a.line1);
      setIf("contact.address.line2", a.line2 === undefined ? undefined : a.line2);
      setIf("contact.address.city", a.city === undefined ? undefined : a.city);
      setIf("contact.address.postcode", a.postcode === undefined ? undefined : a.postcode);
      setIf("contact.address.country", a.country === undefined ? undefined : a.country);
    }
  }

  // Emergency contact (partial)
  if (req.data.emergencyContact !== undefined) {
    const e = req.data.emergencyContact;
    if (e === null) {
      patch["emergencyContact"] = null;
    } else {
      setIf("emergencyContact.name", e.name === undefined ? undefined : e.name);
      setIf("emergencyContact.relationship", e.relationship === undefined ? undefined : e.relationship);
      setIf("emergencyContact.phone", e.phone === undefined ? undefined : e.phone);
    }
  }

  // Workflow/admin
  if (req.data.tags !== undefined) patch["tags"] = req.data.tags.map((t) => String(t));
  if (req.data.alerts !== undefined) patch["alerts"] = req.data.alerts.map((t) => String(t));
  if (req.data.adminNotes !== undefined) patch["adminNotes"] = req.data.adminNotes;

  // Status
  if (req.data.active !== undefined) {
    patch["status.active"] = req.data.active;
    patch["active"] = req.data.active; // legacy mirror
  }
  if (req.data.archived !== undefined) {
    patch["status.archived"] = req.data.archived;
    patch["status.archivedAt"] = req.data.archived
      ? admin.firestore.FieldValue.serverTimestamp()
      : null;

    // legacy mirror
    patch["archived"] = req.data.archived;
    patch["archivedAt"] = req.data.archived
      ? admin.firestore.FieldValue.serverTimestamp()
      : null;
  }

  // System
  patch["updatedAt"] = admin.firestore.FieldValue.serverTimestamp();
  patch["updatedByUid"] = uid;

  // Prevent empty update (Firestore rejects update({}) and it's also pointless)
  if (Object.keys(patch).length <= 2) {
    // updatedAt + updatedByUid only
    throw new HttpsError("invalid-argument", "No fields to update.");
  }

  await patientRef.update(patch);

  return { ok: true };
}
