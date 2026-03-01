/**
 * Commit 04 / 21–22: settings.upsertLocation
 * Create or edit a clinic location (name, color, show online, active, etc.).
 * Write path: clinics/{clinicId}/locations/{locationId}
 * Audit: settings.location.created | settings.location.updated | settings.location.deactivated | settings.location.activated
 *
 * Delete guard (Commit 22): Do NOT implement hard delete from UI. If adding delete in future:
 * - Ensure no future appointments reference this locationId.
 * - Ensure no appointmentTypes.allowedLocationIds include this locationId.
 * Deactivation only (active: false) is the supported lifecycle.
 */

import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import { requireClinicPermission } from "../permissions";
import { writeSettingsAuditEvent } from "../audit/audit";
import {
  assertString,
  assertBoolean,
  assertHexColor,
  pickAllowedFields,
  requireNonEmptyString,
} from "./validators";

const db = admin.firestore();
const FV = admin.firestore.FieldValue;

/** Server whitelist: only these keys accepted in patch. UI must send same keys. */
const LOCATION_PATCH_KEYS = new Set([
  "name",
  "addressText",
  "active",
  "showInOnlineBooking",
  "colorHex",
]);

export type UpsertLocationPatch = {
  name?: string | null;
  addressText?: string | null;
  active?: boolean | null;
  showInOnlineBooking?: boolean | null;
  colorHex?: string | null;
};

function validateAndPickPatch(patch: unknown, isCreate: boolean): UpsertLocationPatch {
  const raw = pickAllowedFields<UpsertLocationPatch>(patch, LOCATION_PATCH_KEYS);
  const name = assertString(raw.name, "name", {
    required: isCreate,
    trim: true,
    minLength: 2,
    maxLength: 80,
  });
  if (isCreate && (!name || name.length === 0)) {
    throw new HttpsError("invalid-argument", "name is required when creating a location.");
  }
  const addressText = assertString(raw.addressText, "addressText", {
    trim: true,
    maxLength: 1024,
  });
  const active = assertBoolean(raw.active, "active");
  const showInOnlineBooking = assertBoolean(raw.showInOnlineBooking, "showInOnlineBooking");
  const colorHex = assertHexColor(raw.colorHex, "colorHex");

  // Address optional unless showInOnlineBooking is being set to true: then require minimal address (future: line1, city, country).
  if (raw.showInOnlineBooking === true) {
    const addr = (addressText ?? "").toString().trim();
    if (addr.length < 3) {
      throw new HttpsError(
        "invalid-argument",
        "When 'Show in online booking' is enabled, address is required (at least 3 characters, e.g. line1, city, country)."
      );
    }
  }

  const out: UpsertLocationPatch = {};
  if (name != null) out.name = name;
  if (addressText !== undefined) out.addressText = addressText ?? null;
  if (active !== undefined) out.active = active ?? null;
  if (showInOnlineBooking !== undefined) out.showInOnlineBooking = showInOnlineBooking ?? null;
  if (colorHex !== undefined) out.colorHex = colorHex ?? null;
  return out;
}

export async function upsertLocation(request: { auth?: { uid?: string }; data?: unknown }) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }

  const data = request.data as Record<string, unknown> | undefined;
  const clinicId = requireNonEmptyString(data?.clinicId, "clinicId");
  const locationIdRaw = data?.locationId;
  const locationId =
    locationIdRaw === null || locationIdRaw === undefined
      ? null
      : assertString(locationIdRaw, "locationId", { maxLength: 128 });
  const isCreate = !locationId || locationId.length === 0;

  let patch: UpsertLocationPatch;
  try {
    patch = validateAndPickPatch(data?.patch, isCreate);
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    throw new HttpsError("invalid-argument", e instanceof Error ? e.message : "Invalid patch.");
  }

  if (Object.keys(patch).length === 0) {
    throw new HttpsError("invalid-argument", "No valid fields to update.");
  }

  const uid = request.auth.uid;
  await requireClinicPermission(db, clinicId, uid, "settings.write");

  const locationsRef = db.collection("clinics").doc(clinicId).collection("locations");
  const now = FV.serverTimestamp();
  let finalId: string;
  let before: Record<string, unknown> = {};

  if (isCreate) {
    finalId = locationsRef.doc().id;
    const doc = {
      name: patch.name ?? "",
      addressText: patch.addressText ?? null,
      active: patch.active ?? true,
      showInOnlineBooking: patch.showInOnlineBooking ?? false,
      colorHex: patch.colorHex ?? null,
      createdAt: now,
      updatedAt: now,
    };
    await locationsRef.doc(finalId).set(doc);

    const changes: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(doc)) {
      if (k !== "createdAt" && k !== "updatedAt") changes[k] = v;
    }
    await writeSettingsAuditEvent(
      db,
      clinicId,
      "settings.location.created",
      uid,
      `clinics/${clinicId}/locations/${finalId}`,
      finalId,
      changes
    );
    return { ok: true, locationId: finalId };
  }

  finalId = locationId!;
  const locRef = locationsRef.doc(finalId);
  const snap = await locRef.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Location not found.");
  }

  const existing = snap.data() ?? {};
  for (const key of Object.keys(patch)) {
    before[key] = existing[key];
  }

  const updateData: Record<string, unknown> = {
    updatedAt: now,
  };
  if (patch.name !== undefined) updateData.name = patch.name;
  if (patch.addressText !== undefined) updateData.addressText = patch.addressText;
  if (patch.active !== undefined) updateData.active = patch.active;
  if (patch.showInOnlineBooking !== undefined)
    updateData.showInOnlineBooking = patch.showInOnlineBooking;
  if (patch.colorHex !== undefined) updateData.colorHex = patch.colorHex;

  await locRef.update(updateData);

  const changes: Record<string, unknown> = {};
  for (const key of Object.keys(patch)) {
    changes[key] = { before: before[key], after: (updateData as any)[key] };
  }

  // Full edits only; active-only toggles use setLocationActive (audit: active_set).
  await writeSettingsAuditEvent(
    db,
    clinicId,
    "settings.location.updated",
    uid,
    `clinics/${clinicId}/locations/${finalId}`,
    finalId,
    changes
  );
  return { ok: true, locationId: finalId };
}
