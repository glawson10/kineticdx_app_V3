import { HttpsError } from "firebase-functions/v2/https";
import { writeSettingsAuditEvent } from "../audit/audit";
import {
  FV,
  asBoolean,
  asObject,
  asNonNegativeNumber,
  requireAuthUid,
  requireBillingWrite,
  requireString,
  taxesCol,
} from "./common";

export async function upsertTax(request: { auth?: { uid?: string }; data?: unknown }) {
  const uid = requireAuthUid(request);
  const data = asObject(request.data);
  const clinicId = requireString(data.clinicId, "clinicId", 2, 120);
  await requireBillingWrite(clinicId, uid);

  const taxIdRaw = String(data.taxId ?? "").trim();
  const isCreate = taxIdRaw.length === 0;
  const patch = asObject(data.patch);

  const name = patch.name !== undefined ? requireString(patch.name, "name", 2, 80) : undefined;
  const rate = patch.rate !== undefined ? asNonNegativeNumber(patch.rate, "rate", 100) : undefined;
  if (rate !== undefined && rate > 100) {
    throw new HttpsError("invalid-argument", "rate must be between 0 and 100.");
  }
  const active = asBoolean(patch.active, "active");

  if (isCreate && name === undefined) {
    throw new HttpsError("invalid-argument", "name is required when creating a tax.");
  }

  const now = FV.serverTimestamp();
  const col = taxesCol(clinicId);

  if (isCreate) {
    const ref = col.doc();
    const doc = {
      name: name!,
      rate: rate ?? 0,
      active: active ?? true,
      createdAt: now,
      updatedAt: now,
    };
    await ref.set(doc);
    await writeSettingsAuditEvent(
      col.firestore,
      clinicId,
      "settings.tax.created",
      uid,
      `clinics/${clinicId}/taxes/${ref.id}`,
      ref.id,
      { name: doc.name, rate: doc.rate, active: doc.active }
    );
    return { ok: true, taxId: ref.id };
  }

  const ref = col.doc(taxIdRaw);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Tax not found.");

  const existing = snap.data() || {};
  const update: Record<string, unknown> = { updatedAt: now };
  const changes: Record<string, unknown> = {};
  if (name !== undefined) {
    update.name = name;
    changes.name = { before: existing.name, after: name };
  }
  if (rate !== undefined) {
    update.rate = rate;
    changes.rate = { before: existing.rate, after: rate };
  }
  if (active !== undefined) {
    update.active = active;
    changes.active = { before: existing.active, after: active };
  }
  if (Object.keys(changes).length === 0) {
    throw new HttpsError("invalid-argument", "No valid fields to update.");
  }

  await ref.update(update);
  await writeSettingsAuditEvent(
    col.firestore,
    clinicId,
    "settings.tax.updated",
    uid,
    `clinics/${clinicId}/taxes/${taxIdRaw}`,
    taxIdRaw,
    changes
  );
  return { ok: true, taxId: taxIdRaw };
}
