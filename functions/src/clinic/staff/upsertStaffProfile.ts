// functions/src/clinic/staff/upsertStaffProfile.ts
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/logger";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

type Input = {
  clinicId: string;
  uid: string;
  patch: Record<string, any>;
};

// ─────────────────────────────
// Helpers
// ─────────────────────────────

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
  if (p && typeof p === "object" && !Array.isArray(p)) return p;
  return {};
}

/**
 * Canonical-first membership lookup:
 *   1) clinics/{clinicId}/members/{uid}
 *   2) clinics/{clinicId}/memberships/{uid} (legacy)
 */
async function getMembershipWithFallback(params: {
  clinicId: string;
  uid: string;
}): Promise<Record<string, any> | null> {
  const canon = await db
    .collection("clinics")
    .doc(params.clinicId)
    .collection("members")
    .doc(params.uid)
    .get();

  if (canon.exists) return canon.data() ?? {};

  const legacy = await db
    .collection("clinics")
    .doc(params.clinicId)
    .collection("memberships")
    .doc(params.uid)
    .get();

  if (legacy.exists) return legacy.data() ?? {};

  return null;
}

function ensurePlainObject(v: any, label: string): Record<string, any> {
  if (!v || typeof v !== "object" || Array.isArray(v)) {
    throw new HttpsError("invalid-argument", `${label} must be an object.`);
  }
  return v;
}

/**
 * Allowlist-only staff profile patch.
 * 🚫 Availability / hours are EXPLICITLY forbidden here.
 */
function sanitizeStaffProfilePatch(raw: Record<string, any>): Record<string, any> {
  const patch = ensurePlainObject(raw, "patch");

  // 🚫 HARD BLOCK availability-related keys
  const forbiddenKeys = [
    "availability",
    "weekly",
    "openingHours",
    "hours",
    "workingHours",
  ];

  for (const k of forbiddenKeys) {
    if (k in patch) {
      throw new HttpsError(
        "invalid-argument",
        `Field "${k}" is not allowed in staff profile updates. ` +
          `Use setStaffAvailabilityDefaultFn instead.`
      );
    }
  }

  const out: Record<string, any> = {};

  // schema version (optional)
  out.schemaVersion =
    Number.isFinite(Number(patch.schemaVersion))
      ? Number(patch.schemaVersion)
      : 1;

  if ("displayName" in patch)
    out.displayName = safeStr(patch.displayName).slice(0, 120);

  if ("firstName" in patch)
    out.firstName = safeStr(patch.firstName).slice(0, 80);

  if ("lastName" in patch)
    out.lastName = safeStr(patch.lastName).slice(0, 80);

  if ("title" in patch)
    out.title = safeStr(patch.title).slice(0, 120);

  if ("notes" in patch)
    out.notes = safeStr(patch.notes).slice(0, 8000);

  if ("photo" in patch && typeof patch.photo === "object") {
    out.photo = {
      storagePath: safeStr(patch.photo.storagePath).slice(0, 300),
      url: safeStr(patch.photo.url).slice(0, 500),
    };
  }

  if ("professional" in patch && typeof patch.professional === "object") {
    out.professional = patch.professional;
  }

  return out;
}

// ─────────────────────────────
// Callable
// ─────────────────────────────

export async function upsertStaffProfile(
  req: CallableRequest<Input>
) {
  if (!req.auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }

  const clinicId = safeStr(req.data?.clinicId);
  const targetUid = safeStr(req.data?.uid);
  const actorUid = req.auth.uid;

  if (!clinicId || !targetUid) {
    throw new HttpsError(
      "invalid-argument",
      "clinicId and uid are required."
    );
  }

  // ── Authorize actor
  const actorMembership = await getMembershipWithFallback({
    clinicId,
    uid: actorUid,
  });

  if (!actorMembership || !isMemberActiveLike(actorMembership)) {
    throw new HttpsError("permission-denied", "Not permitted.");
  }

  const perms = getPermissionsMap(actorMembership);
  if (perms["members.manage"] !== true) {
    throw new HttpsError("permission-denied", "Insufficient permissions.");
  }

  // ── Ensure target exists in clinic
  const targetMembership = await getMembershipWithFallback({
    clinicId,
    uid: targetUid,
  });

  if (!targetMembership) {
    throw new HttpsError(
      "not-found",
      "Target staff member not in clinic."
    );
  }

  // ── Sanitize patch
  const patch = sanitizeStaffProfilePatch(req.data?.patch ?? {});

  const ref = db
    .collection("clinics")
    .doc(clinicId)
    .collection("staffProfiles")
    .doc(targetUid);

  const snap = await ref.get();
  const now = admin.firestore.FieldValue.serverTimestamp();

  await ref.set(
    {
      ...patch,
      updatedAt: now,
      updatedByUid: actorUid,
      ...(snap.exists
        ? {}
        : { createdAt: now, createdByUid: actorUid }),
    },
    { merge: true } // ✅ SAFE: profile-only, never availability
  );

  logger.info("upsertStaffProfile: ok", {
    clinicId,
    actorUid,
    targetUid,
    keys: Object.keys(patch),
  });

  return { ok: true, uid: targetUid };
}
