// functions/src/clinic/syncMyDisplayName.ts
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/logger";

if (!admin.apps.length) admin.initializeApp();

type Input = {
  clinicId: string;
  // Optional: allow overriding later (profile edit UI).
  // For now: ignore/avoid trusting client input by default.
  displayNameOverride?: string;
};

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

function normEmail(v: unknown): string {
  return (v ?? "").toString().trim().toLowerCase();
}

function fallbackNameFromEmail(emailLower: string): string {
  const local = (emailLower.split("@")[0] ?? "").trim();
  return local || "User";
}

function looksLikeEmailLocal(displayName: string, emailLower: string): boolean {
  const d = safeStr(displayName).toLowerCase();
  if (!d) return false;
  const local = safeStr(emailLower.split("@")[0]).toLowerCase();
  if (!local) return false;
  return d === local;
}

function pickFirstNonEmpty(...vals: unknown[]): string {
  for (const v of vals) {
    const s = safeStr(v);
    if (s) return s;
  }
  return "";
}

export async function syncMyDisplayName(req: CallableRequest<Input>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = safeStr(req.data?.clinicId);
  if (!clinicId) throw new HttpsError("invalid-argument", "clinicId required.");

  const uid = req.auth.uid;
  const emailLower = normEmail((req.auth.token as any)?.email);

  const db = admin.firestore();

  // ✅ Membership docs (canonical + legacy)
  const canonRef = db.collection("clinics").doc(clinicId).collection("memberships").doc(uid);
  const legacyRef = db.collection("clinics").doc(clinicId).collection("members").doc(uid);

  const [canonSnap, legacySnap] = await Promise.all([canonRef.get(), legacyRef.get()]);

  if (!canonSnap.exists && !legacySnap.exists) {
    throw new HttpsError("permission-denied", "Not a member of this clinic.");
  }

  const canon = (canonSnap.exists ? (canonSnap.data() as any) : null) ?? {};
  const legacy = (legacySnap.exists ? (legacySnap.data() as any) : null) ?? {};

  // ✅ Try to preserve an existing "real" name in membership docs
  const existingMembershipName = pickFirstNonEmpty(
    canon.displayName,
    canon.fullName,
    legacy.displayName,
    legacy.fullName
  );

  // ✅ Resolve Auth displayName (if set)
  let authDisplayName = "";
  try {
    const user = await admin.auth().getUser(uid);
    authDisplayName = safeStr(user.displayName);
  } catch (e) {
    logger.warn("syncMyDisplayName: admin.auth().getUser failed", {
      uid,
      clinicId,
      err: safeStr((e as any)?.message) || String(e),
    });
  }

  // Optional: allow client override later (disabled-by-default)
  const override = safeStr(req.data?.displayNameOverride);

  // ✅ Decide final displayName:
  // Priority:
  // 1) Existing membership name (IF it doesn't look like email local-part)
  // 2) Auth displayName
  // 3) Override (only if you later decide to trust it)
  // 4) Email local-part fallback
  // 5) "User"
  let displayName = "";

  const existingLooksLikeLocal =
    existingMembershipName && emailLower
      ? looksLikeEmailLocal(existingMembershipName, emailLower)
      : false;

  if (existingMembershipName && !existingLooksLikeLocal) {
    displayName = existingMembershipName;
  } else if (authDisplayName) {
    displayName = authDisplayName;
  } else if (override) {
    displayName = override;
  } else if (emailLower) {
    displayName = fallbackNameFromEmail(emailLower);
  } else {
    displayName = "User";
  }

  // ✅ If we’re about to "set" the same value as already stored, skip writes.
  const canonCurrent = pickFirstNonEmpty(canon.displayName, canon.fullName);
  const legacyCurrent = pickFirstNonEmpty(legacy.displayName, legacy.fullName);

  const canonNeedsWrite = canonSnap.exists && canonCurrent !== displayName;
  const legacyNeedsWrite = legacySnap.exists && legacyCurrent !== displayName;

  logger.info("syncMyDisplayName: resolved", {
    clinicId,
    uid,
    emailLocal: emailLower ? fallbackNameFromEmail(emailLower) : "",
    existingMembershipName,
    existingLooksLikeLocal,
    authDisplayName,
    overrideUsed: !!override && !authDisplayName && !existingMembershipName,
    finalDisplayName: displayName,
    canonExists: canonSnap.exists,
    legacyExists: legacySnap.exists,
    canonNeedsWrite,
    legacyNeedsWrite,
  });

  if (!canonNeedsWrite && !legacyNeedsWrite) {
    return { ok: true, displayName, skipped: true };
  }

  const now = admin.firestore.FieldValue.serverTimestamp();

  const patch = {
    displayName,
    fullName: displayName, // ✅ helps older UI keys
    updatedAt: now,
    updatedByUid: uid,
  };

  const batch = db.batch();
  if (canonNeedsWrite) batch.set(canonRef, patch, { merge: true });
  if (legacyNeedsWrite) batch.set(legacyRef, patch, { merge: true });
  await batch.commit();

  logger.info("syncMyDisplayName: updated", {
    clinicId,
    uid,
    displayName,
    wroteCanon: canonNeedsWrite,
    wroteLegacy: legacyNeedsWrite,
  });

  return { ok: true, displayName };
}
