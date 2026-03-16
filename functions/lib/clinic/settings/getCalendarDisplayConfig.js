"use strict";
/**
 * settings.getCalendarDisplayConfig
 * Read-only. Returns normalized calendar display config from Firestore.
 * Read path: clinics/{clinicId}/settings/calendarDisplay
 * If doc is missing, returns default config (does not create the doc).
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
exports.getCalendarDisplayConfig = getCalendarDisplayConfig;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const permissions_1 = require("../permissions");
const validators_1 = require("./validators");
const db = admin.firestore();
/** Default config when doc is missing. Aligned with Dart CalendarDisplaySettings.defaults. */
function getDefaultCalendarDisplayConfig() {
    return {
        displayStartHour: 7,
        displayEndHour: 20,
        slotMinutes: 15,
        slotHeightPx: 48,
        timePickerIncrement: 5,
        showCurrentTimeIndicator: true,
        hidePatientNames: false,
        confirmMove: true,
        showFinancialIndicators: false,
        showWaitlistMatches: true,
        smartOneDayView: false,
        defaultView: "week",
        weekStartsOn: "monday",
        showWeekends: true,
        showClosedDayLabel: true,
        condensedHeader: false,
        clientNameSeparateLine: false,
    };
}
/** Normalize stored doc to canonical response: legacy field names and slotMinutes from minutesPerBlock. */
function normalizeCalendarDisplayConfig(raw) {
    var _a, _b;
    const d = raw !== null && raw !== void 0 ? raw : {};
    const slotMinutes = (_b = (_a = (typeof d.slotMinutes === "number" && Number.isInteger(d.slotMinutes) ? d.slotMinutes : null)) !== null && _a !== void 0 ? _a : (typeof d.minutesPerBlock === "number" && Number.isInteger(d.minutesPerBlock) ? d.minutesPerBlock : null)) !== null && _b !== void 0 ? _b : 15;
    const confirmMove = typeof d.confirmMove === "boolean"
        ? d.confirmMove
        : typeof d.confirmAppointmentMoves === "boolean"
            ? d.confirmAppointmentMoves
            : true;
    return {
        displayStartHour: typeof d.displayStartHour === "number" && Number.isInteger(d.displayStartHour) ? d.displayStartHour : 7,
        displayEndHour: typeof d.displayEndHour === "number" && Number.isInteger(d.displayEndHour) ? d.displayEndHour : 20,
        slotMinutes,
        slotHeightPx: typeof d.slotHeightPx === "number" ? d.slotHeightPx : 48,
        timePickerIncrement: typeof d.timePickerIncrement === "number" && Number.isInteger(d.timePickerIncrement) ? d.timePickerIncrement : 5,
        showCurrentTimeIndicator: typeof d.showCurrentTimeIndicator === "boolean" ? d.showCurrentTimeIndicator : true,
        hidePatientNames: typeof d.hidePatientNames === "boolean" ? d.hidePatientNames : false,
        confirmMove,
        showFinancialIndicators: typeof d.showFinancialIndicators === "boolean" ? d.showFinancialIndicators : false,
        showWaitlistMatches: typeof d.showWaitlistMatches === "boolean" ? d.showWaitlistMatches : true,
        smartOneDayView: typeof d.smartOneDayView === "boolean" ? d.smartOneDayView : false,
        defaultView: typeof d.defaultView === "string" && d.defaultView.trim() ? d.defaultView.trim() : "week",
        weekStartsOn: typeof d.weekStartsOn === "string" && d.weekStartsOn.trim() ? d.weekStartsOn.trim() : "monday",
        showWeekends: typeof d.showWeekends === "boolean" ? d.showWeekends : true,
        showClosedDayLabel: typeof d.showClosedDayLabel === "boolean" ? d.showClosedDayLabel : true,
        condensedHeader: typeof d.condensedHeader === "boolean" ? d.condensedHeader : false,
        clientNameSeparateLine: typeof d.clientNameSeparateLine === "boolean" ? d.clientNameSeparateLine : false,
    };
}
async function getCalendarDisplayConfig(request) {
    var _a;
    if (!((_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid)) {
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    }
    const data = request.data;
    const clinicId = (0, validators_1.requireNonEmptyString)(data === null || data === void 0 ? void 0 : data.clinicId, "clinicId");
    const uid = request.auth.uid;
    // Require settings.read or settings.write (active membership implied by requireClinicPermission)
    try {
        await (0, permissions_1.requireClinicPermission)(db, clinicId, uid, "settings.read");
    }
    catch (e) {
        if (e instanceof https_1.HttpsError && e.code === "permission-denied") {
            await (0, permissions_1.requireClinicPermission)(db, clinicId, uid, "settings.write");
        }
        else {
            throw e;
        }
    }
    const ref = db.doc(`clinics/${clinicId}/settings/calendarDisplay`);
    const snap = await ref.get();
    if (!snap.exists) {
        return getDefaultCalendarDisplayConfig();
    }
    const stored = snap.data();
    return normalizeCalendarDisplayConfig(stored);
}
//# sourceMappingURL=getCalendarDisplayConfig.js.map