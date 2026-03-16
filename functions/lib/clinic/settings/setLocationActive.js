"use strict";
/**
 * settings.setLocationActive
 * Toggle active flag for a location.
 * Write path: clinics/{clinicId}/locations/{locationId}
 * Audit: settings.location.activated (false→true) or settings.location.deactivated (true→false).
 */
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
exports.setLocationActive = setLocationActive;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const permissions_1 = require("../permissions");
const audit_1 = require("../audit/audit");
const validators_1 = require("./validators");
const db = admin.firestore();
const FV = admin.firestore.FieldValue;
async function setLocationActive(request) {
    var _a, _b;
    if (!((_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid)) {
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    }
    const data = request.data;
    const clinicId = (0, validators_1.requireNonEmptyString)(data === null || data === void 0 ? void 0 : data.clinicId, "clinicId");
    const locationId = (0, validators_1.requireNonEmptyString)(data === null || data === void 0 ? void 0 : data.locationId, "locationId");
    if (typeof (data === null || data === void 0 ? void 0 : data.active) !== "boolean") {
        throw new https_1.HttpsError("invalid-argument", "active must be a boolean.");
    }
    const active = data.active;
    const uid = request.auth.uid;
    await (0, permissions_1.requireClinicPermission)(db, clinicId, uid, "settings.write");
    const ref = db
        .collection("clinics")
        .doc(clinicId)
        .collection("locations")
        .doc(locationId);
    const snap = await ref.get();
    if (!snap.exists) {
        throw new https_1.HttpsError("not-found", "Location not found.");
    }
    const beforeActive = (_b = snap.data()) === null || _b === void 0 ? void 0 : _b.active;
    // TODO: Future guard: do not allow deactivating a location that has future appointments
    // (requires reliable query for appointments by locationId).
    await ref.update({ active, updatedAt: FV.serverTimestamp() });
    const entityPath = `clinics/${clinicId}/locations/${locationId}`;
    const eventType = beforeActive === false && active === true
        ? "settings.location.activated"
        : beforeActive === true && active === false
            ? "settings.location.deactivated"
            : "settings.location.active_set";
    await (0, audit_1.writeSettingsAuditEvent)(db, clinicId, eventType, uid, entityPath, locationId, {
        active: { before: beforeActive, after: active },
    });
    return { ok: true };
}
//# sourceMappingURL=setLocationActive.js.map