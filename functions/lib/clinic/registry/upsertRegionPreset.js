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
exports.upsertRegionPreset = upsertRegionPreset;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const _helpers_1 = require("./_helpers");
async function upsertRegionPreset(req) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j;
    const { db, clinicId, uid } = await (0, _helpers_1.requireTemplatesManage)(req);
    const region = (0, _helpers_1.cleanString)((_a = req.data) === null || _a === void 0 ? void 0 : _a.region, 60);
    if (!region)
        throw new https_1.HttpsError("invalid-argument", "region required.");
    const regionId = ((_c = (_b = req.data) === null || _b === void 0 ? void 0 : _b.regionId) !== null && _c !== void 0 ? _c : "").toString().trim();
    const ref = regionId
        ? db.collection("clinics").doc(clinicId).collection("regionPresets").doc(regionId)
        : db.collection("clinics").doc(clinicId).collection("regionPresets").doc(region);
    const now = admin.firestore.FieldValue.serverTimestamp();
    const payload = {
        schemaVersion: 1,
        region,
        displayName: (0, _helpers_1.cleanString)((_d = req.data) === null || _d === void 0 ? void 0 : _d.displayName, 120) || region,
        segments: (0, _helpers_1.asStringArray)((_e = req.data) === null || _e === void 0 ? void 0 : _e.segments),
        defaultEnabled: ((_g = (_f = req.data) === null || _f === void 0 ? void 0 : _f.defaultEnabled) !== null && _g !== void 0 ? _g : true) === true,
        active: ((_j = (_h = req.data) === null || _h === void 0 ? void 0 : _h.active) !== null && _j !== void 0 ? _j : true) === true,
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
    return { success: true, regionId: ref.id };
}
//# sourceMappingURL=upsertRegionPreset.js.map