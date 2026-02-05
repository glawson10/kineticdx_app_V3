import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { requireActiveMemberWithPerm } from "./authz";

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

  // ✅ Only staff managers can change membership status
  await requireActiveMemberWithPerm(db, clinicId, actorUid, "members.manage");

  // Optional safety: do not allow self-suspension (avoid locking yourself out)
  if (actorUid === memberUid) {
    throw new HttpsError("failed-precondition", "You cannot change your own status.");
  }

  const now = admin.firestore.FieldValue.serverTimestamp();

  const canonRef = db.doc(`clinics/${clinicId}/memberships/${memberUid}`);
  const legacyRef = db.doc(`clinics/${clinicId}/members/${memberUid}`);

  const batch = db.batch();

  // canonical
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

  // legacy mirror (migration window)
  batch.set(
    legacyRef,
    {
      active: status === "active",
      updatedAt: now,
    },
    { merge: true }
  );

  await batch.commit();

  // Optional: audit event
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
