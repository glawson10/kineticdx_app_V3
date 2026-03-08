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
exports.cancelAppointment = cancelAppointment;
// functions/src/clinic/cancelAppointment.ts
// Status-based cancel (no delete). Projection is updated by onAppointmentWrite_toBusyBlock trigger.
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const audit_1 = require("./audit/audit");
function getBoolPerm(perms, key) {
    return typeof perms === "object" && perms !== null && perms[key] === true;
}
function requirePerm(perms, keys, message) {
    const ok = keys.some((k) => getBoolPerm(perms, k));
    if (!ok)
        throw new https_1.HttpsError("permission-denied", message);
}
async function getMembershipData(db, clinicId, uid) {
    var _a, _b;
    const membersRef = db.doc(`clinics/${clinicId}/members/${uid}`);
    const membershipsRef = db.doc(`clinics/${clinicId}/memberships/${uid}`);
    const membersSnap = await membersRef.get();
    if (membersSnap.exists)
        return (_a = membersSnap.data()) !== null && _a !== void 0 ? _a : {};
    const legacySnap = await membershipsRef.get();
    if (legacySnap.exists)
        return (_b = legacySnap.data()) !== null && _b !== void 0 ? _b : {};
    return null;
}
function isActiveMember(data) {
    var _a;
    const status = ((_a = data.status) !== null && _a !== void 0 ? _a : "").toString().toLowerCase().trim();
    if (status === "invited" || status === "suspended")
        return false;
    if (!("active" in data))
        return true;
    return data.active === true;
}
async function cancelAppointment(req) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j;
    if (!req.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const clinicId = ((_b = (_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId) !== null && _b !== void 0 ? _b : "").toString().trim();
    const appointmentId = ((_d = (_c = req.data) === null || _c === void 0 ? void 0 : _c.appointmentId) !== null && _d !== void 0 ? _d : "").toString().trim();
    const reason = ((_f = (_e = req.data) === null || _e === void 0 ? void 0 : _e.reason) !== null && _f !== void 0 ? _f : "").toString().trim() || undefined;
    if (!clinicId || !appointmentId) {
        throw new https_1.HttpsError("invalid-argument", "clinicId and appointmentId are required.");
    }
    const db = admin.firestore();
    const uid = req.auth.uid;
    const memberData = await getMembershipData(db, clinicId, uid);
    if (!memberData || !isActiveMember(memberData)) {
        throw new https_1.HttpsError("permission-denied", "Not a clinic member.");
    }
    const perms = (_g = memberData.permissions) !== null && _g !== void 0 ? _g : {};
    requirePerm(perms, ["schedule.write", "schedule.manage"], "No scheduling permission.");
    const apptRef = db
        .collection("clinics")
        .doc(clinicId)
        .collection("appointments")
        .doc(appointmentId);
    const apptSnap = await apptRef.get();
    if (!apptSnap.exists)
        throw new https_1.HttpsError("not-found", "Appointment not found.");
    const appt = (_h = apptSnap.data()) !== null && _h !== void 0 ? _h : {};
    const currentStatus = ((_j = appt["status"]) !== null && _j !== void 0 ? _j : "booked").toString().toLowerCase();
    if (currentStatus === "cancelled") {
        return { success: true, alreadyCancelled: true };
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    await apptRef.update({
        status: "cancelled",
        cancelledAt: now,
        cancelledByUid: uid,
        ...(reason !== undefined && { cancelReason: reason }),
        updatedAt: now,
        updatedByUid: uid,
    });
    await (0, audit_1.writeAuditEvent)(db, clinicId, {
        type: "appointment.cancelled",
        actorUid: uid,
        appointmentId,
        metadata: { appointmentId, reason: reason !== null && reason !== void 0 ? reason : null },
    });
    return { success: true, alreadyCancelled: false };
}
//# sourceMappingURL=cancelAppointment.js.map