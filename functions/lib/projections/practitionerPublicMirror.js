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
exports.mirrorPractitionerToPublic = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const logger_1 = require("firebase-functions/logger");
const admin = __importStar(require("firebase-admin"));
const writePublicBookingMirror_1 = require("../clinic/writePublicBookingMirror");
if (!admin.apps.length) {
    admin.initializeApp();
}
const db = admin.firestore();
/**
 * When a practitioner doc is written, rebuild the canonical public booking mirror
 * at clinics/{clinicId}/public/config/publicBooking/publicBooking so the
 * practitioner list is always up to date.
 */
exports.mirrorPractitionerToPublic = (0, firestore_1.onDocumentWritten)({
    document: "clinics/{clinicId}/practitioners/{practitionerId}",
    region: "europe-west3",
}, async (event) => {
    var _a, _b, _c, _d;
    const { clinicId, practitionerId } = event.params;
    logger_1.logger.info("mirrorPractitionerToPublic fired", { clinicId, practitionerId });
    try {
        const settingsSnap = await db
            .doc(`clinics/${clinicId}/settings/publicBooking`)
            .get();
        if (!settingsSnap.exists) {
            logger_1.logger.info("mirrorPractitionerToPublic: no settings/publicBooking — skipping mirror rebuild", { clinicId });
            return;
        }
        const settings = ((_a = settingsSnap.data()) !== null && _a !== void 0 ? _a : {});
        const projection = await (0, writePublicBookingMirror_1.writePublicBookingMirror)(clinicId, settings);
        logger_1.logger.info("mirrorPractitionerToPublic: mirror rebuilt", {
            clinicId,
            practitionerId,
            practitionerCount: (_c = (_b = projection === null || projection === void 0 ? void 0 : projection.practitioners) === null || _b === void 0 ? void 0 : _b.length) !== null && _c !== void 0 ? _c : 0,
        });
    }
    catch (err) {
        logger_1.logger.error("mirrorPractitionerToPublic FAILED", {
            clinicId,
            practitionerId,
            err: (_d = err === null || err === void 0 ? void 0 : err.message) !== null && _d !== void 0 ? _d : String(err),
        });
        throw err;
    }
});
//# sourceMappingURL=practitionerPublicMirror.js.map