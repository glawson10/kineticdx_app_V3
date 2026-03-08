"use strict";
/**
 * Commit 31: settings.deletePractitionerOverride
 * Hard delete a practitioner override.
 * Path: clinics/{clinicId}/practitioners/{practitionerId}/overrides/{overrideId}
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
exports.deletePractitionerOverride = deletePractitionerOverride;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const permissions_1 = require("../permissions");
const audit_1 = require("../audit/audit");
const validators_1 = require("./validators");
const mirrorPractitionerAvailabilityToLegacy_1 = require("./mirrorPractitionerAvailabilityToLegacy");
const db = admin.firestore();
async function deletePractitionerOverride(request) {
    var _a;
    if (!((_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid)) {
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    }
    const data = request.data;
    const clinicId = (0, validators_1.requireNonEmptyString)(data === null || data === void 0 ? void 0 : data.clinicId, "clinicId");
    const practitionerId = (0, validators_1.requireNonEmptyString)(data === null || data === void 0 ? void 0 : data.practitionerId, "practitionerId");
    const overrideId = (0, validators_1.requireNonEmptyString)(data === null || data === void 0 ? void 0 : data.overrideId, "overrideId");
    const uid = request.auth.uid;
    await (0, permissions_1.requireClinicPermission)(db, clinicId, uid, "settings.write");
    const ref = db
        .collection("clinics")
        .doc(clinicId)
        .collection("practitioners")
        .doc(practitionerId)
        .collection("overrides")
        .doc(overrideId);
    const snap = await ref.get();
    if (!snap.exists) {
        throw new https_1.HttpsError("not-found", "Override not found.");
    }
    await ref.delete();
    const entityPath = `clinics/${clinicId}/practitioners/${practitionerId}/overrides/${overrideId}`;
    await (0, audit_1.writeSettingsAuditEvent)(db, clinicId, "settings.override.deleted", uid, entityPath, overrideId, {
        deleted: true,
    });
    await (0, mirrorPractitionerAvailabilityToLegacy_1.mirrorPractitionerAvailabilityToLegacy)(clinicId, practitionerId);
    return { ok: true };
}
//# sourceMappingURL=deletePractitionerOverride.js.map