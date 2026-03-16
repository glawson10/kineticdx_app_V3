"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getAgingBucket = void 0;
exports.getAgedReceivables = getAgedReceivables;
const agingBucket_1 = require("./agingBucket");
const common_1 = require("./common");
var agingBucket_2 = require("./agingBucket");
Object.defineProperty(exports, "getAgingBucket", { enumerable: true, get: function () { return agingBucket_2.getAgingBucket; } });
async function getAgedReceivables(request) {
    var _a, _b, _c;
    const uid = (0, common_1.requireAuthUid)(request);
    const data = (0, common_1.asObject)(request.data);
    const clinicId = (0, common_1.requireString)(data.clinicId, "clinicId", 2, 120);
    await (0, common_1.requireBillingRead)(clinicId, uid);
    const now = new Date();
    const buckets = {
        current: 0,
        days30: 0,
        days60: 0,
        days90plus: 0,
    };
    const snap = await (0, common_1.invoicesCol)(clinicId).get();
    for (const doc of snap.docs) {
        const d = doc.data();
        const balance = Number((_a = d.balanceDue) !== null && _a !== void 0 ? _a : 0);
        const status = String((_b = d.status) !== null && _b !== void 0 ? _b : "");
        if (status === "void" || balance <= 0)
            continue;
        const dueRaw = ((_c = d.dueDate) !== null && _c !== void 0 ? _c : d.dueAt);
        const dueDate = (dueRaw === null || dueRaw === void 0 ? void 0 : dueRaw.toDate) ? dueRaw.toDate() : null;
        if (!dueDate) {
            buckets.current = (0, common_1.roundMoney)(buckets.current + balance);
            continue;
        }
        const bucket = (0, agingBucket_1.getAgingBucket)(now, dueDate);
        buckets[bucket] = (0, common_1.roundMoney)(buckets[bucket] + balance);
    }
    return { ok: true, clinicId, buckets };
}
//# sourceMappingURL=getAgedReceivables.js.map