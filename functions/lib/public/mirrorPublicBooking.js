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
exports.onPublicBookingSettingsWrite = void 0;
// functions/src/public/mirrorPublicBooking.ts
const admin = __importStar(require("firebase-admin"));
const logger_1 = require("firebase-functions/logger");
const firestore_1 = require("firebase-functions/v2/firestore");
const publicProjection_1 = require("../clinic/publicProjection");
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
function safeStr(v) {
    return typeof v === "string" ? v.trim() : (v !== null && v !== void 0 ? v : "").toString().trim();
}
function asMap(v) {
    return v && typeof v === "object" ? v : {};
}
exports.onPublicBookingSettingsWrite = (0, firestore_1.onDocumentWritten)({
    region: "europe-west3",
    document: "clinics/{clinicId}/settings/publicBooking",
}, async (event) => {
    var _a, _b, _c, _d, _e;
    const clinicId = safeStr((_a = event.params) === null || _a === void 0 ? void 0 : _a.clinicId);
    if (!clinicId) {
        logger_1.logger.warn("mirrorPublicBooking: missing clinicId param");
        return;
    }
    // ✅ Canonical public mirror doc path (matches listPublicSlotsFn)
    const publicDocRef = db.doc(`clinics/${clinicId}/public/config/publicBooking/publicBooking`);
    const afterSnap = (_b = event.data) === null || _b === void 0 ? void 0 : _b.after;
    const beforeSnap = (_c = event.data) === null || _c === void 0 ? void 0 : _c.before;
    // If deleted, delete mirror too (optional)
    if (!(afterSnap === null || afterSnap === void 0 ? void 0 : afterSnap.exists)) {
        await publicDocRef.delete().catch(() => { });
        logger_1.logger.info("mirrorPublicBooking: source deleted, mirror deleted", {
            clinicId,
            hadBefore: !!(beforeSnap === null || beforeSnap === void 0 ? void 0 : beforeSnap.exists),
        });
        return;
    }
    const publicBookingSettingsDoc = asMap(afterSnap.data());
    // Read clinic root + services + members (for practitioners + memberships)
    const clinicRef = db.doc(`clinics/${clinicId}`);
    const servicesCol = db.collection(`clinics/${clinicId}/services`);
    const membersCol = db.collection(`clinics/${clinicId}/members`);
    const [clinicSnap, servicesSnap, membersSnap] = await Promise.all([
        clinicRef.get().catch(() => null),
        servicesCol.where("active", "==", true).get().catch(() => null),
        // Single-field query only; no composite needed
        membersCol.where("active", "==", true).get().catch(() => null),
    ]);
    const clinicDoc = (clinicSnap === null || clinicSnap === void 0 ? void 0 : clinicSnap.exists) ? asMap(clinicSnap.data()) : {};
    // Prefer root keys (new schema), fall back to legacy profile map
    const profile = asMap(clinicDoc.profile);
    const clinicName = safeStr(clinicDoc.name) ||
        safeStr(profile.name) ||
        safeStr(clinicDoc.clinicName) ||
        safeStr(clinicDoc.publicName) ||
        "Clinic";
    const logoUrl = safeStr(clinicDoc.logoUrl) ||
        safeStr(profile.logoUrl) ||
        safeStr(asMap(clinicDoc.branding).logoUrl) ||
        safeStr(asMap(asMap(clinicDoc.settings).appearance).logoUrl) ||
        "";
    const services = (_d = servicesSnap === null || servicesSnap === void 0 ? void 0 : servicesSnap.docs.map((d) => ({
        id: d.id,
        data: asMap(d.data()),
    }))) !== null && _d !== void 0 ? _d : [];
    const memberships = (_e = membersSnap === null || membersSnap === void 0 ? void 0 : membersSnap.docs.map((d) => ({
        id: d.id,
        data: asMap(d.data()),
    }))) !== null && _e !== void 0 ? _e : [];
    // Practitioners: best-effort filter from memberships.
    // Adjust these heuristics to match your membership schema.
    const practitioners = memberships
        .filter((m) => {
        const md = asMap(m.data);
        if (md.active !== true)
            return false;
        const role = safeStr(md.role).toLowerCase();
        const kind = safeStr(md.kind).toLowerCase();
        const isPractitioner = md.isPractitioner === true;
        // common patterns: role/kind flags or explicit boolean
        if (isPractitioner)
            return true;
        if (role.includes("practitioner") || role.includes("clinician"))
            return true;
        if (kind.includes("practitioner") || kind.includes("clinician"))
            return true;
        return false;
    })
        .map((m) => ({
        id: safeStr(m.id), // usually uid
        data: m.data,
    }));
    // NOTE: buildPublicBookingProjection in your project expects these keys:
    // - clinicId, clinicName, logoUrl
    // - clinicDoc? (optional)
    // - publicBookingSettingsDoc
    // - services
    // - practitioners
    // - memberships
    const input = {
        clinicId,
        clinicName,
        logoUrl,
        clinicDoc,
        publicBookingSettingsDoc,
        services,
        practitioners,
        memberships,
    };
    const projection = (0, publicProjection_1.buildPublicBookingProjection)(input);
    await publicDocRef.set({
        ...projection,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: "mirrorPublicBooking-v2",
    }, { merge: true });
    logger_1.logger.info("mirrorPublicBooking: mirror updated", {
        clinicId,
        services: services.length,
        memberships: memberships.length,
        practitioners: practitioners.length,
    });
});
//# sourceMappingURL=mirrorPublicBooking.js.map