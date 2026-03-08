"use strict";
/**
 * listPatientsForBookingFn
 * Server-side read of patients for the Find patient dialog (booking flow).
 * Requires patients.read. Returns a list of { id, firstName, lastName, dateOfBirth, phone, email, address }
 * so the client does not depend on Firestore rules or indexes for this query.
 */
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
exports.listPatientsForBookingFn = void 0;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const permissions_1 = require("../permissions");
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
function safeStr(v) {
    return typeof v === "string" ? v.trim() : "";
}
function getNested(data, path) {
    const parts = path.split(".");
    let cur = data;
    for (const p of parts) {
        if (cur == null || typeof cur !== "object")
            return undefined;
        cur = cur[p];
    }
    return cur;
}
function toDateOfBirth(v) {
    if (v == null)
        return null;
    if (v instanceof admin.firestore.Timestamp) {
        const d = v.toDate();
        return d.toISOString().slice(0, 10);
    }
    if (typeof v === "string") {
        const parsed = new Date(v);
        if (!Number.isNaN(parsed.getTime()))
            return parsed.toISOString().slice(0, 10);
    }
    return null;
}
function docToRow(doc) {
    var _a, _b, _c, _d, _e, _f;
    const data = (doc.data() || {});
    const identity = data.identity || {};
    const contact = data.contact || {};
    const firstName = safeStr((_a = getNested(data, "identity.firstName")) !== null && _a !== void 0 ? _a : data.firstName) ||
        safeStr(identity.firstName);
    const lastName = safeStr((_b = getNested(data, "identity.lastName")) !== null && _b !== void 0 ? _b : data.lastName) ||
        safeStr(identity.lastName);
    const dobRaw = (_d = (_c = getNested(data, "identity.dateOfBirth")) !== null && _c !== void 0 ? _c : data.dateOfBirth) !== null && _d !== void 0 ? _d : data.dob;
    const dateOfBirth = toDateOfBirth(dobRaw);
    const email = safeStr((_e = getNested(data, "contact.email")) !== null && _e !== void 0 ? _e : data.email) ||
        safeStr(contact.email);
    const phone = safeStr((_f = getNested(data, "contact.phone")) !== null && _f !== void 0 ? _f : data.phone) ||
        safeStr(contact.phone);
    const addressObj = contact.address || {};
    const addressFlat = safeStr(data.address);
    const address = addressFlat ||
        [addressObj.line1, addressObj.line2, addressObj.city, addressObj.postcode]
            .filter(Boolean)
            .map((x) => String(x).trim())
            .join(", ") ||
        "";
    const status = data.status || {};
    const isArchived = status.archived === true || data.archived === true;
    const isMerged = safeStr(data.mergedIntoPatientId).length > 0;
    const isDeleted = data.deletedAt != null;
    return {
        id: doc.id,
        firstName: firstName || "",
        lastName: lastName || "",
        dateOfBirth,
        phone: phone || "",
        email: email || "",
        address: address || "",
        isArchived,
        isMerged,
        isDeleted,
    };
}
exports.listPatientsForBookingFn = (0, https_1.onCall)({ region: "europe-west3", cors: true }, async (request) => {
    var _a, _b;
    if (!((_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid)) {
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    }
    const clinicId = safeStr((_b = request.data) === null || _b === void 0 ? void 0 : _b.clinicId);
    if (!clinicId) {
        throw new https_1.HttpsError("invalid-argument", "clinicId is required.");
    }
    await (0, permissions_1.requireClinicPermission)(db, clinicId, request.auth.uid, "patients.read");
    const patientsRef = db.collection(`clinics/${clinicId}/patients`);
    const snap = await patientsRef
        .orderBy("lastName")
        .limit(300)
        .get();
    const patients = snap.docs.map(docToRow);
    return { patients };
});
//# sourceMappingURL=listPatientsForBooking.js.map