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
const admin = __importStar(require("firebase-admin"));
if (!admin.apps.length) {
    admin.initializeApp();
}
async function rebuildPublicPractitionerMirrors(clinicId) {
    const db = admin.firestore();
    const dirSnap = await db
        .collection(`clinics/${clinicId}/public/directory/practitioners`)
        .get();
    const list = dirSnap.docs.map((d) => {
        var _a, _b, _c, _d;
        const data = (_a = d.data()) !== null && _a !== void 0 ? _a : {};
        return {
            practitionerId: String((_b = data.practitionerId) !== null && _b !== void 0 ? _b : d.id),
            displayName: String((_c = data.displayName) !== null && _c !== void 0 ? _c : "").trim(),
            active: Boolean((_d = data.active) !== null && _d !== void 0 ? _d : false),
        };
    });
    const payload = {
        // UI might expect this exact nesting
        publicBooking: { practitioners: list },
        // Some code might expect a top-level list
        practitioners: list,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: "mirrorPractitionerToPublic.rebuildMirrors",
    };
    const refA = db.doc(`clinics/${clinicId}/public/config/publicBooking`);
    const refB = db.doc(`clinics/${clinicId}/public/publicBooking`);
    console.log("rebuild mirrors", {
        clinicId,
        count: list.length,
        refA: refA.path,
        refB: refB.path,
    });
    await Promise.all([
        refA.set(payload, { merge: true }),
        refB.set(payload, { merge: true }),
    ]);
}
exports.mirrorPractitionerToPublic = (0, firestore_1.onDocumentWritten)({
    document: "clinics/{clinicId}/practitioners/{practitionerId}",
    region: "europe-west3",
}, async (event) => {
    var _a, _b, _c, _d, _e;
    const { clinicId, practitionerId } = event.params;
    console.log("mirrorPractitionerToPublic fired", { clinicId, practitionerId });
    try {
        const afterSnap = (_a = event.data) === null || _a === void 0 ? void 0 : _a.after;
        const publicDirRef = admin
            .firestore()
            .doc(`clinics/${clinicId}/public/directory/practitioners/${practitionerId}`);
        // Delete
        if (!(afterSnap === null || afterSnap === void 0 ? void 0 : afterSnap.exists)) {
            console.log("deleted -> removing directory doc", publicDirRef.path);
            await publicDirRef.delete().catch(() => { });
            await rebuildPublicPractitionerMirrors(clinicId);
            return;
        }
        const data = (_b = afterSnap.data()) !== null && _b !== void 0 ? _b : {};
        const dirPayload = {
            practitionerId,
            displayName: String((_c = data.displayName) !== null && _c !== void 0 ? _c : "").trim(),
            active: Boolean((_d = data.active) !== null && _d !== void 0 ? _d : false),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedBy: "mirrorPractitionerToPublic",
        };
        console.log("writing directory doc", { path: publicDirRef.path, dirPayload });
        await publicDirRef.set(dirPayload, { merge: true });
        await rebuildPublicPractitionerMirrors(clinicId);
        console.log("mirrorPractitionerToPublic complete");
    }
    catch (err) {
        console.error("mirrorPractitionerToPublic FAILED", (_e = err === null || err === void 0 ? void 0 : err.message) !== null && _e !== void 0 ? _e : err, err);
        throw err;
    }
});
//# sourceMappingURL=practitionerPublicMirror.js.map