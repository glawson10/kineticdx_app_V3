// functions/src/clinic/updateMember.ts
// membership.updateMember: update role and/or permissions for a member.
// Caller must have members.manage. Cannot demote the last active owner.

import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {
  requireActiveMemberWithPerm,
  countActiveOwners,
  getClinicMembershipSnap,
  isActiveMembership,
  flattenPermissions,
} from "./authz";
import type { MemberDoc } from "./authz";
import { ownerRolePermissions } from "./roleTemplates";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

type Input = {
  clinicId: string;
  memberUid: string;
  patch: {
    role?: string;
    permissions?: Record<string, boolean>;
  };
};

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

function isOwner(data: MemberDoc): boolean {
  const role = (safeStr(data.roleId) || safeStr(data.role)).toLowerCase();
  return role === "owner";
}

export async function updateMember(req: CallableRequest<Input>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = safeStr(req.data?.clinicId);
  const memberUid = safeStr(req.data?.memberUid);
  const patch = req.data?.patch;

  if (!clinicId || !memberUid) {
    throw new HttpsError("invalid-argument", "clinicId and memberUid are required.");
  }
  if (!patch || typeof patch !== "object") {
    throw new HttpsError("invalid-argument", "patch (role and/or permissions) is required.");
  }

  const actorUid = req.auth.uid;
  await requireActiveMemberWithPerm(db, clinicId, actorUid, "members.manage");

  const snap = await getClinicMembershipSnap(db, clinicId, memberUid);
  if (!snap) {
    throw new HttpsError("not-found", "Member not found.");
  }

  const existing = (snap.data() || {}) as MemberDoc;

  // Last-owner guard: cannot demote or remove permissions such that this member
  // would no longer be an owner if they are currently the last active owner.
  if (isOwner(existing) && isActiveMembership(existing)) {
    const newRole = safeStr(patch.role).toLowerCase();
    const becomingNonOwner = newRole.length > 0 && newRole !== "owner";

    const permsOverride = patch.permissions;
    const losingOwnerPerms =
      permsOverride &&
      typeof permsOverride === "object" &&
      (permsOverride["members.manage"] === false || permsOverride["settings.write"] === false);

    if (becomingNonOwner || losingOwnerPerms) {
      const ownerCount = await countActiveOwners(db, clinicId);
      if (ownerCount <= 1) {
        throw new HttpsError(
          "failed-precondition",
          "Cannot demote or remove the last active owner. Assign another owner first."
        );
      }
    }
  }

  const now = admin.firestore.FieldValue.serverTimestamp();

  const updates: Record<string, unknown> = {
    updatedAt: now,
    updatedByUid: actorUid,
  };

  if (patch.role !== undefined) {
    const role = safeStr(patch.role);
    if (role.length > 0) {
      updates.role = role;
      updates.roleId = role;
      if (role.toLowerCase() === "owner" && !(patch.permissions && typeof patch.permissions === "object")) {
        updates.permissions = ownerRolePermissions();
      }
    }
  }

  if (patch.permissions !== undefined && typeof patch.permissions === "object") {
    updates.permissions = flattenPermissions(patch.permissions);
  }

  const canonRef = db.doc(`clinics/${clinicId}/members/${memberUid}`);
  const legacyRef = db.doc(`clinics/${clinicId}/memberships/${memberUid}`);

  const batch = db.batch();
  batch.set(canonRef, updates, { merge: true });
  batch.set(legacyRef, updates, { merge: true });

  await batch.commit();

  const auditRef = db.collection(`clinics/${clinicId}/audit`).doc();
  await auditRef.set({
    type: "membership.updated",
    clinicId,
    actor: { uid: actorUid },
    subject: { uid: memberUid },
    patch: { role: patch.role, permissionsKeys: patch.permissions ? Object.keys(patch.permissions) : [] },
    at: now,
    schemaVersion: 1,
  });

  return { ok: true };
}
