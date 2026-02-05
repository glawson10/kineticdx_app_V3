import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";

type Patch = {
  name?: string | null;
  phone?: string | null;
  email?: string | null;
  timezone?: string | null;
  address?: string | null;
  logoUrl?: string | null;
  defaultLanguage?: string | null;

  // ✅ public contact links (optional)
  landingUrl?: string | null;
  websiteUrl?: string | null;
  whatsapp?: string | null;
};

const db = admin.firestore();
const FV = admin.firestore.FieldValue;

function isNonEmptyString(v: unknown): v is string {
  return typeof v === "string" && v.trim().length > 0;
}

function asStringOrNull(v: unknown, maxLen: number): string | null | undefined {
  // undefined => not provided
  if (v === undefined) return undefined;

  // null => explicit delete
  if (v === null) return null;

  if (typeof v !== "string") return undefined;

  const s = v.trim();
  if (!s) return null; // empty string => treat as delete
  return s.length > maxLen ? s.slice(0, maxLen) : s;
}

function normalizeUrlOrNull(v: string | null): string | null {
  if (v == null) return null;
  const s = v.trim();
  if (!s) return null;

  const lower = s.toLowerCase();
  if (lower.startsWith("http://") || lower.startsWith("https://")) return s;

  // allow "example.com" style inputs
  if (lower.includes(".") && !lower.includes(" ")) return `https://${s}`;

  return s;
}

function cleanPatch(input: any): Patch {
  const patch: Patch = {};

  patch.name = asStringOrNull(input?.name, 80);
  patch.phone = asStringOrNull(input?.phone, 40);
  patch.email = asStringOrNull(input?.email, 120);
  patch.timezone = asStringOrNull(input?.timezone, 64);
  patch.address = asStringOrNull(input?.address, 200);
  patch.logoUrl = asStringOrNull(input?.logoUrl, 500);
  patch.defaultLanguage = asStringOrNull(input?.defaultLanguage, 10);

  patch.landingUrl = asStringOrNull(input?.landingUrl, 240);
  patch.websiteUrl = asStringOrNull(input?.websiteUrl, 240);
  patch.whatsapp = asStringOrNull(input?.whatsapp, 120);

  // Normalize URLs (only if defined)
  if (patch.landingUrl !== undefined)
    patch.landingUrl = normalizeUrlOrNull(patch.landingUrl);
  if (patch.websiteUrl !== undefined)
    patch.websiteUrl = normalizeUrlOrNull(patch.websiteUrl);

  return patch;
}

function validateTimezone(tz: string) {
  const ok = /^[A-Za-z_]+\/[A-Za-z_]+(?:\/[A-Za-z_]+)?$/.test(tz);
  if (!ok) {
    throw new HttpsError("invalid-argument", "Invalid timezone format.");
  }
}

async function getAuthoritativeMembership(
  clinicId: string,
  uid: string
): Promise<FirebaseFirestore.DocumentData | null> {
  // ✅ Match Firestore rules:
  // Canonical: clinics/{clinicId}/members/{uid}
  // Legacy:    clinics/{clinicId}/memberships/{uid}
  const canonical = db.doc(`clinics/${clinicId}/members/${uid}`);
  const legacy = db.doc(`clinics/${clinicId}/memberships/${uid}`);

  const c = await canonical.get();
  if (c.exists) return c.data() ?? {};

  const l = await legacy.get();
  if (l.exists) return l.data() ?? {};

  return null;
}

function isActiveMember(data: FirebaseFirestore.DocumentData): boolean {
  // ✅ Match Firestore rules: missing "active" => active (back-compat)
  if (!("active" in data)) return true;
  return data.active === true;
}

function hasSettingsWrite(data: FirebaseFirestore.DocumentData): boolean {
  const perms = data.permissions;
  return !!(perms && typeof perms === "object" && perms["settings.write"] === true);
}

function anyMeaningfulKeys(patch: Patch): boolean {
  // If every key is undefined, it means nothing was provided.
  // null counts (it means delete).
  return Object.values(patch).some((v) => v !== undefined);
}

function setOrDelete(
  updateData: Record<string, any>,
  key: string,
  value: string | null | undefined
) {
  if (value === undefined) return; // no change
  if (value === null) updateData[key] = FV.delete();
  else updateData[key] = value;
}

export async function updateClinicProfile(request: any) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }

  const clinicId = isNonEmptyString(request.data?.clinicId)
    ? request.data.clinicId.trim().slice(0, 64)
    : "";

  if (!clinicId) {
    throw new HttpsError("invalid-argument", "clinicId is required.");
  }

  const patch = cleanPatch(request.data?.patch);

  if (!anyMeaningfulKeys(patch)) {
    throw new HttpsError("invalid-argument", "No valid fields to update.");
  }

  if (typeof patch.timezone === "string") validateTimezone(patch.timezone);

  const uid = request.auth.uid;

  // ✅ membership check (authoritative clinic scope only)
  const memberData = await getAuthoritativeMembership(clinicId, uid);
  if (!memberData) {
    throw new HttpsError("permission-denied", "Missing membership.");
  }

  if (!isActiveMember(memberData)) {
    throw new HttpsError("permission-denied", "Inactive membership.");
  }

  if (!hasSettingsWrite(memberData)) {
    throw new HttpsError("permission-denied", "Missing settings.write permission.");
  }

  const clinicRef = db.doc(`clinics/${clinicId}`);
  const clinicSnap = await clinicRef.get();
  if (!clinicSnap.exists) {
    throw new HttpsError("not-found", "Clinic not found.");
  }

  const now = FV.serverTimestamp();

  // Build update payload
  const updateData: Record<string, any> = {
    updatedAt: now,

    // keep profile audit trail
    "profile.updatedAt": now,
    "profile.updatedBy": uid,
  };

  // ✅ Write BOTH root keys and profile keys (so older clients still work)
  setOrDelete(updateData, "name", patch.name);
  setOrDelete(updateData, "phone", patch.phone);
  setOrDelete(updateData, "email", patch.email);
  setOrDelete(updateData, "timezone", patch.timezone);
  setOrDelete(updateData, "address", patch.address);
  setOrDelete(updateData, "logoUrl", patch.logoUrl);
  setOrDelete(updateData, "defaultLanguage", patch.defaultLanguage);

  setOrDelete(updateData, "landingUrl", patch.landingUrl);
  setOrDelete(updateData, "websiteUrl", patch.websiteUrl);
  setOrDelete(updateData, "whatsapp", patch.whatsapp);

  setOrDelete(updateData, "profile.name", patch.name);
  setOrDelete(updateData, "profile.phone", patch.phone);
  setOrDelete(updateData, "profile.email", patch.email);
  setOrDelete(updateData, "profile.timezone", patch.timezone);
  setOrDelete(updateData, "profile.address", patch.address);
  setOrDelete(updateData, "profile.logoUrl", patch.logoUrl);
  setOrDelete(updateData, "profile.defaultLanguage", patch.defaultLanguage);

  setOrDelete(updateData, "profile.landingUrl", patch.landingUrl);
  setOrDelete(updateData, "profile.websiteUrl", patch.websiteUrl);
  setOrDelete(updateData, "profile.whatsapp", patch.whatsapp);

  // Audit
  const auditRef = db.collection(`clinics/${clinicId}/audit`).doc();

  // ✅ Public config mirror doc (public readable)
  const publicConfigRef = db.doc(
    `clinics/${clinicId}/public/config/publicBooking/publicBooking`
  );

  // Compute “post-update” values for mirroring using existing clinic data + patch.
  const existing = clinicSnap.data() || {};
  const existingProfile =
    existing.profile && typeof existing.profile === "object" ? existing.profile : {};

  const currentVal = (key: string) =>
    (existing as any)[key] ?? (existingProfile as any)[key] ?? null;

  const applyPatch = (key: keyof Patch) => {
    const v = patch[key];
    if (v === undefined) return currentVal(key as string);
    return v; // string or null
  };

  const nextClinicName = applyPatch("name");
  const nextLogoUrl = applyPatch("logoUrl");
  const nextEmail = applyPatch("email");
  const nextPhone = applyPatch("phone");

  const nextLandingUrl = applyPatch("landingUrl");
  const nextWebsiteUrl = applyPatch("websiteUrl");
  const nextWhatsapp = applyPatch("whatsapp");

  const changedFields = Object.entries(patch)
    .filter(([, v]) => v !== undefined)
    .map(([k]) => k);

  await db.runTransaction(async (tx) => {
    tx.update(clinicRef, updateData);

    tx.set(
      publicConfigRef,
      {
        clinicId,
        clinicName: typeof nextClinicName === "string" ? nextClinicName : null,
        logoUrl: typeof nextLogoUrl === "string" ? nextLogoUrl : null,

        landingUrl: typeof nextLandingUrl === "string" ? nextLandingUrl : null,
        websiteUrl: typeof nextWebsiteUrl === "string" ? nextWebsiteUrl : null,
        whatsapp: typeof nextWhatsapp === "string" ? nextWhatsapp : null,
        email: typeof nextEmail === "string" ? nextEmail : null,
        phone: typeof nextPhone === "string" ? nextPhone : null,
      },
      { merge: true }
    );

    tx.set(auditRef, {
      schemaVersion: 2,
      type: "clinic.settings.profile_updated",
      clinicId,
      actor: { uid },
      at: now,
      fields: changedFields,
    });
  });

  return { ok: true };
}
