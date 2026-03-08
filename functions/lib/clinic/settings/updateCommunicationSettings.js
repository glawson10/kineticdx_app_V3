"use strict";
/**
 * settings.updateCommunicationSettings
 * Partial update of clinic communication settings (reminders, reply-to, etc.).
 * Write path: clinics/{clinicId}/settings/communication
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
exports.updateCommunicationSettings = updateCommunicationSettings;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const permissions_1 = require("../permissions");
const audit_1 = require("../audit/audit");
const validators_1 = require("./validators");
const db = admin.firestore();
const FV = admin.firestore.FieldValue;
const ALLOWED_KEYS = new Set([
    "defaultReminderChannel",
    "defaultReplyToEmail",
    "reminderLeadHours",
    "followUpEnabled",
    "followUpDelayHours",
    "followUpMessage",
]);
const VALID_CHANNELS = new Set(["email", "sms", "both", "none"]);
const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
function validatePatch(patch) {
    const raw = (0, validators_1.pickAllowedFields)(patch, ALLOWED_KEYS);
    if (Object.keys(raw).length === 0) {
        throw new https_1.HttpsError("invalid-argument", "No valid fields to update.");
    }
    const out = {};
    if (raw.defaultReminderChannel !== undefined) {
        const v = (0, validators_1.assertString)(raw.defaultReminderChannel, "defaultReminderChannel", { trim: true });
        if (v != null) {
            if (!VALID_CHANNELS.has(v)) {
                throw new https_1.HttpsError("invalid-argument", "defaultReminderChannel must be one of: email, sms, both, none.");
            }
            out.defaultReminderChannel = v;
        }
    }
    if (raw.defaultReplyToEmail !== undefined) {
        const v = (0, validators_1.assertString)(raw.defaultReplyToEmail, "defaultReplyToEmail", { trim: true });
        if (v != null) {
            if (!EMAIL_REGEX.test(v)) {
                throw new https_1.HttpsError("invalid-argument", "defaultReplyToEmail must be a valid email address.");
            }
            out.defaultReplyToEmail = v;
        }
    }
    if (raw.reminderLeadHours !== undefined) {
        const n = typeof raw.reminderLeadHours === "number" ? raw.reminderLeadHours : parseInt(String(raw.reminderLeadHours), 10);
        if (!Number.isFinite(n) || n < 0 || n > 168) {
            throw new https_1.HttpsError("invalid-argument", "reminderLeadHours must be between 0 and 168.");
        }
        out.reminderLeadHours = n;
    }
    const booleanFields = ["followUpEnabled"];
    for (const field of booleanFields) {
        if (raw[field] !== undefined) {
            const v = (0, validators_1.assertBoolean)(raw[field], field);
            if (v !== null)
                out[field] = v;
        }
    }
    if (raw.followUpDelayHours !== undefined) {
        const n = typeof raw.followUpDelayHours === "number" ? raw.followUpDelayHours : parseInt(String(raw.followUpDelayHours), 10);
        if (!Number.isFinite(n) || n < 1 || n > 720) {
            throw new https_1.HttpsError("invalid-argument", "followUpDelayHours must be between 1 and 720.");
        }
        out.followUpDelayHours = n;
    }
    if (raw.followUpMessage !== undefined) {
        const v = (0, validators_1.assertString)(raw.followUpMessage, "followUpMessage", { trim: true, maxLength: 2000 });
        out.followUpMessage = v !== null && v !== void 0 ? v : null;
    }
    return out;
}
async function updateCommunicationSettings(request) {
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
    const ref = db.doc(`clinics/${clinicId}/settings/communication`);
    const now = FV.serverTimestamp();
    const writeData = { ...patch, updatedAt: now, updatedByUid: uid };
    await ref.set(writeData, { merge: true });
    const changes = {};
    for (const key of Object.keys(patch)) {
        changes[key] = patch[key];
    }
    await (0, audit_1.writeSettingsAuditEvent)(db, clinicId, "settings.communication.updated", uid, `clinics/${clinicId}/settings/communication`, "communication", changes);
    return { ok: true };
}
//# sourceMappingURL=updateCommunicationSettings.js.map