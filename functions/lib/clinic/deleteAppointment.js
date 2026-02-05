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
exports.deleteAppointment = deleteAppointment;
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
async function deleteAppointment(req) {
    var _a, _b, _c, _d, _e, _f, _g;
    if (!req.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const clinicId = ((_b = (_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId) !== null && _b !== void 0 ? _b : "").toString().trim();
    const appointmentId = ((_d = (_c = req.data) === null || _c === void 0 ? void 0 : _c.appointmentId) !== null && _d !== void 0 ? _d : "").toString().trim();
    if (!clinicId || !appointmentId) {
        throw new https_1.HttpsError("invalid-argument", "clinicId, appointmentId are required.");
    }
    const db = admin.firestore();
    const uid = req.auth.uid;
    const memberRef = db.collection("clinics").doc(clinicId).collection("members").doc(uid);
    const memberSnap = await memberRef.get();
    if (!memberSnap.exists || ((_e = memberSnap.data()) === null || _e === void 0 ? void 0 : _e.active) !== true) {
        throw new https_1.HttpsError("permission-denied", "Not a clinic member.");
    }
    const perms = (_g = (_f = memberSnap.data()) === null || _f === void 0 ? void 0 : _f.permissions) !== null && _g !== void 0 ? _g : {};
    requirePerm(perms, ["schedule.write", "schedule.manage"], "No scheduling permission.");
    const apptRef = db.collection("clinics").doc(clinicId).collection("appointments").doc(appointmentId);
    const apptSnap = await apptRef.get();
    if (!apptSnap.exists)
        throw new https_1.HttpsError("not-found", "Appointment not found.");
    await apptRef.delete();
    return { success: true };
}
//# sourceMappingURL=deleteAppointment.js.map