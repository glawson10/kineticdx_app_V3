import { HttpsError } from "firebase-functions/v2/https";
import { writeSettingsAuditEvent } from "../audit/audit";
import {
  FV,
  asBoolean,
  asNonNegativeNumber,
  asObject,
  billableItemsCol,
  requireAuthUid,
  requireBillingWrite,
  requireString,
  taxesCol,
} from "./common";

export async function upsertBillableItem(request: { auth?: { uid?: string }; data?: unknown }) {
  const uid = requireAuthUid(request);
  const data = asObject(request.data);
  const clinicId = requireString(data.clinicId, "clinicId", 2, 120);
  await requireBillingWrite(clinicId, uid);

  const itemId = String(data.itemId ?? "").trim();
  const isCreate = itemId.length === 0;
  const patch = asObject(data.patch);

  const name = patch.name !== undefined ? requireString(patch.name, "name", 2, 120) : undefined;
  const price = patch.price !== undefined ? asNonNegativeNumber(patch.price, "price") : undefined;
  const active = asBoolean(patch.active, "active");

  let taxId: string | null | undefined;
  if (patch.taxId !== undefined) {
    const raw = String(patch.taxId ?? "").trim();
    taxId = raw.length > 0 ? raw : null;
    if (taxId) {
      const taxSnap = await taxesCol(clinicId).doc(taxId).get();
      if (!taxSnap.exists) throw new HttpsError("invalid-argument", "taxId must reference an existing tax.");
    }
  }

  if (isCreate) {
    if (name === undefined || price === undefined) {
      throw new HttpsError("invalid-argument", "name and price are required when creating billable item.");
    }
  }

  const now = FV.serverTimestamp();
  const col = billableItemsCol(clinicId);
  if (isCreate) {
    const ref = col.doc();
    const doc = {
      name: name!,
      price: price!,
      taxId: taxId ?? null,
      active: active ?? true,
      createdAt: now,
      updatedAt: now,
    };
    await ref.set(doc);
    await writeSettingsAuditEvent(
      col.firestore,
      clinicId,
      "settings.billableItem.created",
      uid,
      `clinics/${clinicId}/billableItems/${ref.id}`,
      ref.id,
      { name: doc.name, price: doc.price, taxId: doc.taxId, active: doc.active }
    );
    return { ok: true, itemId: ref.id };
  }

  const ref = col.doc(itemId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Billable item not found.");
  const existing = snap.data() || {};
  const update: Record<string, unknown> = { updatedAt: now };
  const changes: Record<string, unknown> = {};
  if (name !== undefined) {
    update.name = name;
    changes.name = { before: existing.name, after: name };
  }
  if (price !== undefined) {
    update.price = price;
    changes.price = { before: existing.price, after: price };
  }
  if (taxId !== undefined) {
    update.taxId = taxId;
    changes.taxId = { before: existing.taxId ?? null, after: taxId };
  }
  if (active !== undefined) {
    update.active = active;
    changes.active = { before: existing.active, after: active };
  }
  if (Object.keys(changes).length === 0) throw new HttpsError("invalid-argument", "No valid fields to update.");

  await ref.update(update);
  await writeSettingsAuditEvent(
    col.firestore,
    clinicId,
    "settings.billableItem.updated",
    uid,
    `clinics/${clinicId}/billableItems/${itemId}`,
    itemId,
    changes
  );
  return { ok: true, itemId };
}
