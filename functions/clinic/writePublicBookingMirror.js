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
exports.writePublicBookingMirror = writePublicBookingMirror;
const admin = __importStar(require("firebase-admin"));
const publicProjection_1 = require("./publicProjection");
const db = admin.firestore();
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
}
async function writePublicBookingMirror(clinicId, publicBookingSettingsDoc) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q;
    const clinicSnap = await db.doc(`clinics/${clinicId}`).get();
    const clinicDoc = ((_a = clinicSnap.data()) !== null && _a !== void 0 ? _a : {});
    const clinicName = safeStr((_b = clinicDoc === null || clinicDoc === void 0 ? void 0 : clinicDoc.profile) === null || _b === void 0 ? void 0 : _b.name) ||
        safeStr(clinicDoc === null || clinicDoc === void 0 ? void 0 : clinicDoc.name) ||
        safeStr(clinicDoc === null || clinicDoc === void 0 ? void 0 : clinicDoc.clinicName) ||
        "Clinic";
    const logoUrl = safeStr((_c = clinicDoc === null || clinicDoc === void 0 ? void 0 : clinicDoc.profile) === null || _c === void 0 ? void 0 : _c.logoUrl) ||
        safeStr(clinicDoc === null || clinicDoc === void 0 ? void 0 : clinicDoc.logoUrl) ||
        safeStr((_d = clinicDoc === null || clinicDoc === void 0 ? void 0 : clinicDoc.branding) === null || _d === void 0 ? void 0 : _d.logoUrl) ||
        "";
    const [servicesSnap, practitionersSnap, membershipsSnap] = await Promise.all([
        db.collection(`clinics/${clinicId}/services`).get(),
        db.collection(`clinics/${clinicId}/practitioners`).get(),
        db.collection(`clinics/${clinicId}/memberships`).get(), // ✅ canonical
    ]);
    const services = servicesSnap.docs.map((d) => { var _a; return ({ id: d.id, data: ((_a = d.data()) !== null && _a !== void 0 ? _a : {}) }); });
    const practitioners = practitionersSnap.docs.map((d) => {
        var _a;
        return ({
            id: d.id,
            data: ((_a = d.data()) !== null && _a !== void 0 ? _a : {}),
        });
    });
    const memberships = membershipsSnap.docs.map((d) => {
        var _a;
        return ({
            id: d.id,
            data: ((_a = d.data()) !== null && _a !== void 0 ? _a : {}),
        });
    });
    const projection = (0, publicProjection_1.buildPublicBookingProjection)({
        clinicId,
        clinicName,
        logoUrl,
        clinicDoc,
        publicBookingSettingsDoc: (publicBookingSettingsDoc !== null && publicBookingSettingsDoc !== void 0 ? publicBookingSettingsDoc : {}),
        services,
        practitioners,
        memberships,
    });
    const nestedPublicBooking = {
        clinicId: (_e = projection.clinicId) !== null && _e !== void 0 ? _e : clinicId,
        clinicName: (_f = projection.clinicName) !== null && _f !== void 0 ? _f : clinicName,
        logoUrl: (_g = projection.logoUrl) !== null && _g !== void 0 ? _g : logoUrl,
        contact: (_h = projection.contact) !== null && _h !== void 0 ? _h : {},
        bookingRules: (_j = projection.bookingRules) !== null && _j !== void 0 ? _j : {},
        openingHours: (_k = projection.openingHours) !== null && _k !== void 0 ? _k : {},
        weeklyHours: (_l = projection.weeklyHours) !== null && _l !== void 0 ? _l : {},
        weeklyHoursMeta: (_m = projection.weeklyHoursMeta) !== null && _m !== void 0 ? _m : {},
        slotMinutes: (_o = projection.slotMinutes) !== null && _o !== void 0 ? _o : null,
        services: (_p = projection.services) !== null && _p !== void 0 ? _p : [],
        practitioners: (_q = projection.practitioners) !== null && _q !== void 0 ? _q : [],
    };
    await db
        .doc(`clinics/${clinicId}/public/config/publicBooking/publicBooking`)
        .set({
        ...projection,
        publicBooking: nestedPublicBooking,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: "writePublicBookingMirror-gen2",
    }, { merge: true });
    return projection;
}
//# sourceMappingURL=writePublicBookingMirror.js.map