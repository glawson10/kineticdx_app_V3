"use strict";
/**
 * settings.updatePublicBookingConfig
 * Partial update of public booking configuration.
 * Write path: clinics/{clinicId}/settings/publicBooking
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
exports.updatePublicBookingConfig = updatePublicBookingConfig;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const permissions_1 = require("../permissions");
const audit_1 = require("../audit/audit");
const validators_1 = require("./validators");
const db = admin.firestore();
const FV = admin.firestore.FieldValue;
const ALLOWED_KEYS = new Set([
    "slotStepMinutes",
    "minNoticeMinutes",
    "maxAdvanceDays",
    "requirePhone",
    "requireEmail",
    "allowNewPatients",
    "cancellationPolicyHours",
    "weeklyHours",
    "confirmationMessage",
]);
const VALID_SLOT_STEPS = new Set([5, 10, 15, 20, 30, 60]);
function validatePatch(patch) {
    const raw = (0, validators_1.pickAllowedFields)(patch, ALLOWED_KEYS);
    if (Object.keys(raw).length === 0) {
        throw new https_1.HttpsError("invalid-argument", "No valid fields to update.");
    }
    const out = {};
    if (raw.slotStepMinutes !== undefined) {
        const v = (0, validators_1.assertIntRange)(raw.slotStepMinutes, "slotStepMinutes", { min: 5, max: 60 });
        if (v != null) {
            if (!VALID_SLOT_STEPS.has(v)) {
                throw new https_1.HttpsError("invalid-argument", "slotStepMinutes must be one of: 5, 10, 15, 20, 30, 60.");
            }
            out.slotStepMinutes = v;
        }
    }
    if (raw.minNoticeMinutes !== undefined) {
        const v = (0, validators_1.assertIntRange)(raw.minNoticeMinutes, "minNoticeMinutes", { min: 0, max: 43200 });
        if (v != null)
            out.minNoticeMinutes = v;
    }
    if (raw.maxAdvanceDays !== undefined) {
        const v = (0, validators_1.assertIntRange)(raw.maxAdvanceDays, "maxAdvanceDays", { min: 1, max: 365 });
        if (v != null)
            out.maxAdvanceDays = v;
    }
    if (raw.cancellationPolicyHours !== undefined) {
        const v = (0, validators_1.assertIntRange)(raw.cancellationPolicyHours, "cancellationPolicyHours", { min: 0, max: 168 });
        if (v != null)
            out.cancellationPolicyHours = v;
    }
    const booleanFields = ["requirePhone", "requireEmail", "allowNewPatients"];
    for (const field of booleanFields) {
        if (raw[field] !== undefined) {
            const v = (0, validators_1.assertBoolean)(raw[field], field);
            if (v !== null)
                out[field] = v;
        }
    }
    if (raw.confirmationMessage !== undefined) {
        const v = (0, validators_1.assertString)(raw.confirmationMessage, "confirmationMessage", { trim: true, maxLength: 2000 });
        out.confirmationMessage = v !== null && v !== void 0 ? v : null;
    }
    if (raw.weeklyHours !== undefined) {
        if (raw.weeklyHours !== null && typeof raw.weeklyHours === "object") {
            out.weeklyHours = raw.weeklyHours;
        }
        else if (raw.weeklyHours === null) {
            out.weeklyHours = null;
        }
    }
    return out;
}
async function updatePublicBookingConfig(request) {
    var _a;
    if (!((_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid)) {
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    }
    const data = request.data;
    const clinicId = (0, validators_1.requireNonEmptyString)(data === null || data === void 0 ? void 0 : data.clinicId, "clinicId");
    let patch;
    try {
        patch = validatePatch(data === null || data === void 0 ? void 0 : data.patch);
    }
    catch (e) {
        if (e instanceof https_1.HttpsError)
            throw e;
        throw new https_1.HttpsError("invalid-argument", e instanceof Error ? e.message : "Invalid patch.");
    }
    const uid = request.auth.uid;
    await (0, permissions_1.requireClinicPermission)(db, clinicId, uid, "settings.write");
    const ref = db.doc(`clinics/${clinicId}/settings/publicBooking`);
    const now = FV.serverTimestamp();
    const writeData = { ...patch, updatedAt: now, updatedByUid: uid };
    await ref.set(writeData, { merge: true });
    const changes = {};
    for (const key of Object.keys(patch)) {
        changes[key] = patch[key];
    }
    await (0, audit_1.writeSettingsAuditEvent)(db, clinicId, "settings.publicBooking.updated", uid, `clinics/${clinicId}/settings/publicBooking`, "publicBooking", changes);
    return { ok: true };
}
//# sourceMappingURL=updatePublicBookingConfig.js.map