"use strict";
/**
 * settings.upsertAppointmentType
 * Create or update an appointment type.
 * Write path: clinics/{clinicId}/appointmentTypes/{appointmentTypeId}
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
exports.upsertAppointmentType = upsertAppointmentType;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const permissions_1 = require("../permissions");
const audit_1 = require("../audit/audit");
const validators_1 = require("./validators");
const db = admin.firestore();
const FV = admin.firestore.FieldValue;
const APPT_TYPE_PATCH_KEYS = new Set([
    "name",
    "durationMinutes",
    "colorHex",
    "active",
    "showInOnlineBooking",
    "description",
    "defaultPrice",
    "allowedLocationIds",
    "telehealth",
    "allowedPractitionerIds",
]);
function validateAndPickPatch(patch, isCreate) {
    const raw = (0, validators_1.pickAllowedFields)(patch, APPT_TYPE_PATCH_KEYS);
    const name = (0, validators_1.assertString)(raw.name, "name", {
        required: isCreate,
        trim: true,
        minLength: 2,
        maxLength: 120,
    });
    if (isCreate && (!name || name.length === 0)) {
        throw new https_1.HttpsError("invalid-argument", "name is required when creating an appointment type.");
    }
    const durationMinutes = (0, validators_1.assertIntRange)(raw.durationMinutes, "durationMinutes", {
        min: 5,
        max: 480,
        required: isCreate,
    });
    if (durationMinutes != null && durationMinutes % 5 !== 0) {
        throw new https_1.HttpsError("invalid-argument", "durationMinutes must be divisible by 5.");
    }
    const colorHex = (0, validators_1.assertHexColor)(raw.colorHex, "colorHex");
    const active = (0, validators_1.assertBoolean)(raw.active, "active");
    const showInOnlineBooking = (0, validators_1.assertBoolean)(raw.showInOnlineBooking, "showInOnlineBooking");
    const description = (0, validators_1.assertString)(raw.description, "description", { trim: true, maxLength: 500 });
    let defaultPrice;
    if (raw.defaultPrice !== undefined && raw.defaultPrice !== null) {
        const p = typeof raw.defaultPrice === "number" ? raw.defaultPrice : parseFloat(String(raw.defaultPrice));
        if (!Number.isFinite(p) || p < 0) {
            throw new https_1.HttpsError("invalid-argument", "defaultPrice must be a non-negative number.");
        }
        defaultPrice = Math.round(p * 100) / 100;
    }
    else {
        defaultPrice = raw.defaultPrice === null ? null : undefined;
    }
    let allowedLocationIds;
    if (raw.allowedLocationIds !== undefined) {
        if (raw.allowedLocationIds === null) {
            allowedLocationIds = null;
        }
        else if (Array.isArray(raw.allowedLocationIds)) {
            allowedLocationIds = raw.allowedLocationIds.map((id) => String(id).trim()).filter(Boolean);
        }
    }
    const telehealth = (0, validators_1.assertBoolean)(raw.telehealth, "telehealth");
    let allowedPractitionerIds;
    if (raw.allowedPractitionerIds !== undefined) {
        if (raw.allowedPractitionerIds === null) {
            allowedPractitionerIds = null;
        }
        else if (Array.isArray(raw.allowedPractitionerIds)) {
            allowedPractitionerIds = raw.allowedPractitionerIds.map((id) => String(id).trim()).filter(Boolean);
        }
    }
    const out = {};
    if (name != null)
        out.name = name;
    if (durationMinutes != null)
        out.durationMinutes = durationMinutes;
    if (colorHex !== undefined)
        out.colorHex = colorHex !== null && colorHex !== void 0 ? colorHex : null;
    if (active !== undefined && active !== null)
        out.active = active;
    if (showInOnlineBooking !== undefined && showInOnlineBooking !== null)
        out.showInOnlineBooking = showInOnlineBooking;
    if (description !== undefined)
        out.description = description !== null && description !== void 0 ? description : null;
    if (defaultPrice !== undefined)
        out.defaultPrice = defaultPrice;
    if (allowedLocationIds !== undefined)
        out.allowedLocationIds = allowedLocationIds;
    if (telehealth !== undefined && telehealth !== null)
        out.telehealth = telehealth;
    if (allowedPractitionerIds !== undefined)
        out.allowedPractitionerIds = allowedPractitionerIds;
    return out;
}
async function upsertAppointmentType(request) {
    var _a;
    if (!((_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid)) {
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    }
    const data = request.data;
    const clinicId = (0, validators_1.requireNonEmptyString)(data === null || data === void 0 ? void 0 : data.clinicId, "clinicId");
    const appointmentTypeIdRaw = data === null || data === void 0 ? void 0 : data.appointmentTypeId;
    const appointmentTypeId = appointmentTypeIdRaw === null || appointmentTypeIdRaw === undefined || appointmentTypeIdRaw === ""
        ? null
        : String(appointmentTypeIdRaw).trim();
    const isCreate = !appointmentTypeId || appointmentTypeId.length === 0;
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
    try {
        return await upsertAppointmentTypeImpl(db, clinicId, uid, appointmentTypeId, isCreate, patch);
    }
    catch (e) {
        if (e instanceof https_1.HttpsError)
            throw e;
        const message = e instanceof Error ? e.message : String(e);
        throw new https_1.HttpsError("internal", message || "Failed to save appointment type.");
    }
}
async function upsertAppointmentTypeImpl(db, clinicId, uid, appointmentTypeId, isCreate, patch) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l;
    const colRef = db.collection("clinics").doc(clinicId).collection("appointmentTypes");
    const now = FV.serverTimestamp();
    if (isCreate) {
        const finalId = colRef.doc().id;
        const doc = {
            name: (_a = patch.name) !== null && _a !== void 0 ? _a : "",
            durationMinutes: (_b = patch.durationMinutes) !== null && _b !== void 0 ? _b : 30,
            colorHex: (_c = patch.colorHex) !== null && _c !== void 0 ? _c : null,
            active: (_d = patch.active) !== null && _d !== void 0 ? _d : true,
            showInOnlineBooking: (_e = patch.showInOnlineBooking) !== null && _e !== void 0 ? _e : false,
            description: (_f = patch.description) !== null && _f !== void 0 ? _f : null,
            defaultPrice: (_g = patch.defaultPrice) !== null && _g !== void 0 ? _g : null,
            allowedLocationIds: (_h = patch.allowedLocationIds) !== null && _h !== void 0 ? _h : null,
            telehealth: (_j = patch.telehealth) !== null && _j !== void 0 ? _j : false,
            allowedPractitionerIds: (_k = patch.allowedPractitionerIds) !== null && _k !== void 0 ? _k : null,
            createdAt: now,
            updatedAt: now,
        };
        await colRef.doc(finalId).set(doc);
        const changes = {};
        for (const [k, v] of Object.entries(doc)) {
            if (k !== "createdAt" && k !== "updatedAt")
                changes[k] = v;
        }
        await (0, audit_1.writeSettingsAuditEvent)(db, clinicId, "settings.appointmentType.created", uid, `clinics/${clinicId}/appointmentTypes/${finalId}`, finalId, changes);
        return { ok: true, appointmentTypeId: finalId };
    }
    const ref = colRef.doc(appointmentTypeId);
    const snap = await ref.get();
    if (!snap.exists) {
        throw new https_1.HttpsError("not-found", "Appointment type not found.");
    }
    const existing = (_l = snap.data()) !== null && _l !== void 0 ? _l : {};
    const updateData = { updatedAt: now };
    const changes = {};
    for (const key of Object.keys(patch)) {
        updateData[key] = patch[key];
        changes[key] = { before: existing[key], after: patch[key] };
    }
    await ref.update(updateData);
    await (0, audit_1.writeSettingsAuditEvent)(db, clinicId, "settings.appointmentType.updated", uid, `clinics/${clinicId}/appointmentTypes/${appointmentTypeId}`, appointmentTypeId, changes);
    return { ok: true, appointmentTypeId: appointmentTypeId };
}
//# sourceMappingURL=upsertAppointmentType.js.map