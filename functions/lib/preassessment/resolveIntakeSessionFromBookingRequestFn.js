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
exports.resolveIntakeSessionFromBookingRequestFn = void 0;
// functions/src/preassessment/resolveIntakeSessionFromBookingRequestFn.ts
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const logger_1 = require("firebase-functions/logger");
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
}
/**
 * ✅ For in-app public booking flow (NO token available):
 * Input: clinicId + bookingRequestId
 * Output: intakeSessionId (must already exist from onBookingRequestCreateV2)
 */
exports.resolveIntakeSessionFromBookingRequestFn = (0, https_1.onCall)({ region: "europe-west3", cors: true }, async (req) => {
    var _a, _b, _c;
    const clinicId = safeStr((_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId);
    const bookingRequestId = safeStr((_b = req.data) === null || _b === void 0 ? void 0 : _b.bookingRequestId);
    if (!clinicId || !bookingRequestId) {
        throw new https_1.HttpsError("invalid-argument", "Missing clinicId or bookingRequestId.", {
            clinicId,
            bookingRequestId,
        });
    }
    const brRef = db.doc(`clinics/${clinicId}/bookingRequests/${bookingRequestId}`);
    const brSnap = await brRef.get();
    if (!brSnap.exists) {
        throw new https_1.HttpsError("not-found", "bookingRequest not found.", {
            clinicId,
            bookingRequestId,
        });
    }
    const br = (_c = brSnap.data()) !== null && _c !== void 0 ? _c : {};
    const intakeSessionId = safeStr(br.intakeSessionId);
    if (!intakeSessionId) {
        // This means your trigger didn’t create it (or booking not approved yet / failed).
        throw new https_1.HttpsError("failed-precondition", "No intakeSessionId on this booking request (preassessment not created yet).", { clinicId, bookingRequestId });
    }
    // Optional sanity check: ensure intake session exists
    const isRef = db.doc(`clinics/${clinicId}/intakeSessions/${intakeSessionId}`);
    const isSnap = await isRef.get();
    if (!isSnap.exists) {
        throw new https_1.HttpsError("failed-precondition", "intakeSessionId referenced but session doc missing.", {
            clinicId,
            bookingRequestId,
            intakeSessionId,
        });
    }
    logger_1.logger.info("resolveIntakeSessionFromBookingRequestFn ok", {
        clinicId,
        bookingRequestId,
        intakeSessionId,
    });
    return { ok: true, intakeSessionId };
});
//# sourceMappingURL=resolveIntakeSessionFromBookingRequestFn.js.map