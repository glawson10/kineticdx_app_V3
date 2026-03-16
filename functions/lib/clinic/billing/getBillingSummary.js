"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getBillingSummary = getBillingSummary;
const common_1 = require("./common");
function startOfDay(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate(), 0, 0, 0, 0);
}
function endOfDay(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate(), 23, 59, 59, 999);
}
function startOfMonth(date) {
    return new Date(date.getFullYear(), date.getMonth(), 1, 0, 0, 0, 0);
}
async function getBillingSummary(request) {
    var _a, _b, _c;
    const uid = (0, common_1.requireAuthUid)(request);
    const data = (0, common_1.asObject)(request.data);
    const clinicId = (0, common_1.requireString)(data.clinicId, "clinicId", 2, 120);
    await (0, common_1.requireBillingRead)(clinicId, uid);
    const now = new Date();
    const dayStart = startOfDay(now);
    const dayEnd = endOfDay(now);
    const monthStart = startOfMonth(now);
    const invoicesSnap = await (0, common_1.invoicesCol)(clinicId).get();
    let revenueToday = 0;
    let revenueMonth = 0;
    let outstanding = 0;
    const docs = invoicesSnap.docs;
    for (const doc of docs) {
        const d = doc.data();
        const total = Number((_a = d.total) !== null && _a !== void 0 ? _a : 0);
        const balance = Number((_b = d.balanceDue) !== null && _b !== void 0 ? _b : 0);
        const status = String((_c = d.status) !== null && _c !== void 0 ? _c : "");
        const ts = d.updatedAt;
        const date = (ts === null || ts === void 0 ? void 0 : ts.toDate) ? ts.toDate() : null;
        if (status === "paid" && date) {
            if (date >= dayStart && date <= dayEnd)
                revenueToday = (0, common_1.roundMoney)(revenueToday + total);
            if (date >= monthStart)
                revenueMonth = (0, common_1.roundMoney)(revenueMonth + total);
        }
        if (status !== "void" && balance > 0) {
            outstanding = (0, common_1.roundMoney)(outstanding + balance);
        }
    }
    // Recent activity from same snapshot (no extra listeners): last 5 by updatedAt
    const sorted = [...docs].sort((a, b) => {
        var _a, _b, _c, _d, _e, _f, _g, _h;
        const at = (_d = (_c = (_b = (_a = a.data().updatedAt) === null || _a === void 0 ? void 0 : _a.toDate) === null || _b === void 0 ? void 0 : _b.call(_a)) === null || _c === void 0 ? void 0 : _c.getTime()) !== null && _d !== void 0 ? _d : 0;
        const bt = (_h = (_g = (_f = (_e = b.data().updatedAt) === null || _e === void 0 ? void 0 : _e.toDate) === null || _f === void 0 ? void 0 : _f.call(_e)) === null || _g === void 0 ? void 0 : _g.getTime()) !== null && _h !== void 0 ? _h : 0;
        return bt - at;
    });
    const recentActivity = sorted.slice(0, 5).map((docRef) => {
        var _a;
        const d = docRef.data();
        const status = String((_a = d.status) !== null && _a !== void 0 ? _a : "");
        const snap = d.issuedSnapshot;
        const numResult = snap === null || snap === void 0 ? void 0 : snap.numberingResult;
        const displayNumber = (numResult === null || numResult === void 0 ? void 0 : numResult.displayNumber) != null ? String(numResult.displayNumber) : (d.displayNumber != null ? String(d.displayNumber) : docRef.id.slice(0, 8));
        const ts = d.updatedAt;
        const updatedAt = (ts === null || ts === void 0 ? void 0 : ts.toDate) ? ts.toDate().toISOString() : new Date(0).toISOString();
        return { invoiceId: docRef.id, displayNumber, status, updatedAt };
    });
    return {
        ok: true,
        clinicId,
        revenueToday,
        revenueMonth,
        outstandingInvoices: outstanding,
        recentActivity,
    };
}
//# sourceMappingURL=getBillingSummary.js.map