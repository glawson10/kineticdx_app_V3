"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.upsertTax = upsertTax;
const https_1 = require("firebase-functions/v2/https");
const audit_1 = require("../audit/audit");
const common_1 = require("./common");
async function upsertTax(request) {
    var _a;
    const uid = (0, common_1.requireAuthUid)(request);
    const data = (0, common_1.asObject)(request.data);
    const clinicId = (0, common_1.requireString)(data.clinicId, "clinicId", 2, 120);
    await (0, common_1.requireBillingWrite)(clinicId, uid);
    const taxIdRaw = String((_a = data.taxId) !== null && _a !== void 0 ? _a : "").trim();
    const isCreate = taxIdRaw.length === 0;
    const patch = (0, common_1.asObject)(data.patch);
    const name = patch.name !== undefined ? (0, common_1.requireString)(patch.name, "name", 2, 80) : undefined;
    const rate = patch.rate !== undefined ? (0, common_1.asNonNegativeNumber)(patch.rate, "rate", 100) : undefined;
    if (rate !== undefined && rate > 100) {
        throw new https_1.HttpsError("invalid-argument", "rate must be between 0 and 100.");
    }
    const active = (0, common_1.asBoolean)(patch.active, "active");
    if (isCreate && name === undefined) {
        throw new https_1.HttpsError("invalid-argument", "name is required when creating a tax.");
    }
    const now = common_1.FV.serverTimestamp();
    const col = (0, common_1.taxesCol)(clinicId);
    if (isCreate) {
        const ref = col.doc();
        const doc = {
            name: name,
            rate: rate !== null && rate !== void 0 ? rate : 0,
            active: active !== null && active !== void 0 ? active : true,
            createdAt: now,
            updatedAt: now,
        };
        await ref.set(doc);
        await (0, audit_1.writeSettingsAuditEvent)(col.firestore, clinicId, "settings.tax.created", uid, `clinics/${clinicId}/taxes/${ref.id}`, ref.id, { name: doc.name, rate: doc.rate, active: doc.active });
        return { ok: true, taxId: ref.id };
    }
    const ref = col.doc(taxIdRaw);
    const snap = await ref.get();
    if (!snap.exists)
        throw new https_1.HttpsError("not-found", "Tax not found.");
    const existing = snap.data() || {};
    const update = { updatedAt: now };
    const changes = {};
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
        throw new https_1.HttpsError("invalid-argument", "No valid fields to update.");
    }
    await ref.update(update);
    await (0, audit_1.writeSettingsAuditEvent)(col.firestore, clinicId, "settings.tax.updated", uid, `clinics/${clinicId}/taxes/${taxIdRaw}`, taxIdRaw, changes);
    return { ok: true, taxId: taxIdRaw };
}
//# sourceMappingURL=upsertTax.js.map