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
exports.updateOnlineBookingEnablement = updateOnlineBookingEnablement;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const permissions_1 = require("../permissions");
const audit_1 = require("../audit/audit");
const db = admin.firestore();
const FV = admin.firestore.FieldValue;
function requireNonEmptyString(value, name) {
    const s = typeof value === "string" ? value.trim() : "";
    if (!s)
        throw new https_1.HttpsError("invalid-argument", `${name} is required.`);
    return s;
}
async function updateOnlineBookingEnablement(request) {
    var _a, _b, _c;
    if (!((_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid)) {
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    }
    const data = ((_b = request.data) !== null && _b !== void 0 ? _b : {});
    const clinicId = requireNonEmptyString(data.clinicId, "clinicId");
    const enabled = data.enabled === true;
    const uid = request.auth.uid;
    await (0, permissions_1.requireClinicPermission)(db, clinicId, uid, "settings.write");
    const ref = db.doc(`clinics/${clinicId}/settings/publicBooking`);
    const snap = await ref.get();
    const before = snap.exists ? (((_c = snap.data()) === null || _c === void 0 ? void 0 : _c.onlineBookingEnabled) === true) : false;
    await ref.set({ onlineBookingEnabled: enabled, updatedAt: FV.serverTimestamp(), updatedByUid: uid }, { merge: true });
    await (0, audit_1.writeSettingsAuditEvent)(db, clinicId, "settings.onlineBooking.enablement.updated", uid, `clinics/${clinicId}/settings/publicBooking`, "publicBooking", { onlineBookingEnabled: { before, after: enabled } });
    return { ok: true, onlineBookingEnabled: enabled };
}
//# sourceMappingURL=updateOnlineBookingEnablement.js.map