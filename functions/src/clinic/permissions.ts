// functions/src/clinic/permissions.ts
import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";

// Local copy to avoid TS module-resolution issues across configs.
export type PermissionMap = Record<string, boolean>;

function safeStr(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

function readPerms(raw: unknown): PermissionMap {
  if (!raw || typeof raw !== "object") return {};
  const m = raw as Record<string, unknown>;
  const out: PermissionMap = {};
  for (const k of Object.keys(m)) out[k] = m[k] === true;
  return out;
}

async function loadMemberDoc(
  db: admin.firestore.Firestore,
  clinicId: string,
  uid: string
): Promise<{
  exists: boolean;
  active: boolean;
  permissions: PermissionMap;
}> {
  // ✅ Primary path used by your Flutter self-check UI
  const ref = db.doc(`clinics/${clinicId}/members/${uid}`);
  const snap = await ref.get();

  if (snap.exists) {
    const d = snap.data() as any;
    return {
      exists: true,
      active: d?.active === true,
      permissions: readPerms(d?.permissions),
    };
  }

  // Optional fallback (only if you had an older schema)
  const legacyRef = db.doc(`clinics/${clinicId}/memberships/${uid}`);
  const legacySnap = await legacyRef.get();
  if (legacySnap.exists) {
    const d = legacySnap.data() as any;
    return {
      exists: true,
      active: d?.active === true,
      permissions: readPerms(d?.permissions),
    };
  }

  return { exists: false, active: false, permissions: {} };
}

/**
 * Enforce clinic permission based on member doc:
 * clinics/{clinicId}/members/{uid}.permissions[permKey] === true AND active === true
 */
export async function requireClinicPermission(
  db: admin.firestore.Firestore,
  clinicId: string,
  uid: string,
  permKey: string
): Promise<{
  active: boolean;
  permissions: PermissionMap;
}> {
  const c = safeStr(clinicId);
  const u = safeStr(uid);
  const k = safeStr(permKey);

  if (!c || !u || !k) {
    throw new HttpsError("invalid-argument", "Invalid permission check args.");
  }

  const member = await loadMemberDoc(db, c, u);

  if (!member.exists) {
    throw new HttpsError(
      "permission-denied",
      "No membership doc for uid in clinic."
    );
  }

  if (!member.active) {
    throw new HttpsError(
      "permission-denied",
      "Membership inactive for this clinic."
    );
  }

  if (member.permissions[k] !== true) {
    throw new HttpsError("permission-denied", `Missing permission: ${k}`);
  }

  // Returning this is handy for callers like updateNote
  return { active: member.active, permissions: member.permissions };
}
