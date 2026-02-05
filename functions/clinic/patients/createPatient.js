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
exports.createPatient = createPatient;
// functions/src/clinic/patients/createPatient.ts
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
}
function normalizeEmail(v) {
    const s = safeStr(v).toLowerCase();
    return s;
}
function readBoolOrUndefined(v) {
    if (v === true)
        return true;
    if (v === false)
        return false;
    return undefined;
}
function isMemberActiveLike(data) {
    const status = safeStr(data.status);
    if (status === "suspended")
        return false;
    if (status === "invited")
        return false;
    const active = readBoolOrUndefined(data.active);
    if (active !== undefined)
        return active;
    return true;
}
function getPermissionsMap(data) {
    const p = data.permissions;
    if (p && typeof p === "object")
        return p;
    return {};
}
async function getMembershipDataWithFallback(db, clinicId, uid) {
    const canonRef = db.collection("clinics").doc(clinicId).collection("memberships").doc(uid);
    const canonSnap = await canonRef.get();
    if (canonSnap.exists)
        return (canonSnap.data() || {});
    const legacyRef = db.collection("clinics").doc(clinicId).collection("members").doc(uid);
    const legacySnap = await legacyRef.get();
    if (legacySnap.exists)
        return (legacySnap.data() || {});
    return null;
}
async function assertPatientWritePerm(db, clinicId, uid) {
    var _a;
    const data = await getMembershipDataWithFallback(db, clinicId, uid);
    if (!data)
        throw new https_1.HttpsError("permission-denied", "Not a clinic member.");
    if (!isMemberActiveLike(data)) {
        throw new https_1.HttpsError("permission-denied", "Membership not active.");
    }
    const perms = getPermissionsMap(data);
    if (perms["patients.write"] !== true) {
        // Owner/manager shortcut (optional):
        const roleId = safeStr((_a = data.roleId) !== null && _a !== void 0 ? _a : data.role).toLowerCase();
        if (roleId !== "owner" && roleId !== "manager") {
            throw new https_1.HttpsError("permission-denied", "No patient write permission.");
        }
    }
}
function pickDobString(data) {
    const s = safeStr(data.dob) || safeStr(data.dateOfBirth) || safeStr(data.dateOfBirthIso);
    return s;
}
function parseDobToDayTimestamp(dob) {
    const raw = safeStr(dob);
    if (!raw)
        throw new https_1.HttpsError("invalid-argument", "dob is required.");
    const d = new Date(raw);
    if (Number.isNaN(d.getTime()))
        throw new https_1.HttpsError("invalid-argument", "Invalid dob.");
    const day = new Date(d.getFullYear(), d.getMonth(), d.getDate());
    return admin.firestore.Timestamp.fromDate(day);
}
async function createPatient(req) {
    var _a;
    if (!req.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const data = ((_a = req.data) !== null && _a !== void 0 ? _a : {});
    const clinicId = safeStr(data.clinicId);
    const firstName = safeStr(data.firstName);
    const lastName = safeStr(data.lastName);
    const dobRaw = pickDobString(data);
    // phone/email optional (public booking might provide them, internal might not yet)
    const phone = safeStr(data.phone);
    const email = normalizeEmail(data.email);
    const address = safeStr(data.address);
    if (!clinicId || !firstName || !lastName) {
        throw new https_1.HttpsError("invalid-argument", "clinicId, firstName, lastName are required.");
    }
    const uid = req.auth.uid;
    const db = admin.firestore();
    await assertPatientWritePerm(db, clinicId, uid);
    const dobTs = dobRaw ? parseDobToDayTimestamp(dobRaw) : null;
    const ref = db.collection("clinics").doc(clinicId).collection("patients").doc();
    const now = admin.firestore.FieldValue.serverTimestamp();
    await ref.set({
        clinicId,
        // legacy/simple fields
        firstName,
        lastName,
        dob: dobTs,
        phone: phone || null,
        email: email || null,
        address: address || "",
        // canonical blocks
        identity: {
            firstName,
            lastName,
            preferredName: null,
            dateOfBirth: dobTs,
        },
        contact: {
            phone: phone || null,
            email: email || null,
            preferredMethod: null,
            address: address ? { line1: address } : null,
        },
        emergencyContact: null,
        tags: [],
        alerts: [],
        adminNotes: null,
        status: {
            active: true,
            archived: false,
            archivedAt: null,
        },
        createdByUid: uid,
        createdAt: now,
        updatedByUid: uid,
        updatedAt: now,
        schemaVersion: 1,
    });
    return { ok: true, patientId: ref.id };
}
//# sourceMappingURL=createPatient.js.map