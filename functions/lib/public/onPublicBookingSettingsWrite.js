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
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/v2/firestore");
const logger_1 = require("firebase-functions/logger");
const publicProjection_1 = require("../clinic/publicProjection");
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
}
/**
 * SINGLE BRIDGE WRITER (trigger)
 * Canonical settings (writeable):
 *   clinics/{clinicId}/settings/publicBooking
 *
 * Public mirror (read-only):
 *   clinics/{clinicId}/public/config/publicBooking/publicBooking
 */
exports.onPublicBookingSettingsWrite = (0, firestore_1.onDocumentWritten)({
    region: "europe-west3",
    document: "clinics/{clinicId}/settings/publicBooking",
}, async (event) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j;
    const clinicId = safeStr(event.params.clinicId);
    if (!clinicId)
        return;
    logger_1.logger.info("onPublicBookingSettingsWrite EXECUTED", { clinicId, ts: Date.now() });
    const publicDocRef = db.doc(`clinics/${clinicId}/public/config/publicBooking/publicBooking`);
    const afterSnap = (_a = event.data) === null || _a === void 0 ? void 0 : _a.after;
    // If deleted, delete mirror too (best-effort)
    if (!afterSnap || !afterSnap.exists) {
        logger_1.logger.warn("settings deleted -> deleting mirror", { clinicId });
        await publicDocRef.delete().catch(() => { });
        return;
    }
    const settings = ((_b = afterSnap.data()) !== null && _b !== void 0 ? _b : {});
    const clinicSnap = await db.doc(`clinics/${clinicId}`).get();
    const clinicDoc = clinicSnap.exists ? ((_c = clinicSnap.data()) !== null && _c !== void 0 ? _c : {}) : {};
    const clinicName = safeStr((_d = clinicDoc === null || clinicDoc === void 0 ? void 0 : clinicDoc.profile) === null || _d === void 0 ? void 0 : _d.name) ||
        safeStr(clinicDoc === null || clinicDoc === void 0 ? void 0 : clinicDoc.name) ||
        safeStr(clinicDoc === null || clinicDoc === void 0 ? void 0 : clinicDoc.clinicName) ||
        "Clinic";
    const logoUrl = safeStr((_e = clinicDoc === null || clinicDoc === void 0 ? void 0 : clinicDoc.profile) === null || _e === void 0 ? void 0 : _e.logoUrl) ||
        safeStr(clinicDoc === null || clinicDoc === void 0 ? void 0 : clinicDoc.logoUrl) ||
        safeStr((_f = clinicDoc === null || clinicDoc === void 0 ? void 0 : clinicDoc.branding) === null || _f === void 0 ? void 0 : _f.logoUrl) ||
        "";
    const [servicesSnap, practitionersSnap, membersSnap, membershipsSnap, locationsSnap, typesSnap] = await Promise.all([
        db.collection(`clinics/${clinicId}/services`).get(),
        db.collection(`clinics/${clinicId}/practitioners`).get(),
        db.collection(`clinics/${clinicId}/members`).get(),
        db.collection(`clinics/${clinicId}/memberships`).get(),
        db.collection(`clinics/${clinicId}/locations`).get(),
        db.collection(`clinics/${clinicId}/appointmentTypes`).get(),
    ]);
    logger_1.logger.info("collection counts", {
        clinicId,
        services: servicesSnap.size,
        practitioners: practitionersSnap.size,
        members: membersSnap.size,
        memberships: membershipsSnap.size,
        locations: locationsSnap.size,
        appointmentTypes: typesSnap.size,
    });
    const services = servicesSnap.docs.map((d) => { var _a; return ({ id: d.id, data: ((_a = d.data()) !== null && _a !== void 0 ? _a : {}) }); });
    const practitioners = practitionersSnap.docs.map((d) => {
        var _a;
        return ({
            id: d.id,
            data: ((_a = d.data()) !== null && _a !== void 0 ? _a : {}),
        });
    });
    // Merge members (canonical) + memberships (legacy) so projection has membership data for all; prefer members.
    const memberById = new Map();
    for (const d of membersSnap.docs) {
        memberById.set(d.id, { id: d.id, data: ((_g = d.data()) !== null && _g !== void 0 ? _g : {}) });
    }
    for (const d of membershipsSnap.docs) {
        if (!memberById.has(d.id)) {
            memberById.set(d.id, { id: d.id, data: ((_h = d.data()) !== null && _h !== void 0 ? _h : {}) });
        }
    }
    const memberships = Array.from(memberById.values());
    const projection = (0, publicProjection_1.buildPublicBookingProjection)({
        clinicId,
        clinicName,
        logoUrl,
        clinicDoc,
        publicBookingSettingsDoc: settings,
        services,
        practitioners,
        memberships,
    });
    // Curated lists for public booking: locations and appointmentTypes (active + showInOnlineBooking)
    const locationsList = locationsSnap.docs
        .filter((d) => {
        const dta = d.data();
        return (dta === null || dta === void 0 ? void 0 : dta.active) === true && (dta === null || dta === void 0 ? void 0 : dta.showInOnlineBooking) === true;
    })
        .map((d) => {
        const dta = d.data();
        return { id: d.id, name: safeStr(dta === null || dta === void 0 ? void 0 : dta.name) || d.id };
    });
    const appointmentTypesList = typesSnap.docs
        .filter((d) => {
        const dta = d.data();
        return (dta === null || dta === void 0 ? void 0 : dta.active) === true && (dta === null || dta === void 0 ? void 0 : dta.showInOnlineBooking) === true;
    })
        .map((d) => {
        const dta = d.data();
        const durationMinutes = typeof (dta === null || dta === void 0 ? void 0 : dta.durationMinutes) === "number" ? dta.durationMinutes : 30;
        return {
            id: d.id,
            name: safeStr(dta === null || dta === void 0 ? void 0 : dta.name) || d.id,
            defaultDurationMinutes: durationMinutes,
            description: safeStr(dta === null || dta === void 0 ? void 0 : dta.description) || undefined,
            defaultPrice: typeof (dta === null || dta === void 0 ? void 0 : dta.defaultPrice) === "number" ? dta.defaultPrice : undefined,
            colorHex: safeStr(dta === null || dta === void 0 ? void 0 : dta.colorHex) || undefined,
        };
    });
    // Practitioners in mirror must include allowedLocationIds for location filtering
    const practitionersList = ((_j = projection.practitioners) !== null && _j !== void 0 ? _j : []).map((p) => {
        var _a;
        return ({
            id: p.id,
            displayName: (_a = p.displayName) !== null && _a !== void 0 ? _a : p.id,
            ...(Array.isArray(p.allowedLocationIds) && p.allowedLocationIds.length > 0
                ? { allowedLocationIds: p.allowedLocationIds }
                : {}),
        });
    });
    logger_1.logger.info("projection practitioners", {
        clinicId,
        count: practitionersList.length,
        locationsCount: locationsList.length,
    });
    await publicDocRef.set({
        ...projection,
        locations: locationsList,
        practitioners: practitionersList,
        appointmentTypes: appointmentTypesList,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: "onPublicBookingSettingsWrite-gen2",
    }, { merge: true });
    logger_1.logger.info("wrote public mirror", { path: publicDocRef.path, locations: locationsList.length });
});
//# sourceMappingURL=onPublicBookingSettingsWrite.js.map