/**
 * settings.upsertAppointmentType
 * Create or update an appointment type.
 * Write path: clinics/{clinicId}/appointmentTypes/{appointmentTypeId}
 */

import * as admin from "firebase-admin";
import type { Firestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { requireClinicPermission } from "../permissions";
import { writeSettingsAuditEvent } from "../audit/audit";
import {
  assertString,
  assertBoolean,
  assertIntRange,
  assertHexColor,
  pickAllowedFields,
  requireNonEmptyString,
} from "./validators";

const db = admin.firestore();
const FV = admin.firestore.FieldValue;

const APPT_TYPE_PATCH_KEYS = new Set([
  "name",
  "durationMinutes",
  "colorHex",
  "active",
  "showInOnlineBooking",
  "description",
  "defaultPrice",
  "allowedLocationIds",
  "telehealth",
  "allowedPractitionerIds",
]);

export type UpsertAppointmentTypePatch = {
  name?: string | null;
  durationMinutes?: number | null;
  colorHex?: string | null;
  active?: boolean | null;
  showInOnlineBooking?: boolean | null;
  description?: string | null;
  defaultPrice?: number | null;
  allowedLocationIds?: string[] | null;
  telehealth?: boolean | null;
  allowedPractitionerIds?: string[] | null;
};

function validateAndPickPatch(patch: unknown, isCreate: boolean): UpsertAppointmentTypePatch {
  const raw = pickAllowedFields<UpsertAppointmentTypePatch>(patch, APPT_TYPE_PATCH_KEYS);

  const name = assertString(raw.name, "name", {
    required: isCreate,
    trim: true,
    minLength: 2,
    maxLength: 120,
  });
  if (isCreate && (!name || name.length === 0)) {
    throw new HttpsError("invalid-argument", "name is required when creating an appointment type.");
  }

  const durationMinutes = assertIntRange(raw.durationMinutes, "durationMinutes", {
    min: 5,
    max: 480,
    required: isCreate,
  });
  if (durationMinutes != null && durationMinutes % 5 !== 0) {
    throw new HttpsError("invalid-argument", "durationMinutes must be divisible by 5.");
  }

  const colorHex = assertHexColor(raw.colorHex, "colorHex");
  const active = assertBoolean(raw.active, "active");
  const showInOnlineBooking = assertBoolean(raw.showInOnlineBooking, "showInOnlineBooking");
  const description = assertString(raw.description, "description", { trim: true, maxLength: 500 });

  let defaultPrice: number | null | undefined;
  if (raw.defaultPrice !== undefined && raw.defaultPrice !== null) {
    const p = typeof raw.defaultPrice === "number" ? raw.defaultPrice : parseFloat(String(raw.defaultPrice));
    if (!Number.isFinite(p) || p < 0) {
      throw new HttpsError("invalid-argument", "defaultPrice must be a non-negative number.");
    }
    defaultPrice = Math.round(p * 100) / 100;
  } else {
    defaultPrice = raw.defaultPrice === null ? null : undefined;
  }

  let allowedLocationIds: string[] | null | undefined;
  if (raw.allowedLocationIds !== undefined) {
    if (raw.allowedLocationIds === null) {
      allowedLocationIds = null;
    } else if (Array.isArray(raw.allowedLocationIds)) {
      allowedLocationIds = raw.allowedLocationIds.map((id: unknown) => String(id).trim()).filter(Boolean);
    }
  }

  const telehealth = assertBoolean(raw.telehealth, "telehealth");

  let allowedPractitionerIds: string[] | null | undefined;
  if (raw.allowedPractitionerIds !== undefined) {
    if (raw.allowedPractitionerIds === null) {
      allowedPractitionerIds = null;
    } else if (Array.isArray(raw.allowedPractitionerIds)) {
      allowedPractitionerIds = raw.allowedPractitionerIds.map((id: unknown) => String(id).trim()).filter(Boolean);
    }
  }

  const out: UpsertAppointmentTypePatch = {};
  if (name != null) out.name = name;
  if (durationMinutes != null) out.durationMinutes = durationMinutes;
  if (colorHex !== undefined) out.colorHex = colorHex ?? null;
  if (active !== undefined && active !== null) out.active = active;
  if (showInOnlineBooking !== undefined && showInOnlineBooking !== null) out.showInOnlineBooking = showInOnlineBooking;
  if (description !== undefined) out.description = description ?? null;
  if (defaultPrice !== undefined) out.defaultPrice = defaultPrice;
  if (allowedLocationIds !== undefined) out.allowedLocationIds = allowedLocationIds;
  if (telehealth !== undefined && telehealth !== null) out.telehealth = telehealth;
  if (allowedPractitionerIds !== undefined) out.allowedPractitionerIds = allowedPractitionerIds;
  return out;
}

export async function upsertAppointmentType(request: { auth?: { uid?: string }; data?: unknown }) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }

  const data = request.data as Record<string, unknown> | undefined;
  const clinicId = requireNonEmptyString(data?.clinicId, "clinicId");
  const appointmentTypeIdRaw = data?.appointmentTypeId;
  const appointmentTypeId =
    appointmentTypeIdRaw === null || appointmentTypeIdRaw === undefined || appointmentTypeIdRaw === ""
      ? null
      : String(appointmentTypeIdRaw).trim();
  const isCreate = !appointmentTypeId || appointmentTypeId.length === 0;

  let patch: UpsertAppointmentTypePatch;
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

  try {
    return await upsertAppointmentTypeImpl(db, clinicId, uid, appointmentTypeId, isCreate, patch);
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    const message = e instanceof Error ? e.message : String(e);
    throw new HttpsError("internal", message || "Failed to save appointment type.");
  }
}

async function upsertAppointmentTypeImpl(
  db: Firestore,
  clinicId: string,
  uid: string,
  appointmentTypeId: string | null,
  isCreate: boolean,
  patch: UpsertAppointmentTypePatch
): Promise<{ ok: boolean; appointmentTypeId: string }> {
  const colRef = db.collection("clinics").doc(clinicId).collection("appointmentTypes");
  const now = FV.serverTimestamp();

  if (isCreate) {
    const finalId = colRef.doc().id;
    const doc = {
      name: patch.name ?? "",
      durationMinutes: patch.durationMinutes ?? 30,
      colorHex: patch.colorHex ?? null,
      active: patch.active ?? true,
      showInOnlineBooking: patch.showInOnlineBooking ?? false,
      description: patch.description ?? null,
      defaultPrice: patch.defaultPrice ?? null,
      allowedLocationIds: patch.allowedLocationIds ?? null,
      telehealth: patch.telehealth ?? false,
      allowedPractitionerIds: patch.allowedPractitionerIds ?? null,
      createdAt: now,
      updatedAt: now,
    };
    await colRef.doc(finalId).set(doc);

    const changes: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(doc)) {
      if (k !== "createdAt" && k !== "updatedAt") changes[k] = v;
    }
    await writeSettingsAuditEvent(
      db,
      clinicId,
      "settings.appointmentType.created",
      uid,
      `clinics/${clinicId}/appointmentTypes/${finalId}`,
      finalId,
      changes
    );
    return { ok: true, appointmentTypeId: finalId };
  }

  const ref = colRef.doc(appointmentTypeId!);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Appointment type not found.");
  }

  const existing = snap.data() ?? {};
  const updateData: Record<string, unknown> = { updatedAt: now };
  const changes: Record<string, unknown> = {};

  for (const key of Object.keys(patch)) {
    updateData[key] = (patch as any)[key];
    changes[key] = { before: existing[key], after: (patch as any)[key] };
  }

  await ref.update(updateData);

  await writeSettingsAuditEvent(
    db,
    clinicId,
    "settings.appointmentType.updated",
    uid,
    `clinics/${clinicId}/appointmentTypes/${appointmentTypeId}`,
    appointmentTypeId!,
    changes
  );
  return { ok: true, appointmentTypeId: appointmentTypeId! };
}
