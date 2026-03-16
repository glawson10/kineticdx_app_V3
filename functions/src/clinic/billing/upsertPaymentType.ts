import { HttpsError } from "firebase-functions/v2/https";
import { writeSettingsAuditEvent } from "../audit/audit";
import {
  FV,
  asBoolean,
  asObject,
  paymentTypesCol,
  requireAuthUid,
  requireBillingWrite,
  requireString,
} from "./common";

export async function upsertPaymentType(request: { auth?: { uid?: string }; data?: unknown }) {
  const uid = requireAuthUid(request);
  const data = asObject(request.data);
  const clinicId = requireString(data.clinicId, "clinicId", 2, 120);
  await requireBillingWrite(clinicId, uid);

  const paymentTypeId = String(data.paymentTypeId ?? "").trim();
  const isCreate = paymentTypeId.length === 0;
  const patch = asObject(data.patch);

  const name = patch.name !== undefined ? requireString(patch.name, "name", 2, 60) : undefined;
  const active = asBoolean(patch.active, "active");
  if (isCreate && name === undefined) {
    throw new HttpsError("invalid-argument", "name is required when creating payment type.");
  }

  const now = FV.serverTimestamp();
  const col = paymentTypesCol(clinicId);
  if (isCreate) {
    const ref = col.doc();
    const doc = {
      name: name!,
      active: active ?? true,
      createdAt: now,
      updatedAt: now,
    };
    await ref.set(doc);
    await writeSettingsAuditEvent(
      col.firestore,
      clinicId,
      "settings.paymentType.created",
      uid,
      `clinics/${clinicId}/paymentTypes/${ref.id}`,
      ref.id,
      { name: doc.name, active: doc.active }
    );
    return { ok: true, paymentTypeId: ref.id };
  }

  const ref = col.doc(paymentTypeId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Payment type not found.");
  const existing = snap.data() || {};

  const update: Record<string, unknown> = { updatedAt: now };
  const changes: Record<string, unknown> = {};
  if (name !== undefined) {
    update.name = name;
    changes.name = { before: existing.name, after: name };
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
    "settings.paymentType.updated",
    uid,
    `clinics/${clinicId}/paymentTypes/${paymentTypeId}`,
    paymentTypeId,
    changes
  );
  return { ok: true, paymentTypeId };
}
