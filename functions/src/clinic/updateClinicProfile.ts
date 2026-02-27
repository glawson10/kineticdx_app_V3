/**
 * Commit 4 + 5: settings.updateClinicProfile
 * - Auth → membership → settings.write → validate → write profile.* only.
 * - Root mirror: only name and timezone (minimal legacy compat).
 * - Public projection: not here; use event-driven onWrite/trigger for public mirror (see OPENING_HOURS_CONTRACT).
 * - Audit: settings.clinic.updated with changes (canonical keys profile.*).
 */

import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import { writeSettingsAuditEvent } from "./audit/audit";
import {
  validateTimezone,
  validateEmail,
  validateSessionTimeoutMinutes,
} from "./generalSettingsValidation";

export type GeneralSettingsPatch = {
  name?: string | null;
  adminContactFirstName?: string | null;
  adminContactLastName?: string | null;
  adminContactEmail?: string | null;
  country?: string | null;
  timezone?: string | null;
  currency?: string | null;
  terminology?: string | null;
  replyToEmail?: string | null;
  sessionTimeoutMinutes?: number | null;
  require2FA?: boolean | null;
  _testAudit?: boolean;
};

const db = admin.firestore();
const FV = admin.firestore.FieldValue;

function isNonEmptyString(v: unknown): v is string {
  return typeof v === "string" && v.trim().length > 0;
}

function trimStr(v: string, maxLen: number): string {
  const s = v.trim();
  return s.length > maxLen ? s.slice(0, maxLen) : s;
}

/** Admin contact completeness: if any is set, all three must be valid (email valid, first+last non-empty). */
function validateAdminContact(patch: GeneralSettingsPatch): void {
  const first = patch.adminContactFirstName;
  const last = patch.adminContactLastName;
  const email = patch.adminContactEmail;
  const hasFirst = typeof first === "string" && first.trim().length > 0;
  const hasLast = typeof last === "string" && last.trim().length > 0;
  const hasEmail = typeof email === "string" && email.trim().length > 0;
  if (!hasFirst && !hasLast && !hasEmail) return;
  if (!hasFirst || !hasLast) {
    throw new HttpsError(
      "invalid-argument",
      "If any admin contact field is set, first name, last name and email are all required."
    );
  }
  if (!hasEmail || !validateEmail(email!.trim().toLowerCase())) {
    throw new HttpsError(
      "invalid-argument",
      "Admin contact email must be a valid email address when admin contact is provided."
    );
  }
  if (email!.trim().length > 254) {
    throw new HttpsError("invalid-argument", "Admin contact email must be at most 254 characters.");
  }
}

/** Normalize and validate patch; returns only keys that were provided (undefined = not in patch). */
function cleanAndValidatePatch(input: unknown): GeneralSettingsPatch {
  const raw = input && typeof input === "object" ? input : {};
  const patch: GeneralSettingsPatch = {};

  if (raw.hasOwnProperty("name")) {
    const v = (raw as any).name;
    if (v === null) patch.name = null;
    else if (typeof v === "string") {
      const s = trimStr(v, 80);
      if (s.length < 2) {
        throw new HttpsError("invalid-argument", "Clinic name must be at least 2 characters.");
      }
      if (/^\s*$/.test(v)) {
        throw new HttpsError("invalid-argument", "Clinic name cannot be only whitespace.");
      }
      patch.name = s;
    }
  }

  if (raw.hasOwnProperty("adminContactFirstName")) {
    const v = (raw as any).adminContactFirstName;
    if (v === null) patch.adminContactFirstName = null;
    else if (typeof v === "string") patch.adminContactFirstName = trimStr(v, 50);
  }
  if (raw.hasOwnProperty("adminContactLastName")) {
    const v = (raw as any).adminContactLastName;
    if (v === null) patch.adminContactLastName = null;
    else if (typeof v === "string") patch.adminContactLastName = trimStr(v, 50);
  }
  if (raw.hasOwnProperty("adminContactEmail")) {
    const v = (raw as any).adminContactEmail;
    if (v === null) patch.adminContactEmail = null;
    else if (typeof v === "string") {
      const s = v.trim().toLowerCase();
      if (s.length > 0 && !validateEmail(s)) {
        throw new HttpsError("invalid-argument", "Admin contact email must be a valid email address.");
      }
      patch.adminContactEmail = s.length > 254 ? s.slice(0, 254) : s;
    }
  }

  if (raw.hasOwnProperty("country")) {
    const v = (raw as any).country;
    if (v === null) patch.country = null;
    else if (typeof v === "string") {
      const s = v.trim().toUpperCase();
      if (s.length > 0) {
        if (s.length !== 2 || !/^[A-Z]{2}$/.test(s)) {
          throw new HttpsError("invalid-argument", "Country must be ISO 3166-1 alpha-2 (2 letters).");
        }
        patch.country = s;
      } else patch.country = null;
    }
  }

  if (raw.hasOwnProperty("timezone")) {
    const v = (raw as any).timezone;
    if (v === null) patch.timezone = null;
    else if (typeof v === "string") {
      const s = v.trim();
      if (s.length > 0) {
        validateTimezone(s);
        patch.timezone = s.length > 64 ? s.slice(0, 64) : s;
      } else patch.timezone = null;
    }
  }

  if (raw.hasOwnProperty("currency")) {
    const v = (raw as any).currency;
    if (v === null) patch.currency = null;
    else if (typeof v === "string") {
      const s = v.trim().toUpperCase();
      if (s.length > 0) {
        if (s.length !== 3 || !/^[A-Z]{3}$/.test(s)) {
          throw new HttpsError("invalid-argument", "Currency must be ISO 4217 alpha-3 (3 letters).");
        }
        patch.currency = s;
      } else patch.currency = null;
    }
  }

  if (raw.hasOwnProperty("terminology")) {
    const v = (raw as any).terminology;
    if (v === null) patch.terminology = null;
    else if (typeof v === "string") {
      const s = v.trim().toLowerCase();
      if (s.length > 0) {
        if (s !== "patient" && s !== "client") {
          throw new HttpsError("invalid-argument", "Terminology must be 'patient' or 'client'.");
        }
        patch.terminology = s;
      } else patch.terminology = null;
    }
  }

  if (raw.hasOwnProperty("replyToEmail")) {
    const v = (raw as any).replyToEmail;
    if (v === null) patch.replyToEmail = null;
    else if (typeof v === "string") {
      const s = v.trim().toLowerCase();
      if (s.length > 0) {
        if (!validateEmail(s) || s.length > 254) {
          throw new HttpsError("invalid-argument", "Reply-to email must be a valid email (max 254 chars).");
        }
        patch.replyToEmail = s;
      } else patch.replyToEmail = null;
    }
  }

  if (raw.hasOwnProperty("sessionTimeoutMinutes")) {
    const v = (raw as any).sessionTimeoutMinutes;
    if (v === null || v === undefined) patch.sessionTimeoutMinutes = null;
    else {
      const n = Number(v);
      if (!Number.isInteger(n) || n < 0) {
        throw new HttpsError("invalid-argument", "sessionTimeoutMinutes must be a non-negative integer.");
      }
      validateSessionTimeoutMinutes(n === 0 ? null : n);
      patch.sessionTimeoutMinutes = n === 0 ? null : n;
    }
  }

  if (raw.hasOwnProperty("require2FA")) {
    const v = (raw as any).require2FA;
    if (v === null || v === undefined) patch.require2FA = null;
    else if (typeof v === "boolean") patch.require2FA = v;
    else throw new HttpsError("invalid-argument", "require2FA must be a boolean.");
  }

  if ((raw as any)?._testAudit === true) patch._testAudit = true;

  validateAdminContact(patch);
  return patch;
}

async function getAuthoritativeMembership(
  clinicId: string,
  uid: string
): Promise<FirebaseFirestore.DocumentData | null> {
  const canonical = db.doc(`clinics/${clinicId}/members/${uid}`);
  const legacy = db.doc(`clinics/${clinicId}/memberships/${uid}`);
  const c = await canonical.get();
  if (c.exists) return c.data() ?? {};
  const l = await legacy.get();
  if (l.exists) return l.data() ?? {};
  return null;
}

function isActiveMember(data: FirebaseFirestore.DocumentData): boolean {
  if (!("active" in data)) return true;
  return data.active === true;
}

function hasSettingsWrite(data: FirebaseFirestore.DocumentData): boolean {
  const perms = data.permissions;
  return !!(perms && typeof perms === "object" && perms["settings.write"] === true);
}

function anyMeaningfulKeys(patch: GeneralSettingsPatch): boolean {
  return Object.entries(patch).some(([k, v]) => v !== undefined && k !== "_testAudit");
}

function isTestAuditOnly(patch: GeneralSettingsPatch): boolean {
  return (
    patch._testAudit === true &&
    Object.entries(patch).every(([k, v]) => k === "_testAudit" || v === undefined)
  );
}

/** Write profile.* only. Mirror to root only for legacy keys: name, timezone (minimal root mirroring). */
const ROOT_MIRROR_KEYS = new Set(["name", "timezone"]);

function applyProfileUpdate(
  updateData: Record<string, any>,
  profileKey: string,
  value: string | number | boolean | null | undefined
) {
  if (value === undefined) return;
  const profileDot = `profile.${profileKey}`;
  if (value === null) {
    updateData[profileDot] = FV.delete();
    if (ROOT_MIRROR_KEYS.has(profileKey)) updateData[profileKey] = FV.delete();
  } else {
    updateData[profileDot] = value;
    if (ROOT_MIRROR_KEYS.has(profileKey)) updateData[profileKey] = value;
  }
}

/** Write profile.* only (no root mirror). Used for sessionTimeoutMinutes, require2FA. */
function applyProfileOnly(
  updateData: Record<string, any>,
  profileKey: string,
  value: number | boolean | null | undefined
) {
  if (value === undefined) return;
  const profileDot = `profile.${profileKey}`;
  if (value === null) {
    updateData[profileDot] = FV.delete();
  } else {
    updateData[profileDot] = value;
  }
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

  let patch: GeneralSettingsPatch;
  try {
    patch = cleanAndValidatePatch(request.data?.patch);
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    throw new HttpsError("invalid-argument", e instanceof Error ? e.message : "Invalid patch.");
  }

  const testAuditOnly = isTestAuditOnly(patch);
  if (!testAuditOnly && !anyMeaningfulKeys(patch)) {
    throw new HttpsError("invalid-argument", "No valid fields to update.");
  }

  const uid = request.auth.uid;
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

  if (testAuditOnly) {
    await writeSettingsAuditEvent(
      db,
      clinicId,
      "settings.clinic.updated",
      uid,
      `clinics/${clinicId}`,
      clinicId,
      {}
    );
    return { ok: true };
  }

  const updateData: Record<string, any> = {
    updatedAt: now,
    "profile.updatedAt": now,
    "profile.updatedBy": uid,
  };

  applyProfileUpdate(updateData, "name", patch.name);
  applyProfileUpdate(updateData, "adminContactFirstName", patch.adminContactFirstName);
  applyProfileUpdate(updateData, "adminContactLastName", patch.adminContactLastName);
  applyProfileUpdate(updateData, "adminContactEmail", patch.adminContactEmail);
  applyProfileUpdate(updateData, "country", patch.country);
  applyProfileUpdate(updateData, "timezone", patch.timezone);
  applyProfileUpdate(updateData, "currency", patch.currency);
  applyProfileUpdate(updateData, "terminology", patch.terminology);
  applyProfileUpdate(updateData, "replyToEmail", patch.replyToEmail);

  if (patch.sessionTimeoutMinutes !== undefined) {
    applyProfileOnly(
      updateData,
      "sessionTimeoutMinutes",
      patch.sessionTimeoutMinutes === null || patch.sessionTimeoutMinutes === 0 ? null : patch.sessionTimeoutMinutes
    );
  }

  if (patch.require2FA !== undefined) {
    applyProfileOnly(updateData, "require2FA", patch.require2FA === null ? null : patch.require2FA);
  }

  const changedFields = Object.entries(patch)
    .filter(([k, v]) => v !== undefined && k !== "_testAudit")
    .map(([k]) => k);
  const auditChanges: Record<string, unknown> = {};
  for (const key of changedFields) {
    const v = (patch as any)[key];
    const canonicalKey = `profile.${key}`;
    auditChanges[canonicalKey] = v === null ? null : v;
  }

  const auditRef = db.collection(`clinics/${clinicId}/audit`).doc();

  await db.runTransaction(async (tx) => {
    tx.update(clinicRef, updateData);
    tx.set(auditRef, {
      clinicId,
      eventType: "settings.clinic.updated",
      actorUserId: uid,
      entityPath: `clinics/${clinicId}`,
      entityId: clinicId,
      changes: auditChanges,
      createdAt: now,
    });
  });

  return { ok: true };
}
