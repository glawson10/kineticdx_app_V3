"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.upsertBillableItem = upsertBillableItem;
const https_1 = require("firebase-functions/v2/https");
const audit_1 = require("../audit/audit");
const common_1 = require("./common");
async function upsertBillableItem(request) {
    var _a, _b, _c;
    const uid = (0, common_1.requireAuthUid)(request);
    const data = (0, common_1.asObject)(request.data);
    const clinicId = (0, common_1.requireString)(data.clinicId, "clinicId", 2, 120);
    await (0, common_1.requireBillingWrite)(clinicId, uid);
    const itemId = String((_a = data.itemId) !== null && _a !== void 0 ? _a : "").trim();
    const isCreate = itemId.length === 0;
    const patch = (0, common_1.asObject)(data.patch);
    const name = patch.name !== undefined ? (0, common_1.requireString)(patch.name, "name", 2, 120) : undefined;
    const price = patch.price !== undefined ? (0, common_1.asNonNegativeNumber)(patch.price, "price") : undefined;
    const active = (0, common_1.asBoolean)(patch.active, "active");
    let taxId;
    if (patch.taxId !== undefined) {
        const raw = String((_b = patch.taxId) !== null && _b !== void 0 ? _b : "").trim();
        taxId = raw.length > 0 ? raw : null;
        if (taxId) {
            const taxSnap = await (0, common_1.taxesCol)(clinicId).doc(taxId).get();
            if (!taxSnap.exists)
                throw new https_1.HttpsError("invalid-argument", "taxId must reference an existing tax.");
        }
    }
    if (isCreate) {
        if (name === undefined || price === undefined) {
            throw new https_1.HttpsError("invalid-argument", "name and price are required when creating billable item.");
        }
    }
    const now = common_1.FV.serverTimestamp();
    const col = (0, common_1.billableItemsCol)(clinicId);
    if (isCreate) {
        const ref = col.doc();
        const doc = {
            name: name,
            price: price,
            taxId: taxId !== null && taxId !== void 0 ? taxId : null,
            active: active !== null && active !== void 0 ? active : true,
            createdAt: now,
            updatedAt: now,
        };
        await ref.set(doc);
        await (0, audit_1.writeSettingsAuditEvent)(col.firestore, clinicId, "settings.billableItem.created", uid, `clinics/${clinicId}/billableItems/${ref.id}`, ref.id, { name: doc.name, price: doc.price, taxId: doc.taxId, active: doc.active });
        return { ok: true, itemId: ref.id };
    }
    const ref = col.doc(itemId);
    const snap = await ref.get();
    if (!snap.exists)
        throw new https_1.HttpsError("not-found", "Billable item not found.");
    const existing = snap.data() || {};
    const update = { updatedAt: now };
    const changes = {};
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
        changes.taxId = { before: (_c = existing.taxId) !== null && _c !== void 0 ? _c : null, after: taxId };
    }
    if (active !== undefined) {
        update.active = active;
        changes.active = { before: existing.active, after: active };
    }
    if (Object.keys(changes).length === 0)
        throw new https_1.HttpsError("invalid-argument", "No valid fields to update.");
    await ref.update(update);
    await (0, audit_1.writeSettingsAuditEvent)(col.firestore, clinicId, "settings.billableItem.updated", uid, `clinics/${clinicId}/billableItems/${itemId}`, itemId, changes);
    return { ok: true, itemId };
}
//# sourceMappingURL=upsertBillableItem.js.map