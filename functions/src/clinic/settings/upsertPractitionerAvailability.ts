/**
 * Commit 31: settings.upsertPractitionerAvailability
 * Create or update base recurring availability for a practitioner.
 * Path: clinics/{clinicId}/practitioners/{practitionerId}/availability/{availabilityId}
 */

import * as admin from "firebase-admin";
import type { Firestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { requireClinicPermission } from "../permissions";
import { writeSettingsAuditEvent } from "../audit/audit";
import { requireNonEmptyString } from "./validators";
import {
  assertIsoDate,
  assertTimeHHmm,
  assertNoOverlaps,
  MAX_BLOCKS,
  MAX_INTERVAL,
  type AvailabilityBlock,
} from "./practitionerAvailabilityValidation";
import { assertString, assertBoolean, assertIntRange } from "./validators";
import { mirrorPractitionerAvailabilityToLegacy } from "./mirrorPractitionerAvailabilityToLegacy";

const db = admin.firestore();
const FV = admin.firestore.FieldValue;

const FREQUENCY_SET = new Set(["weekly", "biweekly", "monthly"]);

function validatePatch(patch: unknown): {
  locationId: string;
  startDate: string;
  endDate: string | null;
  recurrenceRule: { frequency: string; interval: number };
  blocks: AvailabilityBlock[];
  description: string | null;
  active: boolean;
} {
  if (patch == null || typeof patch !== "object") {
    throw new HttpsError("invalid-argument", "patch is required.");
  }
  const p = patch as Record<string, unknown>;

  const locationId = requireNonEmptyString(p.locationId, "locationId");
  const startDate = assertIsoDate(p.startDate, "startDate");
  const endDateRaw = p.endDate;
  let endDate: string | null = null;
  if (endDateRaw != null && endDateRaw !== "") {
    const parsedEnd = assertIsoDate(endDateRaw, "endDate");
    if (parsedEnd < startDate) {
      throw new HttpsError("invalid-argument", "endDate must be >= startDate.");
    }
    endDate = parsedEnd;
  }

  const rr = p.recurrenceRule;
  if (rr == null || typeof rr !== "object") {
    throw new HttpsError("invalid-argument", "recurrenceRule is required.");
  }
  const r = rr as Record<string, unknown>;
  const frequency = assertString(r.frequency, "recurrenceRule.frequency", { required: true });
  if (!frequency || frequency.length === 0) {
    throw new HttpsError("invalid-argument", "recurrenceRule.frequency is required.");
  }
  if (!FREQUENCY_SET.has(frequency)) {
    throw new HttpsError(
      "invalid-argument",
      "recurrenceRule.frequency must be one of: weekly, biweekly, monthly."
    );
  }
  const interval = assertIntRange(r.interval, "recurrenceRule.interval", {
    min: 1,
    max: MAX_INTERVAL,
    required: true,
  });
  if (interval == null) {
    throw new HttpsError("invalid-argument", "recurrenceRule.interval is required.");
  }

  const description =
    assertString(p.description, "description", { trim: true, maxLength: 500 }) ?? null;
  const active = assertBoolean(p.active, "active") ?? true;

  const blocksRaw = p.blocks;
  if (!Array.isArray(blocksRaw) || blocksRaw.length > MAX_BLOCKS) {
    throw new HttpsError(
      "invalid-argument",
      `blocks must be an array of length 0 to ${MAX_BLOCKS}.`
    );
  }
  if (active && blocksRaw.length === 0) {
    throw new HttpsError("invalid-argument", "When active is true, at least one block is required.");
  }
  const blocks: AvailabilityBlock[] = [];
  for (let i = 0; i < blocksRaw.length; i++) {
    const b = blocksRaw[i];
    if (b == null || typeof b !== "object") {
      throw new HttpsError("invalid-argument", `blocks[${i}] must be an object.`);
    }
    const block = b as Record<string, unknown>;
    const dayOfWeek = assertIntRange(block.dayOfWeek, "blocks[].dayOfWeek", {
      min: 1,
      max: 7,
      required: true,
    });
    if (dayOfWeek == null) {
      throw new HttpsError("invalid-argument", "blocks[].dayOfWeek is required (1–7).");
    }
    const startTime = assertTimeHHmm(block.startTime, "blocks[].startTime");
    const endTime = assertTimeHHmm(block.endTime, "blocks[].endTime");
    const bookableOnline = assertBoolean(block.bookableOnline, "blocks[].bookableOnline");
    blocks.push({
      dayOfWeek,
      startTime,
      endTime,
      bookableOnline: bookableOnline ?? true,
    });
  }
  if (blocks.length > 0) assertNoOverlaps(blocks);

  return {
    locationId,
    startDate,
    endDate,
    recurrenceRule: { frequency, interval },
    blocks,
    description,
    active,
  };
}

export async function upsertPractitionerAvailability(request: {
  auth?: { uid?: string };
  data?: unknown;
}) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }

  const data = request.data as Record<string, unknown> | undefined;
  const clinicId = requireNonEmptyString(data?.clinicId, "clinicId");
  const practitionerId = requireNonEmptyString(data?.practitionerId, "practitionerId");
  const availabilityIdRaw = data?.availabilityId;
  const availabilityId =
    availabilityIdRaw === null || availabilityIdRaw === undefined || availabilityIdRaw === ""
      ? null
      : String(availabilityIdRaw).trim();
  const isCreate = !availabilityId || availabilityId.length === 0;

  let validated: ReturnType<typeof validatePatch>;
  try {
    validated = validatePatch(data?.patch);
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    throw new HttpsError("invalid-argument", e instanceof Error ? e.message : "Invalid patch.");
  }

  const uid = request.auth.uid;
  await requireClinicPermission(db, clinicId, uid, "settings.write");

  try {
    return await upsertPractitionerAvailabilityImpl(db, clinicId, practitionerId, uid, availabilityId, isCreate, validated);
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    const message = e instanceof Error ? e.message : String(e);
    throw new HttpsError("internal", message || "Failed to save availability rule.");
  }
}

async function upsertPractitionerAvailabilityImpl(
  db: Firestore,
  clinicId: string,
  practitionerId: string,
  uid: string,
  availabilityId: string | null,
  isCreate: boolean,
  validated: ReturnType<typeof validatePatch>
): Promise<{ ok: boolean; availabilityId: string }> {
  const colRef = db
    .collection("clinics")
    .doc(clinicId)
    .collection("practitioners")
    .doc(practitionerId)
    .collection("availability");

  const now = FV.serverTimestamp();

  if (isCreate) {
    const docId = colRef.doc().id;
    const doc = {
      locationId: validated.locationId,
      startDate: validated.startDate,
      endDate: validated.endDate ?? null,
      recurrenceRule: validated.recurrenceRule,
      blocks: validated.blocks,
      description: validated.description ?? null,
      active: validated.active,
      createdAt: now,
      updatedAt: now,
    };
    await colRef.doc(docId).set(doc);
    const entityPath = `clinics/${clinicId}/practitioners/${practitionerId}/availability/${docId}`;
    await writeSettingsAuditEvent(
      db,
      clinicId,
      "settings.availability.created",
      uid,
      entityPath,
      docId,
      { locationId: validated.locationId, startDate: validated.startDate, active: validated.active }
    );
    await mirrorPractitionerAvailabilityToLegacy(clinicId, practitionerId);
    return { ok: true, availabilityId: docId };
  }

  const ref = colRef.doc(availabilityId!);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Availability not found.");
  }

  const beforeActive = snap.data()?.active;
  const updateData: Record<string, unknown> = {
    locationId: validated.locationId,
    startDate: validated.startDate,
    endDate: validated.endDate ?? null,
    recurrenceRule: validated.recurrenceRule,
    blocks: validated.blocks,
    description: validated.description ?? null,
    active: validated.active,
    updatedAt: now,
  };
  await ref.update(updateData);

  const entityPath = `clinics/${clinicId}/practitioners/${practitionerId}/availability/${availabilityId}`;
  const prev = snap.data() ?? {};
  const keysExceptActive = ["locationId", "startDate", "endDate", "recurrenceRule", "blocks", "description"];
  const onlyActiveChanged =
    beforeActive !== validated.active &&
    keysExceptActive.every(
      (k) => JSON.stringify(prev[k]) === JSON.stringify(updateData[k])
    );

  if (onlyActiveChanged) {
    const eventType = validated.active
      ? "settings.availability.activated"
      : "settings.availability.deactivated";
    await writeSettingsAuditEvent(db, clinicId, eventType, uid, entityPath, availabilityId!, {
      active: { before: beforeActive, after: validated.active },
    });
  } else {
    const { updatedAt: _unused, ...changesForAudit } = updateData;
    await writeSettingsAuditEvent(db, clinicId, "settings.availability.updated", uid, entityPath, availabilityId!, changesForAudit);
  }
  await mirrorPractitionerAvailabilityToLegacy(clinicId, practitionerId);
  return { ok: true, availabilityId: availabilityId! };
}
