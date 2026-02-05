// functions/src/clinic/acceptInvite.ts
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/logger";

import { hashToken } from "./hash";
import { flattenPermissions } from "./authz";

type AcceptInviteInput = {
  token: string; // now supports: "<clinicId>.<rawToken>" (preferred)
};

type AnyMap = Record<string, any>;

function normEmail(v: unknown): string {
  return (v ?? "").toString().trim().toLowerCase();
}

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

function fallbackNameFromEmail(emailLower: string): string {
  const local = (emailLower.split("@")[0] ?? "").trim();
  if (!local) return "User";
  const pretty = local.replace(/[._-]+/g, " ").trim();
  return pretty || local;
}

async function resolveDisplayName(uid: string, emailLower: string, authToken: any) {
  // 1) Best: Firebase Auth profile
  try {
    const u = await admin.auth().getUser(uid);
    const dn = safeStr(u.displayName);
    if (dn) return dn;
  } catch (e) {
    logger.warn("[acceptInvite] getUser() failed (continuing with fallback)", {
      uid,
      err: String(e),
    });
  }

  // 2) Token fallbacks (sometimes present)
  const candidates = [
    authToken?.name,
    authToken?.display_name,
    authToken?.displayName,
    authToken?.["display_name"],
    authToken?.["displayName"],
  ];
  for (const c of candidates) {
    const s = safeStr(c);
    if (s) return s;
  }

  // 3) Email-derived fallback
  return fallbackNameFromEmail(emailLower);
}

/**
 * Token format:
 * - Preferred: "<clinicId>.<rawToken>"
 * - Back-compat: "<rawToken>" (will fail unless you still do collectionGroup lookups; we intentionally do NOT)
 */
function parseCompositeToken(token: string): { clinicId: string; rawToken: string } {
  const t = safeStr(token);
  const dot = t.indexOf(".");
  if (dot <= 0 || dot === t.length - 1) {
    throw new HttpsError(
      "invalid-argument",
      "Invite token format invalid. Please use the latest invite link."
    );
  }
  const clinicId = t.substring(0, dot).trim();
  const rawToken = t.substring(dot + 1).trim();
  if (!clinicId || !rawToken) {
    throw new HttpsError(
      "invalid-argument",
      "Invite token format invalid. Please use the latest invite link."
    );
  }
  return { clinicId, rawToken };
}

export async function acceptInvite(req: CallableRequest<AcceptInviteInput>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const token = safeStr(req.data?.token);
  if (!token) throw new HttpsError("invalid-argument", "Invite token required.");

  const db = admin.firestore();
  const uid = req.auth.uid;

  const userEmail = normEmail(req.auth.token.email);
  if (!userEmail) {
    throw new HttpsError("failed-precondition", "User email not available.");
  }

  const displayName = await resolveDisplayName(uid, userEmail, req.auth.token);
  logger.info("[acceptInvite] resolved displayName", { uid, userEmail, displayName });

  // ✅ Parse token => clinicId + rawToken
  const { clinicId, rawToken } = parseCompositeToken(token);
  const tokenHash = hashToken(rawToken);

  // ✅ Look up invite ONLY within that clinic (no collectionGroup)
  const invitesCol = db.collection("clinics").doc(clinicId).collection("invites");
  const inviteQuery = await invitesCol.where("tokenHash", "==", tokenHash).limit(1).get();

  if (inviteQuery.empty) {
    throw new HttpsError("not-found", "Invite not found or invalid.");
  }

  const inviteSnap = inviteQuery.docs[0];
  const invite = inviteSnap.data() as AnyMap;

  logger.info("[acceptInvite] invite located", {
    clinicId,
    inviteId: inviteSnap.id,
    status: safeStr(invite.status),
  });

  // Validate invite state
  if (safeStr(invite.status) !== "pending") {
    throw new HttpsError("failed-precondition", "Invite already used or revoked.");
  }

  if (!invite.expiresAt || typeof invite.expiresAt.toMillis !== "function") {
    throw new HttpsError("failed-precondition", "Invite expiry missing.");
  }
  if (invite.expiresAt.toMillis() < Date.now()) {
    throw new HttpsError("deadline-exceeded", "Invite expired.");
  }

  const inviteEmail = normEmail(invite.email);
  if (inviteEmail !== userEmail) {
    throw new HttpsError("permission-denied", "Invite email does not match signed-in user.");
  }

  const roleId = safeStr(invite.roleId);
  if (!roleId) throw new HttpsError("invalid-argument", "Invite roleId missing.");

  // Load role permissions
  const roleRef = db.collection("clinics").doc(clinicId).collection("roles").doc(roleId);
  const roleSnap = await roleRef.get();
  if (!roleSnap.exists) {
    throw new HttpsError("invalid-argument", "Role no longer exists.");
  }

  const rolePermissions = (roleSnap.data()?.permissions ?? {}) as AnyMap;
  const flattened = flattenPermissions(rolePermissions);

  const now = admin.firestore.FieldValue.serverTimestamp();

  // ✅ CANONICAL membership path = /members
  const canonicalMembershipRef = db
    .collection("clinics")
    .doc(clinicId)
    .collection("members")
    .doc(uid);

  // ✅ Legacy mirror during migration window = /memberships
  const legacyMembershipRef = db
    .collection("clinics")
    .doc(clinicId)
    .collection("memberships")
    .doc(uid);

  // User index mirror (clinic picker)
  const userMembershipRef = db.collection("users").doc(uid).collection("memberships").doc(clinicId);

  // Idempotency: if membership exists in either place, treat as already accepted.
  const [canonExisting, legacyExisting] = await Promise.all([
    canonicalMembershipRef.get(),
    legacyMembershipRef.get(),
  ]);

  if (canonExisting.exists || legacyExisting.exists) {
    logger.warn("[acceptInvite] membership already exists (idempotent accept)", {
      clinicId,
      uid,
      canonExists: canonExisting.exists,
      legacyExists: legacyExisting.exists,
    });

    // Mark invite consumed anyway so link can't be reused
    try {
      await inviteSnap.ref.update({
        status: "accepted",
        acceptedAt: now,
        acceptedByUid: uid,
      });
    } catch (e) {
      logger.warn("[acceptInvite] failed to mark invite accepted during idempotent path", {
        clinicId,
        inviteId: inviteSnap.id,
        err: String(e),
      });
    }

    return { ok: true, success: true, clinicId, alreadyMember: true };
  }

  const clinicSnap = await db.collection("clinics").doc(clinicId).get();
  const clinicName = clinicSnap.data()?.profile?.name ?? clinicId;

  const batch = db.batch();

  // Canonical membership (authoritative)
  batch.set(canonicalMembershipRef, {
    role: roleId,
    roleId: roleId, // back-compat
    displayName,
    fullName: displayName, // optional back-compat

    permissions: flattened,
    status: "active",
    active: true, // back-compat

    invitedEmail: inviteEmail,
    invitedByUid: invite.createdByUid ?? null,
    invitedAt: invite.createdAt ?? null,

    createdAt: now,
    updatedAt: now,
    createdByUid: uid,
    updatedByUid: uid,
  });

  // Legacy mirror (optional)
  batch.set(legacyMembershipRef, {
    role: roleId,
    roleId: roleId, // back-compat
    displayName,
    fullName: displayName,
    invitedEmail: inviteEmail,

    permissions: flattened,
    active: true,
    status: "active",
    createdAt: now,
    updatedAt: now,
    createdByUid: uid,
    updatedByUid: uid,
  });

  // User index mirror (clinic picker)
  batch.set(userMembershipRef, {
    clinicNameCache: clinicName,
    role: roleId,
    roleId: roleId, // back-compat
    status: "active",
    active: true, // back-compat
    createdAt: now,
  });

  // Mark invite consumed
  batch.update(inviteSnap.ref, {
    status: "accepted",
    acceptedAt: now,
    acceptedByUid: uid,
  });

  await batch.commit();

  logger.info("[acceptInvite] invite accepted + membership created", {
    clinicId,
    uid,
    roleId,
    wroteCanonical: true,
    wroteLegacy: true,
  });

  return { ok: true, success: true, clinicId, alreadyMember: false };
}
