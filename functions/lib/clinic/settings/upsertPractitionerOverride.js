"use strict";
/**
 * Commit 31: settings.upsertPractitionerOverride
 * Create or update a time-bounded override for a practitioner.
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
exports.upsertPractitionerOverride = upsertPractitionerOverride;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const permissions_1 = require("../permissions");
const audit_1 = require("../audit/audit");
const validators_1 = require("./validators");
const practitionerAvailabilityValidation_1 = require("./practitionerAvailabilityValidation");
const mirrorPractitionerAvailabilityToLegacy_1 = require("./mirrorPractitionerAvailabilityToLegacy");
const db = admin.firestore();
const FV = admin.firestore.FieldValue;
const OVERRIDE_REASON_SET = new Set(["sickness", "holiday", "training", "other"]);
function validateOverridePatch(patch) {
    var _a;
    if (patch == null || typeof patch !== "object") {
        throw new https_1.HttpsError("invalid-argument", "patch is required.");
    }
    const p = patch;
    const fromAt = (0, practitionerAvailabilityValidation_1.parseTimestampInput)(p.fromAt, "fromAt");
    const toAt = (0, practitionerAvailabilityValidation_1.parseTimestampInput)(p.toAt, "toAt");
    if (toAt.toMillis() <= fromAt.toMillis()) {
        throw new https_1.HttpsError("invalid-argument", "toAt must be after fromAt.");
    }
    const isAvailableRaw = p.isAvailable;
    if (isAvailableRaw === undefined || isAvailableRaw === null) {
        throw new https_1.HttpsError("invalid-argument", "isAvailable is required.");
    }
    if (typeof isAvailableRaw !== "boolean") {
        throw new https_1.HttpsError("invalid-argument", "isAvailable must be a boolean.");
    }
    const locationId = p.locationId === null || p.locationId === undefined || p.locationId === ""
        ? null
        : (0, validators_1.assertString)(p.locationId, "locationId", { trim: true });
    const description = (_a = (0, validators_1.assertString)(p.description, "description", { trim: true, maxLength: 200 })) !== null && _a !== void 0 ? _a : null;
    const reasonRaw = (0, validators_1.assertString)(p.reason, "reason", { trim: true, maxLength: 32 });
    const reason = reasonRaw && reasonRaw.length > 0
        ? OVERRIDE_REASON_SET.has(reasonRaw)
            ? reasonRaw
            : null
        : null;
    return {
        locationId: locationId !== null && locationId !== void 0 ? locationId : null,
        fromAt,
        toAt,
        isAvailable: isAvailableRaw,
        description,
        reason,
    };
}
async function upsertPractitionerOverride(request) {
    var _a, _b, _c, _d, _e, _f, _g;
    if (!((_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid)) {
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    }
    const data = request.data;
    const clinicId = (0, validators_1.requireNonEmptyString)(data === null || data === void 0 ? void 0 : data.clinicId, "clinicId");
    const practitionerId = (0, validators_1.requireNonEmptyString)(data === null || data === void 0 ? void 0 : data.practitionerId, "practitionerId");
    const overrideIdRaw = data === null || data === void 0 ? void 0 : data.overrideId;
    const overrideId = overrideIdRaw === null || overrideIdRaw === undefined || overrideIdRaw === ""
        ? null
        : String(overrideIdRaw).trim();
    const isCreate = !overrideId || overrideId.length === 0;
    let validated;
    try {
        validated = validateOverridePatch(data === null || data === void 0 ? void 0 : data.patch);
    }
    catch (e) {
        if (e instanceof https_1.HttpsError)
            throw e;
        throw new https_1.HttpsError("invalid-argument", e instanceof Error ? e.message : "Invalid patch.");
    }
    const uid = request.auth.uid;
    await (0, permissions_1.requireClinicPermission)(db, clinicId, uid, "settings.write");
    const colRef = db
        .collection("clinics")
        .doc(clinicId)
        .collection("practitioners")
        .doc(practitionerId)
        .collection("overrides");
    const now = FV.serverTimestamp();
    if (isCreate) {
        const docId = colRef.doc().id;
        await colRef.doc(docId).set({
            locationId: (_b = validated.locationId) !== null && _b !== void 0 ? _b : null,
            fromAt: validated.fromAt,
            toAt: validated.toAt,
            isAvailable: validated.isAvailable,
            description: (_c = validated.description) !== null && _c !== void 0 ? _c : null,
            reason: (_d = validated.reason) !== null && _d !== void 0 ? _d : null,
            createdAt: now,
            updatedAt: now,
        });
        const entityPath = `clinics/${clinicId}/practitioners/${practitionerId}/overrides/${docId}`;
        await (0, audit_1.writeSettingsAuditEvent)(db, clinicId, "settings.override.created", uid, entityPath, docId, { fromAt: validated.fromAt.toMillis(), toAt: validated.toAt.toMillis(), isAvailable: validated.isAvailable });
        await (0, mirrorPractitionerAvailabilityToLegacy_1.mirrorPractitionerAvailabilityToLegacy)(clinicId, practitionerId);
        return { ok: true, overrideId: docId };
    }
    const ref = colRef.doc(overrideId);
    const snap = await ref.get();
    if (!snap.exists) {
        throw new https_1.HttpsError("not-found", "Override not found.");
    }
    await ref.update({
        locationId: (_e = validated.locationId) !== null && _e !== void 0 ? _e : null,
        fromAt: validated.fromAt,
        toAt: validated.toAt,
        isAvailable: validated.isAvailable,
        description: (_f = validated.description) !== null && _f !== void 0 ? _f : null,
        reason: (_g = validated.reason) !== null && _g !== void 0 ? _g : null,
        updatedAt: now,
    });
    const entityPath = `clinics/${clinicId}/practitioners/${practitionerId}/overrides/${overrideId}`;
    await (0, audit_1.writeSettingsAuditEvent)(db, clinicId, "settings.override.updated", uid, entityPath, overrideId, {
        fromAt: validated.fromAt.toMillis(),
        toAt: validated.toAt.toMillis(),
        isAvailable: validated.isAvailable,
    });
    await (0, mirrorPractitionerAvailabilityToLegacy_1.mirrorPractitionerAvailabilityToLegacy)(clinicId, practitionerId);
    return { ok: true, overrideId };
}
//# sourceMappingURL=upsertPractitionerOverride.js.map