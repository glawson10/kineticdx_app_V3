"use strict";
/**
 * Commit 04 / 21–22: settings.upsertLocation
 * Create or edit a clinic location (name, color, show online, active, etc.).
 * Write path: clinics/{clinicId}/locations/{locationId}
 * Audit: settings.location.created | settings.location.updated | settings.location.deactivated | settings.location.activated
 *
 * Delete guard (Commit 22): Do NOT implement hard delete from UI. If adding delete in future:
 * - Ensure no future appointments reference this locationId.
 * - Ensure no appointmentTypes.allowedLocationIds include this locationId.
 * Deactivation only (active: false) is the supported lifecycle.
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
exports.upsertLocation = upsertLocation;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const permissions_1 = require("../permissions");
const audit_1 = require("../audit/audit");
const validators_1 = require("./validators");
const db = admin.firestore();
const FV = admin.firestore.FieldValue;
/** Server whitelist: only these keys accepted in patch. UI must send same keys. */
const LOCATION_PATCH_KEYS = new Set([
    "name",
    "addressText",
    "active",
    "showInOnlineBooking",
    "colorHex",
    "phone",
    "notes",
]);
function validateAndPickPatch(patch, isCreate) {
    const raw = (0, validators_1.pickAllowedFields)(patch, LOCATION_PATCH_KEYS);
    const name = (0, validators_1.assertString)(raw.name, "name", {
        required: isCreate,
        trim: true,
        minLength: 2,
        maxLength: 80,
    });
    if (isCreate && (!name || name.length === 0)) {
        throw new https_1.HttpsError("invalid-argument", "name is required when creating a location.");
    }
    const addressText = (0, validators_1.assertString)(raw.addressText, "addressText", {
        trim: true,
        maxLength: 1024,
    });
    const active = (0, validators_1.assertBoolean)(raw.active, "active");
    const showInOnlineBooking = (0, validators_1.assertBoolean)(raw.showInOnlineBooking, "showInOnlineBooking");
    const colorHex = (0, validators_1.assertHexColor)(raw.colorHex, "colorHex");
    const phone = (0, validators_1.assertString)(raw.phone, "phone", { trim: true, maxLength: 64 });
    const notes = (0, validators_1.assertString)(raw.notes, "notes", { trim: true, maxLength: 1024 });
    // Address optional unless showInOnlineBooking is being set to true: then require minimal address (future: line1, city, country).
    if (raw.showInOnlineBooking === true) {
        const addr = (addressText !== null && addressText !== void 0 ? addressText : "").toString().trim();
        if (addr.length < 3) {
            throw new https_1.HttpsError("invalid-argument", "When 'Show in online booking' is enabled, address is required (at least 3 characters, e.g. line1, city, country).");
        }
    }
    const out = {};
    if (name != null)
        out.name = name;
    if (addressText !== undefined)
        out.addressText = addressText !== null && addressText !== void 0 ? addressText : null;
    if (active !== undefined)
        out.active = active !== null && active !== void 0 ? active : null;
    if (showInOnlineBooking !== undefined)
        out.showInOnlineBooking = showInOnlineBooking !== null && showInOnlineBooking !== void 0 ? showInOnlineBooking : null;
    if (colorHex !== undefined)
        out.colorHex = colorHex !== null && colorHex !== void 0 ? colorHex : null;
    if (phone !== undefined)
        out.phone = phone !== null && phone !== void 0 ? phone : null;
    if (notes !== undefined)
        out.notes = notes !== null && notes !== void 0 ? notes : null;
    return out;
}
async function upsertLocation(request) {
    var _a, _b, _c, _d, _e, _f, _g;
    if (!((_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid)) {
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    }
    const data = request.data;
    const clinicId = (0, validators_1.requireNonEmptyString)(data === null || data === void 0 ? void 0 : data.clinicId, "clinicId");
    const locationIdRaw = data === null || data === void 0 ? void 0 : data.locationId;
    const locationId = locationIdRaw === null || locationIdRaw === undefined
        ? null
        : (0, validators_1.assertString)(locationIdRaw, "locationId", { maxLength: 128 });
    const isCreate = !locationId || locationId.length === 0;
    let patch;
    try {
        patch = validateAndPickPatch(data === null || data === void 0 ? void 0 : data.patch, isCreate);
    }
    catch (e) {
        if (e instanceof https_1.HttpsError)
            throw e;
        throw new https_1.HttpsError("invalid-argument", e instanceof Error ? e.message : "Invalid patch.");
    }
    if (Object.keys(patch).length === 0) {
        throw new https_1.HttpsError("invalid-argument", "No valid fields to update.");
    }
    const uid = request.auth.uid;
    await (0, permissions_1.requireClinicPermission)(db, clinicId, uid, "settings.write");
    const locationsRef = db.collection("clinics").doc(clinicId).collection("locations");
    const now = FV.serverTimestamp();
    let finalId;
    let before = {};
    if (isCreate) {
        finalId = locationsRef.doc().id;
        const doc = {
            name: (_b = patch.name) !== null && _b !== void 0 ? _b : "",
            addressText: (_c = patch.addressText) !== null && _c !== void 0 ? _c : null,
            active: (_d = patch.active) !== null && _d !== void 0 ? _d : true,
            showInOnlineBooking: (_e = patch.showInOnlineBooking) !== null && _e !== void 0 ? _e : false,
            colorHex: (_f = patch.colorHex) !== null && _f !== void 0 ? _f : null,
            createdAt: now,
            updatedAt: now,
        };
        await locationsRef.doc(finalId).set(doc);
        const changes = {};
        for (const [k, v] of Object.entries(doc)) {
            if (k !== "createdAt" && k !== "updatedAt")
                changes[k] = v;
        }
        await (0, audit_1.writeSettingsAuditEvent)(db, clinicId, "settings.location.created", uid, `clinics/${clinicId}/locations/${finalId}`, finalId, changes);
        return { ok: true, locationId: finalId };
    }
    finalId = locationId;
    const locRef = locationsRef.doc(finalId);
    const snap = await locRef.get();
    if (!snap.exists) {
        throw new https_1.HttpsError("not-found", "Location not found.");
    }
    const existing = (_g = snap.data()) !== null && _g !== void 0 ? _g : {};
    for (const key of Object.keys(patch)) {
        before[key] = existing[key];
    }
    const updateData = {
        updatedAt: now,
    };
    if (patch.name !== undefined)
        updateData.name = patch.name;
    if (patch.addressText !== undefined)
        updateData.addressText = patch.addressText;
    if (patch.active !== undefined)
        updateData.active = patch.active;
    if (patch.showInOnlineBooking !== undefined)
        updateData.showInOnlineBooking = patch.showInOnlineBooking;
    if (patch.colorHex !== undefined)
        updateData.colorHex = patch.colorHex;
    await locRef.update(updateData);
    const changes = {};
    for (const key of Object.keys(patch)) {
        changes[key] = { before: before[key], after: updateData[key] };
    }
    // Full edits only; active-only toggles use setLocationActive (audit: active_set).
    await (0, audit_1.writeSettingsAuditEvent)(db, clinicId, "settings.location.updated", uid, `clinics/${clinicId}/locations/${finalId}`, finalId, changes);
    return { ok: true, locationId: finalId };
}
//# sourceMappingURL=upsertLocation.js.map