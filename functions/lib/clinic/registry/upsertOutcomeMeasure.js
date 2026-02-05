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
exports.upsertOutcomeMeasure = upsertOutcomeMeasure;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const _helpers_1 = require("./_helpers");
async function upsertOutcomeMeasure(req) {
    var _a, _b, _c, _d, _e, _f, _g, _h;
    const { db, clinicId, uid } = await (0, _helpers_1.requireTemplatesManage)(req);
    const name = (0, _helpers_1.cleanString)((_a = req.data) === null || _a === void 0 ? void 0 : _a.name, 80);
    if (!name)
        throw new https_1.HttpsError("invalid-argument", "name required.");
    const measureId = ((_c = (_b = req.data) === null || _b === void 0 ? void 0 : _b.measureId) !== null && _c !== void 0 ? _c : "").toString().trim();
    const ref = measureId
        ? db.collection("clinics").doc(clinicId).collection("outcomeMeasures").doc(measureId)
        : db.collection("clinics").doc(clinicId).collection("outcomeMeasures").doc();
    const now = admin.firestore.FieldValue.serverTimestamp();
    const payload = {
        schemaVersion: 1,
        name,
        fullName: (0, _helpers_1.cleanString)((_d = req.data) === null || _d === void 0 ? void 0 : _d.fullName, 200) || null,
        tags: (0, _helpers_1.asStringArray)((_e = req.data) === null || _e === void 0 ? void 0 : _e.tags),
        scoreFormatHint: (0, _helpers_1.cleanString)((_f = req.data) === null || _f === void 0 ? void 0 : _f.scoreFormatHint, 200) || null,
        active: ((_h = (_g = req.data) === null || _g === void 0 ? void 0 : _g.active) !== null && _h !== void 0 ? _h : true) === true,
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
    return { success: true, measureId: ref.id };
}
//# sourceMappingURL=upsertOutcomeMeasure.js.map