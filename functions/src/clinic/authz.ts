import { Firestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

export type PermissionMap = Record<string, boolean>;

export type MemberDoc = {
  // legacy
  active?: boolean;

  // new lifecycle
  status?: "invited" | "active" | "suspended" | string;

  // role keys
  role?: string;
  roleId?: string;

  // permissions
  permissions?: PermissionMap;

  [k: string]: any;
};

function norm(s: unknown) {
  return (s ?? "").toString().trim();
}

/**
 * Canonical membership location (align with Firestore rules):
 *   clinics/{clinicId}/members/{uid}
 * Legacy fallback: clinics/{clinicId}/memberships/{uid}
 */
export async function getClinicMembershipSnap(db: Firestore, clinicId: string, uid: string) {
  const membersRef = db.doc(`clinics/${clinicId}/members/${uid}`);
  const membersSnap = await membersRef.get();
  if (membersSnap.exists) return membersSnap;

  const legacyRef = db.doc(`clinics/${clinicId}/memberships/${uid}`);
  const legacySnap = await legacyRef.get();
  if (legacySnap.exists) return legacySnap;

  return null;
}

/**
 * Back-compat membership active rules:
 * - If status is present:
 *    - "active" => active
 *    - "suspended" => inactive
 *    - "invited" => inactive (they should only use accept flow)
 * - Else if active field exists => must be true
 * - Else (missing active) => treat as active (matches your Firestore rules)
 */
export function isActiveMembership(data: MemberDoc): boolean {
  const status = norm(data.status).toLowerCase();
  if (status === "active") return true;
  if (status === "suspended") return false;
  if (status === "invited") return false;

  if ("active" in (data as any)) return data.active === true;

  return true; // missing active => active
}

export function flattenPermissions(rolePermissions: PermissionMap): PermissionMap {
  const flattened: PermissionMap = {};
  for (const k of Object.keys(rolePermissions ?? {})) {
    flattened[k] = rolePermissions[k] === true;
  }
  return flattened;
}

export async function requireActiveMember(
  db: Firestore,
  clinicId: string,
  uid: string
): Promise<MemberDoc> {
  const snap = await getClinicMembershipSnap(db, clinicId, uid);
  if (!snap) {
    throw new HttpsError("permission-denied", "Not a clinic member.");
  }

  const data = (snap.data() || {}) as MemberDoc;

  if (!isActiveMembership(data)) {
    throw new HttpsError("permission-denied", "Membership inactive.");
  }

  return data;
}

export async function requireActiveMemberWithPerm(
  db: Firestore,
  clinicId: string,
  uid: string,
  perm: string
): Promise<MemberDoc> {
  const member = await requireActiveMember(db, clinicId, uid);
  const perms = (member.permissions ?? {}) as PermissionMap;

  if (perms[perm] !== true) {
    throw new HttpsError("permission-denied", `Missing permission: ${perm}`);
  }

  return member;
}

export async function hasPerm(
  db: Firestore,
  clinicId: string,
  uid: string,
  perm: string
): Promise<boolean> {
  try {
    await requireActiveMemberWithPerm(db, clinicId, uid, perm);
    return true;
  } catch {
    return false;
  }
}

/**
 * Count active owners in clinic (members + memberships, distinct uids).
 * Used to enforce "cannot suspend/demote last owner".
 */
export async function countActiveOwners(db: Firestore, clinicId: string): Promise<number> {
  const membersRef = db.collection("clinics").doc(clinicId).collection("members");
  const membershipsRef = db.collection("clinics").doc(clinicId).collection("memberships");

  const [membersSnap, membershipsSnap] = await Promise.all([
    membersRef.get(),
    membershipsRef.get(),
  ]);

  const ownerUids = new Set<string>();

  for (const doc of membersSnap.docs) {
    const d = (doc.data() || {}) as MemberDoc;
    const role = (norm(d.roleId) || norm(d.role)).toLowerCase();
    if (role === "owner" && isActiveMembership(d)) ownerUids.add(doc.id);
  }
  for (const doc of membershipsSnap.docs) {
    const d = (doc.data() || {}) as MemberDoc;
    const role = (norm(d.roleId) || norm(d.role)).toLowerCase();
    if (role === "owner" && isActiveMembership(d)) ownerUids.add(doc.id);
  }

  return ownerUids.size;
}

/**
 * Notes policy:
 * - notes.write.own → can amend own notes
 * - notes.write.any → can amend any notes
 */
export async function requireCanAmendNote(
  db: Firestore,
  clinicId: string,
  actorUid: string,
  authorUid: string
): Promise<"own" | "any"> {
  const member = await requireActiveMember(db, clinicId, actorUid);
  const perms = (member.permissions ?? {}) as PermissionMap;

  if (actorUid === authorUid && perms["notes.write.own"] === true) {
    return "own";
  }

  if (perms["notes.write.any"] === true) {
    return "any";
  }

  throw new HttpsError("permission-denied", "You are not allowed to amend this note.");
}
