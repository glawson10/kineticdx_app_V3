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
exports.onAppointmentWrite_toBusyBlock = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const admin = __importStar(require("firebase-admin"));
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
function safeStr(v) {
    return typeof v === "string" ? v.trim() : "";
}
function toTimestamp(v) {
    var _a;
    if (!v)
        return null;
    // Firestore Timestamp already
    if (v instanceof admin.firestore.Timestamp)
        return v;
    // Serialized Timestamp-like
    if (typeof v === "object" && typeof v._seconds === "number") {
        const secs = Number(v._seconds);
        const nanos = Number((_a = v._nanoseconds) !== null && _a !== void 0 ? _a : 0);
        return new admin.firestore.Timestamp(secs, nanos);
    }
    // millis number
    if (typeof v === "number" && Number.isFinite(v)) {
        return admin.firestore.Timestamp.fromMillis(v);
    }
    // ISO string
    if (typeof v === "string") {
        const t = Date.parse(v);
        if (Number.isFinite(t))
            return admin.firestore.Timestamp.fromMillis(t);
    }
    return null;
}
exports.onAppointmentWrite_toBusyBlock = (0, firestore_1.onDocumentWritten)({
    region: "europe-west3",
    document: "clinics/{clinicId}/appointments/{appointmentId}",
}, async (event) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m;
    const { clinicId, appointmentId } = event.params;
    const after = (_a = event.data) === null || _a === void 0 ? void 0 : _a.after;
    const afterExists = (_b = after === null || after === void 0 ? void 0 : after.exists) !== null && _b !== void 0 ? _b : false;
    const blockRef = db.doc(`clinics/${clinicId}/public/availability/blocks/${appointmentId}`);
    // Deleted => remove block
    if (!afterExists) {
        await blockRef.delete().catch(() => { });
        return;
    }
    const a = after.data() || {};
    // Support multiple possible appointment field names (migration-safe)
    const startRaw = (_g = (_f = (_e = (_d = (_c = a.startAt) !== null && _c !== void 0 ? _c : a.startUtc) !== null && _d !== void 0 ? _d : a.start) !== null && _e !== void 0 ? _e : a.startsAt) !== null && _f !== void 0 ? _f : a.startTime) !== null && _g !== void 0 ? _g : a.startMs;
    const endRaw = (_m = (_l = (_k = (_j = (_h = a.endAt) !== null && _h !== void 0 ? _h : a.endUtc) !== null && _j !== void 0 ? _j : a.end) !== null && _k !== void 0 ? _k : a.endsAt) !== null && _l !== void 0 ? _l : a.endTime) !== null && _m !== void 0 ? _m : a.endMs;
    const startTs = toTimestamp(startRaw);
    const endTs = toTimestamp(endRaw);
    if (!startTs || !endTs) {
        console.warn("Appointment missing start/end; cannot build busy block", {
            clinicId,
            appointmentId,
            keys: Object.keys(a),
        });
        // Don’t leave a stale/invalid block around
        await blockRef.delete().catch(() => { });
        return;
    }
    const status = safeStr(a.status) || "booked";
    if (status === "cancelled") {
        await blockRef.delete().catch(() => { });
        return;
    }
    const kind = safeStr(a.kind);
    const practitionerId = safeStr(a.practitionerId) || safeStr(a.clinicianId);
    // ✅ Scope rules:
    // - admin without practitioner => clinic-wide block
    // - admin with practitioner    => practitioner block
    // - everything else            => practitioner block
    const scope = kind === "admin"
        ? practitionerId
            ? "practitioner"
            : "clinic"
        : "practitioner";
    await blockRef.set({
        clinicId,
        appointmentId,
        startUtc: startTs, // Timestamp
        endUtc: endTs, // Timestamp
        scope,
        // standardize on practitionerId
        practitionerId: practitionerId || null,
        // legacy mirror for older readers
        clinicianId: practitionerId || null,
        status,
        kind: kind || null,
        source: "appointments_mirror",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
});
//# sourceMappingURL=onAppointmentWrite_toBusyBlock.js.map