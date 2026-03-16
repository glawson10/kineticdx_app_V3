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
exports.writeAuditEvent = writeAuditEvent;
exports.writeSettingsAuditEvent = writeSettingsAuditEvent;
const admin = __importStar(require("firebase-admin"));
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
}
async function resolveActorDisplayName(db, clinicId, uid) {
    var _a, _b;
    const u = safeStr(uid);
    if (!u)
        return "";
    try {
        // 1) Clinic membership doc (canonical) — clinic-scoped name/email
        const canon = await db
            .collection("clinics")
            .doc(clinicId)
            .collection("memberships")
            .doc(u)
            .get();
        if (canon.exists) {
            const md = canon.data() || {};
            const dn = safeStr((_a = md["displayName"]) !== null && _a !== void 0 ? _a : md["name"]);
            if (dn)
                return dn;
            const email = safeStr(md["email"]);
            if (email)
                return email;
        }
        // 2) Legacy clinic member doc (temporary fallback)
        const legacy = await db
            .collection("clinics")
            .doc(clinicId)
            .collection("members")
            .doc(u)
            .get();
        if (legacy.exists) {
            const md = legacy.data() || {};
            const dn = safeStr((_b = md["displayName"]) !== null && _b !== void 0 ? _b : md["name"]);
            if (dn)
                return dn;
            const email = safeStr(md["email"]);
            if (email)
                return email;
        }
        // 3) Global user profile doc
        const userDoc = await db.collection("users").doc(u).get();
        if (userDoc.exists) {
            const ud = userDoc.data() || {};
            const dn = safeStr(ud["displayName"]);
            if (dn)
                return dn;
            const email = safeStr(ud["email"]);
            if (email)
                return email;
        }
        // 4) Firebase Auth
        const au = await admin.auth().getUser(u);
        const dn2 = safeStr(au.displayName);
        if (dn2)
            return dn2;
        const em2 = safeStr(au.email);
        if (em2)
            return em2;
        return u;
    }
    catch {
        return u;
    }
}
function removeUndefined(obj) {
    const cleaned = {};
    for (const [key, value] of Object.entries(obj)) {
        if (value !== undefined) {
            // Recursively clean nested objects
            if (value && typeof value === "object" && !Array.isArray(value) && !(value instanceof admin.firestore.Timestamp)) {
                cleaned[key] = removeUndefined(value);
            }
            else {
                cleaned[key] = value;
            }
        }
    }
    return cleaned;
}
async function writeAuditEvent(db, clinicId, event) {
    const actorUid = safeStr(event.actorUid);
    const actorDisplayName = safeStr(event.actorDisplayName) ||
        (actorUid ? await resolveActorDisplayName(db, clinicId, actorUid) : "");
    // Filter out undefined values - Firestore doesn't accept undefined
    const cleanEvent = {
        type: event.type,
        actorUid,
        actorDisplayName: actorDisplayName || null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (event.patientId)
        cleanEvent.patientId = event.patientId;
    if (event.episodeId)
        cleanEvent.episodeId = event.episodeId;
    if (event.noteId)
        cleanEvent.noteId = event.noteId;
    if (event.appointmentId)
        cleanEvent.appointmentId = event.appointmentId;
    if (event.metadata && Object.keys(event.metadata).length > 0) {
        // Remove undefined values from metadata object
        const cleanedMetadata = removeUndefined(event.metadata);
        if (Object.keys(cleanedMetadata).length > 0) {
            cleanEvent.metadata = cleanedMetadata;
        }
    }
    await db.collection("clinics").doc(clinicId).collection("audit").add(cleanEvent);
}
async function writeSettingsAuditEvent(db, clinicId, eventType, actorUserId, entityPath, entityId, changes) {
    const ref = db.collection("clinics").doc(clinicId).collection("audit").doc();
    // Firestore does not accept undefined; strip it from nested changes
    const cleanChanges = removeUndefined((changes !== null && changes !== void 0 ? changes : {}));
    await ref.set({
        clinicId,
        eventType,
        actorUserId: (actorUserId !== null && actorUserId !== void 0 ? actorUserId : "").toString().trim(),
        entityPath,
        entityId,
        changes: cleanChanges,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
}
//# sourceMappingURL=audit.js.map