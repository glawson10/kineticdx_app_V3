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
exports.onClinicCreatedProvisionOwnerMembership = void 0;
// functions/src/clinic/onClinicCreatedProvisionOwner.ts
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/v2/firestore");
const logger_1 = require("firebase-functions/logger");
const roleTemplates_1 = require("./roleTemplates");
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
}
function pickOwnerDisplayName(clinic) {
    var _a;
    const fromClinic = safeStr(clinic === null || clinic === void 0 ? void 0 : clinic.createdByName) ||
        safeStr(clinic === null || clinic === void 0 ? void 0 : clinic.createdByDisplayName) ||
        safeStr((_a = clinic === null || clinic === void 0 ? void 0 : clinic.profile) === null || _a === void 0 ? void 0 : _a.ownerName);
    if (fromClinic)
        return fromClinic;
    const email = safeStr(clinic === null || clinic === void 0 ? void 0 : clinic.createdByEmail);
    if (email && email.includes("@"))
        return email.split("@")[0];
    return "Owner";
}
exports.onClinicCreatedProvisionOwnerMembership = (0, firestore_1.onDocumentCreated)({
    region: "europe-west3",
    document: "clinics/{clinicId}",
}, async (event) => {
    var _a, _b;
    const clinicId = safeStr(event.params.clinicId);
    if (!clinicId)
        return;
    const clinicSnap = await db.doc(`clinics/${clinicId}`).get();
    const clinic = ((_a = clinicSnap.data()) !== null && _a !== void 0 ? _a : {});
    const ownerUid = safeStr(clinic === null || clinic === void 0 ? void 0 : clinic.ownerUid) || safeStr(clinic === null || clinic === void 0 ? void 0 : clinic.createdByUid);
    if (!ownerUid) {
        logger_1.logger.warn("Clinic has no ownerUid/createdByUid; cannot provision owner", {
            clinicId,
        });
        return;
    }
    const displayName = pickOwnerDisplayName(clinic);
    const invitedEmail = safeStr(clinic === null || clinic === void 0 ? void 0 : clinic.createdByEmail) || null;
    const now = admin.firestore.FieldValue.serverTimestamp();
    const canonRef = db
        .collection("clinics")
        .doc(clinicId)
        .collection("memberships")
        .doc(ownerUid);
    const canonSnap = await canonRef.get();
    if (canonSnap.exists) {
        logger_1.logger.info("Owner membership already exists; skipping", {
            clinicId,
            ownerUid,
            path: canonRef.path,
        });
        return;
    }
    logger_1.logger.info("Provisioning missing owner membership", {
        clinicId,
        ownerUid,
    });
    const batch = db.batch();
    batch.set(canonRef, {
        role: "owner",
        roleId: "owner",
        displayName,
        invitedEmail,
        permissions: (0, roleTemplates_1.ownerRolePermissions)(),
        status: "active",
        active: true,
        createdAt: now,
        updatedAt: now,
        createdByUid: ownerUid,
        updatedByUid: ownerUid,
    });
    // Optional legacy mirror during migration window
    const legacyRef = db
        .collection("clinics")
        .doc(clinicId)
        .collection("members")
        .doc(ownerUid);
    batch.set(legacyRef, {
        roleId: "owner",
        displayName,
        invitedEmail,
        permissions: (0, roleTemplates_1.ownerRolePermissions)(),
        active: true,
        createdAt: now,
        updatedAt: now,
        createdByUid: ownerUid,
        updatedByUid: ownerUid,
    }, { merge: true });
    // Ensure user index exists too (clinic picker)
    const clinicName = safeStr((_b = clinic === null || clinic === void 0 ? void 0 : clinic.profile) === null || _b === void 0 ? void 0 : _b.name) || safeStr(clinic === null || clinic === void 0 ? void 0 : clinic.name) || clinicId;
    const userIdxRef = db
        .collection("users")
        .doc(ownerUid)
        .collection("memberships")
        .doc(clinicId);
    batch.set(userIdxRef, {
        clinicNameCache: clinicName,
        role: "owner",
        roleId: "owner",
        status: "active",
        active: true,
        createdAt: now,
    }, { merge: true });
    await batch.commit();
    logger_1.logger.info("Owner membership provisioned", {
        clinicId,
        ownerUid,
    });
});
//# sourceMappingURL=onClinicCreatedProvisionOwner.js.map