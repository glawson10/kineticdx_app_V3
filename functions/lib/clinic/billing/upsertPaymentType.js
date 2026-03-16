"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.upsertPaymentType = upsertPaymentType;
const https_1 = require("firebase-functions/v2/https");
const audit_1 = require("../audit/audit");
const common_1 = require("./common");
async function upsertPaymentType(request) {
    var _a;
    const uid = (0, common_1.requireAuthUid)(request);
    const data = (0, common_1.asObject)(request.data);
    const clinicId = (0, common_1.requireString)(data.clinicId, "clinicId", 2, 120);
    await (0, common_1.requireBillingWrite)(clinicId, uid);
    const paymentTypeId = String((_a = data.paymentTypeId) !== null && _a !== void 0 ? _a : "").trim();
    const isCreate = paymentTypeId.length === 0;
    const patch = (0, common_1.asObject)(data.patch);
    const name = patch.name !== undefined ? (0, common_1.requireString)(patch.name, "name", 2, 60) : undefined;
    const active = (0, common_1.asBoolean)(patch.active, "active");
    if (isCreate && name === undefined) {
        throw new https_1.HttpsError("invalid-argument", "name is required when creating payment type.");
    }
    const now = common_1.FV.serverTimestamp();
    const col = (0, common_1.paymentTypesCol)(clinicId);
    if (isCreate) {
        const ref = col.doc();
        const doc = {
            name: name,
            active: active !== null && active !== void 0 ? active : true,
            createdAt: now,
            updatedAt: now,
        };
        await ref.set(doc);
        await (0, audit_1.writeSettingsAuditEvent)(col.firestore, clinicId, "settings.paymentType.created", uid, `clinics/${clinicId}/paymentTypes/${ref.id}`, ref.id, { name: doc.name, active: doc.active });
        return { ok: true, paymentTypeId: ref.id };
    }
    const ref = col.doc(paymentTypeId);
    const snap = await ref.get();
    if (!snap.exists)
        throw new https_1.HttpsError("not-found", "Payment type not found.");
    const existing = snap.data() || {};
    const update = { updatedAt: now };
    const changes = {};
    if (name !== undefined) {
        update.name = name;
        changes.name = { before: existing.name, after: name };
    }
    if (active !== undefined) {
        update.active = active;
        changes.active = { before: existing.active, after: active };
    }
    if (Object.keys(changes).length === 0) {
        throw new https_1.HttpsError("invalid-argument", "No valid fields to update.");
    }
    await ref.update(update);
    await (0, audit_1.writeSettingsAuditEvent)(col.firestore, clinicId, "settings.paymentType.updated", uid, `clinics/${clinicId}/paymentTypes/${paymentTypeId}`, paymentTypeId, changes);
    return { ok: true, paymentTypeId };
}
//# sourceMappingURL=upsertPaymentType.js.map