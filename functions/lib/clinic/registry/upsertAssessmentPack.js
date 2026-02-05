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
exports.upsertAssessmentPack = upsertAssessmentPack;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const _helpers_1 = require("./_helpers");
async function upsertAssessmentPack(req) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m;
    const { db, clinicId, uid } = await (0, _helpers_1.requireTemplatesManage)(req);
    const name = (0, _helpers_1.cleanString)((_a = req.data) === null || _a === void 0 ? void 0 : _a.name, 120);
    const bodyRegion = (0, _helpers_1.cleanString)((_b = req.data) === null || _b === void 0 ? void 0 : _b.bodyRegion, 60);
    if (!name || !bodyRegion) {
        throw new https_1.HttpsError("invalid-argument", "name and bodyRegion required.");
    }
    const packId = ((_d = (_c = req.data) === null || _c === void 0 ? void 0 : _c.packId) !== null && _d !== void 0 ? _d : "").toString().trim();
    const ref = packId
        ? db.collection("clinics").doc(clinicId).collection("assessmentPacks").doc(packId)
        : db.collection("clinics").doc(clinicId).collection("assessmentPacks").doc();
    const now = admin.firestore.FieldValue.serverTimestamp();
    const payload = {
        schemaVersion: 1,
        name,
        bodyRegion,
        defaultSide: (0, _helpers_1.cleanString)((_e = req.data) === null || _e === void 0 ? void 0 : _e.defaultSide, 20) || "central",
        noteTypes: (0, _helpers_1.asStringArray)((_f = req.data) === null || _f === void 0 ? void 0 : _f.noteTypes),
        objectiveTemplate: (_h = (_g = req.data) === null || _g === void 0 ? void 0 : _g.objectiveTemplate) !== null && _h !== void 0 ? _h : {},
        subjectiveTemplate: (_k = (_j = req.data) === null || _j === void 0 ? void 0 : _j.subjectiveTemplate) !== null && _k !== void 0 ? _k : {},
        active: ((_m = (_l = req.data) === null || _l === void 0 ? void 0 : _l.active) !== null && _m !== void 0 ? _m : true) === true,
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
    return { success: true, packId: ref.id };
}
//# sourceMappingURL=upsertAssessmentPack.js.map