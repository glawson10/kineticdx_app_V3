import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { requireActiveMemberWithPerm, countActiveOwners, getClinicMembershipSnap, isActiveMembership } from "./authz";
import type { MemberDoc } from "./authz";

type Input = {
  clinicId: string;
  memberUid: string;
  status: "active" | "suspended";
};

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

function normalizeStatus(v: unknown): "active" | "suspended" {
  const s = safeStr(v).toLowerCase();
  if (s === "active" || s === "suspended") return s;
  throw new HttpsError("invalid-argument", "status must be active|suspended");
}

function isOwner(data: MemberDoc): boolean {
  const role = (safeStr(data.roleId) || safeStr(data.role)).toLowerCase();
  return role === "owner";
}

export async function setMembershipStatus(req: CallableRequest<Input>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = safeStr(req.data?.clinicId);
  const memberUid = safeStr(req.data?.memberUid);
  const status = normalizeStatus(req.data?.status);

  if (!clinicId || !memberUid) {
    throw new HttpsError("invalid-argument", "clinicId and memberUid are required.");
  }

  const db = admin.firestore();
  const actorUid = req.auth.uid;

  await requireActiveMemberWithPerm(db, clinicId, actorUid, "members.manage");

  if (actorUid === memberUid) {
    throw new HttpsError("failed-precondition", "You cannot change your own status.");
  }

  // Last-owner guard: cannot suspend the last active owner
  if (status === "suspended") {
    const snap = await getClinicMembershipSnap(db, clinicId, memberUid);
    if (snap) {
      const data = (snap.data() || {}) as MemberDoc;
      if (isOwner(data) && isActiveMembership(data)) {
        const ownerCount = await countActiveOwners(db, clinicId);
        if (ownerCount <= 1) {
          throw new HttpsError(
            "failed-precondition",
            "Cannot suspend the last active owner. Assign another owner first."
          );
        }
      }
    }
  }

  const now = admin.firestore.FieldValue.serverTimestamp();

  // Canonical path (matches Firestore rules): members
  const canonRef = db.doc(`clinics/${clinicId}/members/${memberUid}`);
  const legacyRef = db.doc(`clinics/${clinicId}/memberships/${memberUid}`);

  const batch = db.batch();

  batch.set(
    canonRef,
    {
      status,
      active: status === "active",
      updatedAt: now,
      updatedByUid: actorUid,
    },
    { merge: true }
  );

  batch.set(
    legacyRef,
    {
      status,
      active: status === "active",
      updatedAt: now,
      updatedByUid: actorUid,
    },
    { merge: true }
  );

  await batch.commit();

  const auditRef = db.collection(`clinics/${clinicId}/audit`).doc();
  await auditRef.set({
    type: "membership.status_changed",
    clinicId,
    actor: { uid: actorUid },
    subject: { uid: memberUid },
    status,
    at: now,
    schemaVersion: 1,
  });

  return { ok: true };
}
