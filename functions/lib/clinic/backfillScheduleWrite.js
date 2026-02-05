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
exports.backfillScheduleWrite = backfillScheduleWrite;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const authz_1 = require("./authz");
async function backfillScheduleWrite(req) {
    var _a, _b, _c, _d;
    if (!req.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const clinicId = ((_b = (_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId) !== null && _b !== void 0 ? _b : "").toString().trim();
    if (!clinicId)
        throw new https_1.HttpsError("invalid-argument", "clinicId is required.");
    const db = admin.firestore();
    const uid = req.auth.uid;
    // ✅ requester must be active + members.manage
    await (0, authz_1.requireActiveMemberWithPerm)(db, clinicId, uid, "members.manage");
    // ✅ canonical memberships
    const canonSnap = await db
        .collection("clinics")
        .doc(clinicId)
        .collection("memberships")
        .get();
    const batch = db.batch();
    let count = 0;
    const now = admin.firestore.FieldValue.serverTimestamp();
    for (const doc of canonSnap.docs) {
        const data = doc.data();
        const perms = ((_c = data.permissions) !== null && _c !== void 0 ? _c : {});
        if (perms["schedule.read"] === true && perms["schedule.write"] !== true) {
            batch.update(doc.ref, {
                "permissions.schedule.write": true,
                updatedAt: now,
            });
            count++;
        }
    }
    // Optional: keep legacy in sync during migration
    const legacySnap = await db
        .collection("clinics")
        .doc(clinicId)
        .collection("members")
        .get();
    for (const doc of legacySnap.docs) {
        const data = doc.data();
        const perms = ((_d = data.permissions) !== null && _d !== void 0 ? _d : {});
        if (perms["schedule.read"] === true && perms["schedule.write"] !== true) {
            batch.update(doc.ref, {
                "permissions.schedule.write": true,
                updatedAt: now,
            });
            // don't double count if same UID exists in both
            // (count tracks canonical primarily)
        }
    }
    if (count === 0 && legacySnap.empty)
        return { success: true, updated: 0 };
    await batch.commit();
    return { success: true, updated: count };
}
//# sourceMappingURL=backfillScheduleWrite.js.map