// functions/src/clinic/helpers.ts
import * as admin from "firebase-admin";
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";

type AnyMap = Record<string, any>;

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

// Back-compat: missing active => active
function isActiveMemberDoc(d: AnyMap): boolean {
  const status = safeStr(d?.status);
  if (status === "suspended") return false;
  if (status === "invited") return false;
  if ("active" in (d ?? {})) return d.active === true;
  return true;
}

/**
 * Canonical membership reader:
 * - primary: clinics/{clinicId}/memberships/{uid}
 * - legacy fallback: clinics/{clinicId}/members/{uid}
 */
export async function getMembershipDoc(
  db: admin.firestore.Firestore,
  clinicId: string,
  uid: string
) {
  const canonRef = db
    .collection("clinics")
    .doc(clinicId)
    .collection("memberships")
    .doc(uid);

  const canonSnap = await canonRef.get();
  if (canonSnap.exists) {
    return { path: canonRef.path, data: (canonSnap.data() ?? {}) as AnyMap };
  }

  // legacy fallback (temporary during migration)
  const legacyRef = db
    .collection("clinics")
    .doc(clinicId)
    .collection("members")
    .doc(uid);

  const legacySnap = await legacyRef.get();
  if (legacySnap.exists) {
    return { path: legacyRef.path, data: (legacySnap.data() ?? {}) as AnyMap };
  }

  return null;
}

/**
 * Require templates.manage permission on an active membership.
 */
export async function requireTemplatesManage(req: CallableRequest<any>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = safeStr(req.data?.clinicId);
  if (!clinicId) throw new HttpsError("invalid-argument", "clinicId required.");

  const db = admin.firestore();
  const uid = req.auth.uid;

  const m = await getMembershipDoc(db, clinicId, uid);
  if (!m) {
    throw new HttpsError("permission-denied", "Not a clinic member.");
  }

  const data = m.data;
  if (!isActiveMemberDoc(data)) {
    throw new HttpsError("permission-denied", "Not an active clinic member.");
  }

  const perms =
    data?.permissions && typeof data.permissions === "object"
      ? (data.permissions as AnyMap)
      : {};

  if (perms["templates.manage"] !== true) {
    throw new HttpsError("permission-denied", "No templates.manage permission.");
  }

  return { db, clinicId, uid, perms };
}

export function cleanString(v: any, max = 300) {
  const s = (v ?? "").toString().trim();
  if (!s) return "";
  return s.length > max ? s.substring(0, max) : s;
}

export function asStringArray(v: any) {
  if (!Array.isArray(v)) return [];
  return v
    .map((x) => (x ?? "").toString().trim())
    .filter((x) => x.length > 0);
}
