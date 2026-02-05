// functions/src/clinic/updateMemberProfile.ts
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/logger";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

type Input = {
  clinicId: string;
  memberUid: string;
  displayName?: string;
};

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

function readBoolOrUndefined(v: any): boolean | undefined {
  if (v === true) return true;
  if (v === false) return false;
  return undefined;
}

function isMemberActiveLike(data: Record<string, any>): boolean {
  const status = safeStr((data as any).status);
  if (status === "suspended") return false;
  if (status === "invited") return false;

  const active = readBoolOrUndefined((data as any).active);
  if (active !== undefined) return active;

  return true;
}

function getPermissionsMap(data: Record<string, any>): Record<string, any> {
  const p = (data as any).permissions;
  if (p && typeof p === "object" && !Array.isArray(p)) return p as Record<string, any>;
  return {};
}

/**
 * ✅ Canonical-first membership lookup:
 *   1) clinics/{clinicId}/members/{uid}        (canonical)
 *   2) clinics/{clinicId}/memberships/{uid}    (legacy fallback)
 */
async function getMembershipWithFallback(params: {
  clinicId: string;
  uid: string;
}): Promise<Record<string, any> | null> {
  const canonicalRef = db
    .collection("clinics")
    .doc(params.clinicId)
    .collection("members")
    .doc(params.uid);

  const canonicalSnap = await canonicalRef.get();
  if (canonicalSnap.exists) return (canonicalSnap.data() ?? {}) as Record<string, any>;

  const legacyRef = db
    .collection("clinics")
    .doc(params.clinicId)
    .collection("memberships")
    .doc(params.uid);

  const legacySnap = await legacyRef.get();
  if (legacySnap.exists) return (legacySnap.data() ?? {}) as Record<string, any>;

  return null;
}

function clampLen(s: string, max: number): string {
  const t = safeStr(s);
  if (t.length <= max) return t;
  return t.substring(0, max);
}

export async function updateMemberProfile(req: CallableRequest<Input>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = safeStr(req.data?.clinicId);
  const memberUid = safeStr(req.data?.memberUid);
  const displayNameRaw = safeStr(req.data?.displayName);

  if (!clinicId) throw new HttpsError("invalid-argument", "clinicId required.");
  if (!memberUid) throw new HttpsError("invalid-argument", "memberUid required.");
  if (!displayNameRaw) throw new HttpsError("invalid-argument", "displayName required.");

  // Keep membership doc tidy / predictable
  const displayName = clampLen(displayNameRaw, 120);

  const actorUid = req.auth.uid;

  // ✅ authorize actor
  const actorMembership = await getMembershipWithFallback({ clinicId, uid: actorUid });
  if (!actorMembership) throw new HttpsError("permission-denied", "Not a clinic member.");
  if (!isMemberActiveLike(actorMembership)) {
    throw new HttpsError("permission-denied", "Membership not active.");
  }

  const perms = getPermissionsMap(actorMembership);
  if (perms["members.manage"] !== true) {
    throw new HttpsError("permission-denied", "Insufficient permissions.");
  }

  // ✅ target must exist in at least one place
  // canonical first
  const canonRef = db
    .collection("clinics")
    .doc(clinicId)
    .collection("members")
    .doc(memberUid);

  const legacyRef = db
    .collection("clinics")
    .doc(clinicId)
    .collection("memberships")
    .doc(memberUid);

  const [canonSnap, legacySnap] = await Promise.all([canonRef.get(), legacyRef.get()]);

  if (!canonSnap.exists && !legacySnap.exists) {
    throw new HttpsError("not-found", "Target member not found.");
  }

  const now = admin.firestore.FieldValue.serverTimestamp();

  const patch = {
    displayName,
    fullName: displayName, // legacy convenience
    updatedAt: now,
    updatedByUid: actorUid,
  };

  const batch = db.batch();
  if (canonSnap.exists) batch.set(canonRef, patch, { merge: true });
  if (legacySnap.exists) batch.set(legacyRef, patch, { merge: true });
  await batch.commit();

  logger.info("updateMemberProfile: updated", {
    clinicId,
    actorUid,
    memberUid,
    displayName,
    wroteCanonical: canonSnap.exists,
    wroteLegacy: legacySnap.exists,
  });

  return { ok: true, memberUid, displayName };
}
