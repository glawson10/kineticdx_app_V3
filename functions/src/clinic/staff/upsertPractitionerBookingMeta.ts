// functions/src/clinic/staff/upsertPractitionerBookingMeta.ts
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

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

function isMemberActiveLike(data: Record<string, any>): boolean {
  const status = safeStr((data as any).status);
  if (status === "suspended") return false;
  if (status === "invited") return false;

  const active = (data as any).active;
  if (active === true) return true;
  if (active === false) return false;
  return true;
}

function getPermissionsMap(data: Record<string, any>): Record<string, any> {
  const p = (data as any).permissions;
  if (p && typeof p === "object" && !Array.isArray(p)) return p;
  return {};
}

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

function sanitizeBookingMetaPatch(raw: Record<string, any>): Record<string, any> {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new HttpsError("invalid-argument", "patch must be an object.");
  }

  const out: Record<string, any> = {};

  if ("activeForBooking" in raw) {
    out.activeForBooking = raw.activeForBooking === true;
  }

  if ("showInPublicBooking" in raw) {
    out.showInPublicBooking = raw.showInPublicBooking === true;
  }

  if ("publicSortOrder" in raw) {
    const n = Number(raw.publicSortOrder);
    out.sortOrder = Number.isFinite(n) ? Math.max(0, Math.round(n)) : 0;
  }

  if ("allowedLocationIds" in raw) {
    if (Array.isArray(raw.allowedLocationIds)) {
      out.allowedLocationIds = raw.allowedLocationIds
        .map((x: any) => safeStr(x))
        .filter((x: string) => x.length > 0)
        .slice(0, 50);
    } else {
      out.allowedLocationIds = [];
    }
  }

  if ("serviceIdsAllowed" in raw) {
    if (Array.isArray(raw.serviceIdsAllowed)) {
      out.serviceIdsAllowed = raw.serviceIdsAllowed
        .map((x: any) => safeStr(x))
        .filter((x: string) => x.length > 0)
        .slice(0, 100);
    } else {
      out.serviceIdsAllowed = [];
    }
  }

  if ("displayName" in raw) {
    out.displayName = safeStr(raw.displayName).slice(0, 200);
  }

  return out;
}

export async function upsertPractitionerBookingMeta(
  req: CallableRequest<Input>
) {
  if (!req.auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }

  const clinicId = safeStr(req.data?.clinicId);
  const targetUid = safeStr(req.data?.uid);
  const actorUid = req.auth.uid;

  if (!clinicId || !targetUid) {
    throw new HttpsError("invalid-argument", "clinicId and uid are required.");
  }

  const actorMembership = await getMembershipWithFallback({
    clinicId,
    uid: actorUid,
  });

  if (!actorMembership || !isMemberActiveLike(actorMembership)) {
    throw new HttpsError("permission-denied", "Not permitted.");
  }

  const perms = getPermissionsMap(actorMembership);
  if (perms["members.manage"] !== true) {
    throw new HttpsError(
      "permission-denied",
      "Only clinic managers can change booking metadata."
    );
  }

  const targetMembership = await getMembershipWithFallback({
    clinicId,
    uid: targetUid,
  });

  if (!targetMembership) {
    throw new HttpsError("not-found", "Target member not found in clinic.");
  }

  const patch = sanitizeBookingMetaPatch(req.data?.patch ?? {});

  if (Object.keys(patch).length === 0) {
    return { ok: true, noop: true };
  }

  // Ensure displayName is populated if not in patch
  if (!("displayName" in patch)) {
    const existingPrac = await db
      .doc(`clinics/${clinicId}/practitioners/${targetUid}`)
      .get();

    if (!existingPrac.exists) {
      patch.displayName =
        safeStr(targetMembership.displayName) ||
        safeStr(targetMembership.name) ||
        safeStr(targetMembership.invitedEmail) ||
        "Practitioner";
    }
  }

  // Sync active from membership
  patch.active = isMemberActiveLike(targetMembership);

  const ref = db.doc(`clinics/${clinicId}/practitioners/${targetUid}`);
  const now = admin.firestore.FieldValue.serverTimestamp();

  const snap = await ref.get();

  try {
    await ref.set(
      {
        ...patch,
        updatedAt: now,
        updatedByUid: actorUid,
        ...(snap.exists ? {} : { createdAt: now, createdByUid: actorUid }),
      },
      { merge: true }
    );
  } catch (err: any) {
    const msg = err?.message ?? String(err);
    logger.error("upsertPractitionerBookingMeta: write failed", { clinicId, targetUid, err: msg });
    throw new HttpsError("internal", `Failed to update booking metadata: ${msg}`);
  }

  logger.info("upsertPractitionerBookingMeta: success", {
    clinicId,
    targetUid,
    actorUid,
    patchKeys: Object.keys(patch),
  });

  return { ok: true };
}
