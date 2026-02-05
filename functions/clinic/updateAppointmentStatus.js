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
exports.updateAppointmentStatus = updateAppointmentStatus;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
function getBoolPerm(perms, key) {
    return typeof perms === "object" && perms !== null && perms[key] === true;
}
function requirePerm(perms, keys, message) {
    const ok = keys.some((k) => getBoolPerm(perms, k));
    if (!ok)
        throw new https_1.HttpsError("permission-denied", message);
}
function normalizeStatus(s) {
    const v = (s !== null && s !== void 0 ? s : "").toLowerCase().trim();
    const allowed = new Set(["booked", "attended", "cancelled", "missed"]);
    if (!allowed.has(v)) {
        throw new https_1.HttpsError("invalid-argument", "Invalid status. Use booked | attended | cancelled | missed.");
    }
    return v;
}
async function getMembershipData(db, clinicId, uid) {
    var _a, _b;
    const canonical = db.collection("clinics").doc(clinicId).collection("memberships").doc(uid);
    const legacy = db.collection("clinics").doc(clinicId).collection("members").doc(uid);
    const c = await canonical.get();
    if (c.exists)
        return (_a = c.data()) !== null && _a !== void 0 ? _a : {};
    const l = await legacy.get();
    if (l.exists)
        return (_b = l.data()) !== null && _b !== void 0 ? _b : {};
    return null;
}
function isActiveMember(data) {
    var _a;
    const status = ((_a = data.status) !== null && _a !== void 0 ? _a : "").toString().toLowerCase().trim();
    if (status === "suspended" || status === "invited")
        return false;
    if (!("active" in data))
        return true; // back-compat
    return data.active === true;
}
async function updateAppointmentStatus(req) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l;
    if (!req.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const clinicId = ((_b = (_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId) !== null && _b !== void 0 ? _b : "").toString().trim();
    const appointmentId = ((_d = (_c = req.data) === null || _c === void 0 ? void 0 : _c.appointmentId) !== null && _d !== void 0 ? _d : "").toString().trim();
    const status = normalizeStatus(((_f = (_e = req.data) === null || _e === void 0 ? void 0 : _e.status) !== null && _f !== void 0 ? _f : "").toString());
    if (!clinicId || !appointmentId) {
        throw new https_1.HttpsError("invalid-argument", "clinicId and appointmentId are required.");
    }
    const db = admin.firestore();
    const uid = req.auth.uid;
    // ─────────────────────────────
    // Membership + permission check (canonical)
    // ─────────────────────────────
    const member = await getMembershipData(db, clinicId, uid);
    if (!member || !isActiveMember(member)) {
        throw new https_1.HttpsError("permission-denied", "Not an active clinic member.");
    }
    const perms = (_g = member.permissions) !== null && _g !== void 0 ? _g : {};
    requirePerm(perms, ["schedule.write", "schedule.manage"], "No scheduling permission.");
    // ─────────────────────────────
    // Load appointment
    // ─────────────────────────────
    const apptRef = db
        .collection("clinics")
        .doc(clinicId)
        .collection("appointments")
        .doc(appointmentId);
    const apptSnap = await apptRef.get();
    if (!apptSnap.exists)
        throw new https_1.HttpsError("not-found", "Appointment not found.");
    const appt = (_h = apptSnap.data()) !== null && _h !== void 0 ? _h : {};
    // Prevent status changes on admin blocks
    const kind = ((_j = appt["kind"]) !== null && _j !== void 0 ? _j : "").toString().toLowerCase();
    if (kind === "admin" || !((_k = appt["patientId"]) !== null && _k !== void 0 ? _k : "").toString()) {
        throw new https_1.HttpsError("failed-precondition", "Admin blocks cannot have attendance status.");
    }
    const currentStatus = ((_l = appt["status"]) !== null && _l !== void 0 ? _l : "booked").toString().toLowerCase();
    if (currentStatus === status) {
        return { success: true, unchanged: true };
    }
    // ─────────────────────────────
    // Build patch
    // ─────────────────────────────
    const now = admin.firestore.FieldValue.serverTimestamp();
    const patch = {
        status,
        updatedAt: now,
        updatedByUid: uid,
    };
    // Clear all status timestamps first
    patch.attendedAt = null;
    patch.cancelledAt = null;
    patch.missedAt = null;
    if (status === "attended")
        patch.attendedAt = now;
    if (status === "cancelled")
        patch.cancelledAt = now;
    if (status === "missed")
        patch.missedAt = now;
    await apptRef.update(patch);
    return { success: true };
}
//# sourceMappingURL=updateAppointmentStatus.js.map