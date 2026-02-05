"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.upsertClinicalTest = upsertClinicalTest;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const _helpers_1 = require("./_helpers");
async function upsertClinicalTest(req) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q, _r;
    const { db, clinicId, uid } = await (0, _helpers_1.requireTemplatesManage)(req);
    const name = (0, _helpers_1.cleanString)((_a = req.data) === null || _a === void 0 ? void 0 : _a.name, 120);
    if (!name)
        throw new https_1.HttpsError("invalid-argument", "name required.");
    const testId = ((_c = (_b = req.data) === null || _b === void 0 ? void 0 : _b.testId) !== null && _c !== void 0 ? _c : "").toString().trim();
    const ref = testId
        ? db.collection("clinics").doc(clinicId).collection("clinicalTestRegistry").doc(testId)
        : db.collection("clinics").doc(clinicId).collection("clinicalTestRegistry").doc();
    const now = admin.firestore.FieldValue.serverTimestamp();
    const payload = {
        schemaVersion: 1,
        name,
        shortName: (0, _helpers_1.cleanString)((_d = req.data) === null || _d === void 0 ? void 0 : _d.shortName, 80) || null,
        bodyRegions: (0, _helpers_1.asStringArray)((_e = req.data) === null || _e === void 0 ? void 0 : _e.bodyRegions),
        tags: (0, _helpers_1.asStringArray)((_f = req.data) === null || _f === void 0 ? void 0 : _f.tags),
        category: (0, _helpers_1.cleanString)((_g = req.data) === null || _g === void 0 ? void 0 : _g.category, 80) || "special_test",
        instructions: (0, _helpers_1.cleanString)((_h = req.data) === null || _h === void 0 ? void 0 : _h.instructions, 5000) || null,
        positiveCriteria: (0, _helpers_1.cleanString)((_j = req.data) === null || _j === void 0 ? void 0 : _j.positiveCriteria, 2000) || null,
        contraindications: (0, _helpers_1.cleanString)((_k = req.data) === null || _k === void 0 ? void 0 : _k.contraindications, 2000) || null,
        interpretation: (0, _helpers_1.cleanString)((_l = req.data) === null || _l === void 0 ? void 0 : _l.interpretation, 5000) || null,
        resultType: (0, _helpers_1.cleanString)((_m = req.data) === null || _m === void 0 ? void 0 : _m.resultType, 40) || "ternary",
        allowedResults: (0, _helpers_1.asStringArray)((_o = req.data) === null || _o === void 0 ? void 0 : _o.allowedResults).length > 0
            ? (0, _helpers_1.asStringArray)((_p = req.data) === null || _p === void 0 ? void 0 : _p.allowedResults)
            : ["positive", "negative", "notTested"],
        active: ((_r = (_q = req.data) === null || _q === void 0 ? void 0 : _q.active) !== null && _r !== void 0 ? _r : true) === true,
        updatedAt: now,
        updatedByUid: uid,
    };
    const snap = await ref.get();
    if (!snap.exists) {
        await ref.set({ ...payload, createdAt: now, createdByUid: uid });
    }
    else {
        await ref.update(payload);
    }
    return { success: true, testId: ref.id };
}
//# sourceMappingURL=upsertClinicalTest.js.map