"use strict";
/**
 * settings.updateCalendarDisplayConfig
 * Partial update of calendar display settings.
 * Write path: clinics/{clinicId}/settings/calendarDisplay
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
exports.updateCalendarDisplayConfig = updateCalendarDisplayConfig;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const permissions_1 = require("../permissions");
const audit_1 = require("../audit/audit");
const validators_1 = require("./validators");
const db = admin.firestore();
const FV = admin.firestore.FieldValue;
const ALLOWED_KEYS = new Set([
    "displayStartHour",
    "displayEndHour",
    "minutesPerBlock",
    "slotHeightPx",
    "timePickerIncrement",
    "showCurrentTimeIndicator",
    "hidePatientNames",
    "confirmMove",
    "showFinancialIndicators",
    "showWaitlistMatches",
    "smartOneDayView",
    "defaultView",
    "weekStartsOn",
    "showWeekends",
    "showClosedDayLabel",
    "condensedHeader",
    "clientNameSeparateLine",
]);
const VALID_DEFAULT_VIEWS = new Set(["day", "week", "month"]);
const VALID_WEEK_STARTS = new Set(["monday", "sunday"]);
const VALID_MINUTES_PER_BLOCK = new Set([5, 10, 15, 20, 30, 60]);
function validatePatch(patch) {
    var _a, _b;
    const raw = (0, validators_1.pickAllowedFields)(patch, ALLOWED_KEYS);
    if (Object.keys(raw).length === 0) {
        throw new https_1.HttpsError("invalid-argument", "No valid fields to update.");
    }
    const out = {};
    if (raw.displayStartHour !== undefined) {
        const v = (0, validators_1.assertIntRange)(raw.displayStartHour, "displayStartHour", { min: 0, max: 23 });
        if (v != null)
            out.displayStartHour = v;
    }
    if (raw.displayEndHour !== undefined) {
        const v = (0, validators_1.assertIntRange)(raw.displayEndHour, "displayEndHour", { min: 1, max: 24 });
        if (v != null)
            out.displayEndHour = v;
    }
    const startHour = ((_a = out.displayStartHour) !== null && _a !== void 0 ? _a : raw.displayStartHour);
    const endHour = ((_b = out.displayEndHour) !== null && _b !== void 0 ? _b : raw.displayEndHour);
    if (startHour !== undefined && endHour !== undefined && endHour <= startHour) {
        throw new https_1.HttpsError("invalid-argument", "displayEndHour must be greater than displayStartHour.");
    }
    if (raw.minutesPerBlock !== undefined) {
        const v = (0, validators_1.assertIntRange)(raw.minutesPerBlock, "minutesPerBlock", { min: 5, max: 60 });
        if (v != null) {
            if (!VALID_MINUTES_PER_BLOCK.has(v)) {
                throw new https_1.HttpsError("invalid-argument", "minutesPerBlock must be one of: 5, 10, 15, 20, 30, 60.");
            }
            out.minutesPerBlock = v;
        }
    }
    if (raw.slotHeightPx !== undefined) {
        const v = (0, validators_1.assertIntRange)(raw.slotHeightPx, "slotHeightPx", { min: 20, max: 120 });
        if (v != null)
            out.slotHeightPx = v;
    }
    if (raw.timePickerIncrement !== undefined) {
        const v = (0, validators_1.assertIntRange)(raw.timePickerIncrement, "timePickerIncrement", { min: 1, max: 60 });
        if (v != null)
            out.timePickerIncrement = v;
    }
    const booleanFields = [
        "showCurrentTimeIndicator",
        "hidePatientNames",
        "confirmMove",
        "showFinancialIndicators",
        "showWaitlistMatches",
        "smartOneDayView",
        "showWeekends",
        "showClosedDayLabel",
        "condensedHeader",
        "clientNameSeparateLine",
    ];
    for (const field of booleanFields) {
        if (raw[field] !== undefined) {
            const v = (0, validators_1.assertBoolean)(raw[field], field);
            if (v !== null)
                out[field] = v;
        }
    }
    if (raw.defaultView !== undefined) {
        const v = (0, validators_1.assertString)(raw.defaultView, "defaultView", { trim: true });
        if (v != null) {
            if (!VALID_DEFAULT_VIEWS.has(v)) {
                throw new https_1.HttpsError("invalid-argument", "defaultView must be one of: day, week, month.");
            }
            out.defaultView = v;
        }
    }
    if (raw.weekStartsOn !== undefined) {
        const v = (0, validators_1.assertString)(raw.weekStartsOn, "weekStartsOn", { trim: true });
        if (v != null) {
            if (!VALID_WEEK_STARTS.has(v)) {
                throw new https_1.HttpsError("invalid-argument", "weekStartsOn must be one of: monday, sunday.");
            }
            out.weekStartsOn = v;
        }
    }
    return out;
}
async function updateCalendarDisplayConfig(request) {
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
    const ref = db.doc(`clinics/${clinicId}/settings/calendarDisplay`);
    const now = FV.serverTimestamp();
    const writeData = { ...patch, updatedAt: now };
    await ref.set(writeData, { merge: true });
    const changes = {};
    for (const key of Object.keys(patch)) {
        changes[key] = patch[key];
    }
    await (0, audit_1.writeSettingsAuditEvent)(db, clinicId, "settings.calendarDisplay.updated", uid, `clinics/${clinicId}/settings/calendarDisplay`, "calendarDisplay", changes);
    return { ok: true };
}
//# sourceMappingURL=updateCalendarDisplayConfig.js.map