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
exports.onClinicCreatedProvisionDefaults = void 0;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/v2/firestore");
const logger_1 = require("firebase-functions/logger");
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
/**
 * Creates default settings docs for a clinic + ensures owner membership exists.
 * Safe: idempotent (only writes if missing).
 *
 * Trigger: when clinics/{clinicId} is created.
 */
exports.onClinicCreatedProvisionDefaults = (0, firestore_1.onDocumentCreated)({
    region: "europe-west3",
    document: "clinics/{clinicId}",
}, async (event) => {
    var _a, _b, _c, _d;
    const clinicId = ((_a = event.params.clinicId) !== null && _a !== void 0 ? _a : "").toString().trim();
    if (!clinicId)
        return;
    const clinicRef = db.doc(`clinics/${clinicId}`);
    const clinicSnap = await clinicRef.get();
    const clinic = (_b = clinicSnap.data()) !== null && _b !== void 0 ? _b : {};
    const createdByUid = ((_c = clinic.createdByUid) !== null && _c !== void 0 ? _c : "").toString().trim();
    const createdByEmail = ((_d = clinic.createdByEmail) !== null && _d !== void 0 ? _d : "").toString().trim() || null;
    // ───────────────────────────────────────────────────────────
    // 1) Provision notification settings doc (your existing logic)
    // ───────────────────────────────────────────────────────────
    const notifRef = db.doc(`clinics/${clinicId}/settings/notifications`);
    const notifSnap = await notifRef.get();
    if (!notifSnap.exists) {
        const defaultNotifications = {
            schemaVersion: 1,
            defaultLocale: "en",
            brevo: {
                senderId: null, // set in Brevo + clinic settings later
                replyToEmail: null, // set later
            },
            events: {
                "booking.created.patientConfirmation": {
                    enabled: false,
                    templateIdByLocale: {},
                },
                "booking.created.clinicianNotification": {
                    enabled: false,
                    templateIdByLocale: {},
                    recipientPolicy: { mode: "practitionerOnAppointment" },
                },
            },
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            createdBy: "system.provisioner",
        };
        await notifRef.set(defaultNotifications, { merge: false });
        logger_1.logger.info("Provisioned default notifications settings", { clinicId });
    }
    else {
        logger_1.logger.info("notifications settings already exist; skipping", { clinicId });
    }
    // ───────────────────────────────────────────────────────────
    // 2) Ensure the creator is the clinic owner member
    // ───────────────────────────────────────────────────────────
    if (!createdByUid) {
        logger_1.logger.warn("Clinic missing createdByUid; cannot provision owner membership", { clinicId });
        return;
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    // clinics/{clinicId}/members/{uid}  (authoritative)
    const memberRef = db.doc(`clinics/${clinicId}/members/${createdByUid}`);
    const memberSnap = await memberRef.get();
    if (!memberSnap.exists) {
        const ownerPermissions = {
            // Settings / staff
            "settings.read": true,
            "settings.write": true,
            "members.read": true,
            "members.manage": true,
            "roles.manage": true,
            // Schedule
            "schedule.read": true,
            "schedule.write": true,
            // Patients / clinical
            "patients.read": true,
            "patients.write": true,
            "clinical.read": true,
            "clinical.write": true,
            // Notes
            "notes.read": true,
            "notes.write.any": true,
            "notes.write.own": true,
            // Services / registries / resources
            "services.manage": true,
            "registries.manage": true,
            "resources.manage": true,
            // Audit
            "audit.read": true,
        };
        await memberRef.set({
            active: true,
            status: "active",
            roleId: "owner",
            invitedEmail: createdByEmail, // optional (nice for UI)
            permissions: ownerPermissions,
            createdAt: now,
            updatedAt: now,
            createdByUid: createdByUid,
            updatedByUid: createdByUid,
        }, { merge: false });
        logger_1.logger.info("Provisioned owner membership", { clinicId, uid: createdByUid });
    }
    else {
        logger_1.logger.info("Owner membership already exists; skipping", { clinicId, uid: createdByUid });
    }
    // Optional but recommended: users/{uid}/memberships/{clinicId} (fast clinic picker index)
    // Only create if missing.
    const indexRef = db.doc(`users/${createdByUid}/memberships/${clinicId}`);
    const indexSnap = await indexRef.get();
    if (!indexSnap.exists) {
        await indexRef.set({
            clinicId,
            roleId: "owner",
            active: true,
            invitedEmail: createdByEmail,
            createdAt: now,
            updatedAt: now,
        }, { merge: false });
        logger_1.logger.info("Provisioned membership index", { clinicId, uid: createdByUid });
    }
});
//# sourceMappingURL=provisionClinicDefaults.js.map