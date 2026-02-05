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
exports.setRegistryActive = setRegistryActive;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const _helpers_1 = require("./_helpers");
async function setRegistryActive(req) {
    var _a, _b, _c;
    const { db, clinicId, uid } = await (0, _helpers_1.requireTemplatesManage)(req);
    const collection = (_a = req.data) === null || _a === void 0 ? void 0 : _a.collection;
    const id = ((_c = (_b = req.data) === null || _b === void 0 ? void 0 : _b.id) !== null && _c !== void 0 ? _c : "").trim();
    if (!collection || !id) {
        throw new https_1.HttpsError("invalid-argument", "collection and id required.");
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    await db.collection("clinics").doc(clinicId)
        .collection(collection)
        .doc(id)
        .update({
        active: req.data.active === true,
        updatedAt: now,
        updatedByUid: uid,
    });
    return { success: true };
}
//# sourceMappingURL=setRegistryActive.js.map