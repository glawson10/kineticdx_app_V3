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
exports.createBookingRequestFn = void 0;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const logger_1 = require("firebase-functions/logger");
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
}
function lowerEmail(v) {
    return safeStr(v).toLowerCase();
}
function toTsFromMs(ms) {
    if (!Number.isFinite(ms) || ms <= 0)
        throw new Error("Invalid ms timestamp");
    return admin.firestore.Timestamp.fromMillis(ms);
}
function normalizePhone(v) {
    const s = safeStr(v);
    if (!s)
        return "";
    const cleaned = s.replace(/[^\d+]/g, "");
    if (cleaned.startsWith("+"))
        return "+" + cleaned.slice(1).replace(/\+/g, "");
    return cleaned.replace(/\+/g, "");
}
function requireAuthed(context) {
    var _a;
    // Option 1 typically means: require auth (anonymous auth is fine too)
    if (!((_a = context.auth) === null || _a === void 0 ? void 0 : _a.uid)) {
        throw new https_1.HttpsError("unauthenticated", "You must be signed in to book.");
    }
    return context.auth.uid;
}
exports.createBookingRequestFn = (0, https_1.onCall)({ region: "europe-west3" }, async (req) => {
    var _a, _b, _c;
    const uid = requireAuthed(req);
    const input = ((_a = req.data) !== null && _a !== void 0 ? _a : {});
    const clinicId = safeStr(input.clinicId);
    if (!clinicId)
        throw new https_1.HttpsError("invalid-argument", "Missing clinicId.");
    const practitionerId = safeStr(input.practitionerId) || safeStr(input.clinicianId);
    if (!practitionerId) {
        throw new https_1.HttpsError("invalid-argument", "Missing practitionerId/clinicianId.");
    }
    // times
    let startUtc;
    let endUtc;
    try {
        startUtc = toTsFromMs(Number(input.startUtcMs));
        endUtc = toTsFromMs(Number(input.endUtcMs));
    }
    catch {
        throw new https_1.HttpsError("invalid-argument", "Invalid start/end times.");
    }
    const startDt = startUtc.toDate();
    const endDt = endUtc.toDate();
    if (!(endDt.getTime() > startDt.getTime())) {
        throw new https_1.HttpsError("invalid-argument", "End time must be after start time.");
    }
    // patient
    const p = (_b = input.patient) !== null && _b !== void 0 ? _b : {};
    const firstName = safeStr(p.firstName);
    const lastName = safeStr(p.lastName);
    let dob;
    try {
        dob = toTsFromMs(Number(p.dobMs));
    }
    catch {
        throw new https_1.HttpsError("invalid-argument", "Missing/invalid patient DOB.");
    }
    if (!firstName || !lastName) {
        throw new https_1.HttpsError("invalid-argument", "Missing patient first/last name.");
    }
    // appointment
    const a = (_c = input.appointment) !== null && _c !== void 0 ? _c : {};
    const minutes = Number(a.minutes);
    if (!Number.isFinite(minutes) || minutes <= 0 || minutes > 240) {
        throw new https_1.HttpsError("invalid-argument", "Invalid appointment minutes.");
    }
    const tz = safeStr(input.tz) || "Europe/Prague";
    const kind = safeStr(input.kind) || "new";
    const email = lowerEmail(p.email);
    const phoneRaw = safeStr(p.phone);
    const phoneNorm = normalizePhone(phoneRaw);
    const requestDoc = {
        clinicId,
        practitionerId, // canonical field going forward
        clinicianId: safeStr(input.clinicianId) || null, // optional legacy
        startUtc,
        endUtc,
        tz,
        kind,
        patient: {
            firstName,
            lastName,
            dob,
            email: email || "",
            phone: phoneRaw || "",
            phoneNorm: phoneNorm || "",
            address: safeStr(p.address) || "",
            consentToTreatment: p.consentToTreatment === true,
        },
        appointment: {
            minutes,
            label: safeStr(a.label) || "",
            priceText: safeStr(a.priceText) || "",
            description: safeStr(a.description) || "",
        },
        requesterUid: uid,
        status: "pending",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        source: "publicBookingCallable",
    };
    const ref = db.collection(`clinics/${clinicId}/bookingRequests`).doc();
    await ref.set(requestDoc);
    logger_1.logger.info("BookingRequest created via callable", {
        clinicId,
        requestId: ref.id,
        uid,
        practitionerId,
        startUtcMs: startDt.getTime(),
    });
    return {
        bookingRequestId: ref.id,
        path: ref.path,
        status: "pending",
    };
});
//# sourceMappingURL=createBookingRequestFn.js.map