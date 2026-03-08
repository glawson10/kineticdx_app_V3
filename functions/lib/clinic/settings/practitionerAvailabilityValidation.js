"use strict";
/**
 * Validation helpers for practitioner availability and overrides (Commit 31).
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
exports.MAX_INTERVAL = exports.MAX_BLOCKS = void 0;
exports.assertIsoDate = assertIsoDate;
exports.assertTimeHHmm = assertTimeHHmm;
exports.assertNoOverlaps = assertNoOverlaps;
exports.parseTimestampInput = parseTimestampInput;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
exports.MAX_BLOCKS = 20;
exports.MAX_INTERVAL = 365;
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;
const TIME_HHMM = /^([01]?\d|2[0-3]):([0-5]\d)$/;
/**
 * Assert ISO date string (YYYY-MM-DD).
 */
function assertIsoDate(val, field) {
    if (val === null || val === undefined || (typeof val === "string" && val.trim() === "")) {
        throw new https_1.HttpsError("invalid-argument", `Missing required field: ${field}`);
    }
    const s = typeof val === "string" ? val.trim() : String(val);
    if (!ISO_DATE.test(s)) {
        throw new https_1.HttpsError("invalid-argument", `${field} must be ISO date (YYYY-MM-DD).`);
    }
    return s;
}
/**
 * Assert time string HH:mm (24h).
 */
function assertTimeHHmm(val, field) {
    if (val === null || val === undefined) {
        throw new https_1.HttpsError("invalid-argument", `Missing required field: ${field}`);
    }
    const s = typeof val === "string" ? val.trim() : String(val);
    if (!TIME_HHMM.test(s)) {
        throw new https_1.HttpsError("invalid-argument", `${field} must be time HH:mm (24h).`);
    }
    return s;
}
/**
 * Ensure no overlapping blocks on the same day.
 */
function assertNoOverlaps(blocks) {
    var _a;
    const byDay = new Map();
    for (const b of blocks) {
        const list = (_a = byDay.get(b.dayOfWeek)) !== null && _a !== void 0 ? _a : [];
        list.push(b);
        byDay.set(b.dayOfWeek, list);
    }
    for (const [, list] of byDay) {
        list.sort((a, b) => a.startTime.localeCompare(b.startTime));
        for (let i = 1; i < list.length; i++) {
            if (list[i].startTime < list[i - 1].endTime) {
                throw new https_1.HttpsError("invalid-argument", `Overlapping blocks on day ${list[i].dayOfWeek}: ${list[i - 1].startTime}-${list[i - 1].endTime} and ${list[i].startTime}-${list[i].endTime}`);
            }
        }
    }
}
/**
 * Parse timestamp from client (seconds or milliseconds or Firestore Timestamp-like).
 */
function parseTimestampInput(val, field) {
    if (val === null || val === undefined) {
        throw new https_1.HttpsError("invalid-argument", `Missing required field: ${field}`);
    }
    if (val && typeof val.toMillis === "function") {
        return val;
    }
    const n = typeof val === "number" ? val : parseInt(String(val), 10);
    if (!Number.isFinite(n)) {
        throw new https_1.HttpsError("invalid-argument", `${field} must be a valid timestamp.`);
    }
    const ms = n > 1e12 ? n : n * 1000;
    return admin.firestore.Timestamp.fromMillis(ms);
}
//# sourceMappingURL=practitionerAvailabilityValidation.js.map