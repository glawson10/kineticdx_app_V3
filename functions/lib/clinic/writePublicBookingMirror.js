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
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
}
const DAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
function normalizeWeeklyHours(weekly) {
    const out = {
        mon: [],
        tue: [],
        wed: [],
        thu: [],
        fri: [],
        sat: [],
        sun: [],
    };
    if (!weekly || typeof weekly !== "object")
        return out;
    for (const d of DAY_KEYS) {
        const v = weekly[d];
        if (Array.isArray(v)) {
            out[d] = v
                .map((it) => ({
                start: safeStr(it === null || it === void 0 ? void 0 : it.start),
                end: safeStr(it === null || it === void 0 ? void 0 : it.end),
            }))
                .filter((it) => it.start && it.end);
        }
    }
    return out;
}
async function writePublicBookingMirror(clinicId, publicBookingSettingsDoc) {
    var _a, _b, _c, _d, _e;
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
        db.collection(`clinics/${clinicId}/memberships`).get(),
    ]);
    const services = servicesSnap.docs.map((d) => {
        var _a;
        return ({
            id: d.id,
            data: ((_a = d.data()) !== null && _a !== void 0 ? _a : {}),
        });
    });
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
    // 🔐 FORCE canonical weeklyHours (ALL 7 DAYS ALWAYS PRESENT)
    const weeklyHours = normalizeWeeklyHours(projection.weeklyHours);
    const ref = db.doc(`clinics/${clinicId}/public/config/publicBooking/publicBooking`);
    await ref.set({
        ...projection,
        weeklyHours,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: "writePublicBookingMirror-gen2",
        schemaVersion: (_e = projection.schemaVersion) !== null && _e !== void 0 ? _e : 1,
    }, { merge: false } // AUTHORITATIVE SNAPSHOT
    );
    return {
        ...projection,
        weeklyHours,
    };
}
//# sourceMappingURL=writePublicBookingMirror.js.map