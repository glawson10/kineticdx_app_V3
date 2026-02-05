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
exports.bootstrapPublicBookingSettings = bootstrapPublicBookingSettings;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const writePublicBookingMirror_1 = require("./writePublicBookingMirror");
function safeStr(v) {
    return typeof v === "string" ? v.trim() : "";
}
function asString(v, maxLen) {
    if (typeof v !== "string")
        return undefined;
    const s = v.trim();
    if (!s)
        return undefined;
    return s.length > maxLen ? s.slice(0, maxLen) : s;
}
async function getMembershipData(db, clinicId, uid) {
    var _a, _b;
    const canonical = db.doc(`clinics/${clinicId}/memberships/${uid}`);
    const legacy = db.doc(`clinics/${clinicId}/members/${uid}`);
    const c = await canonical.get();
    if (c.exists)
        return (_a = c.data()) !== null && _a !== void 0 ? _a : {};
    const l = await legacy.get();
    if (l.exists)
        return (_b = l.data()) !== null && _b !== void 0 ? _b : {};
    return null;
}
function isActiveMember(data) {
    var _a;
    const status = ((_a = data.status) !== null && _a !== void 0 ? _a : "").toString().toLowerCase().trim();
    if (status === "suspended" || status === "invited")
        return false;
    if (!("active" in data))
        return true; // back-compat
    return data.active === true;
}
async function bootstrapPublicBookingSettings(req) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q, _r;
    if (!((_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid))
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const clinicId = safeStr((_b = req.data) === null || _b === void 0 ? void 0 : _b.clinicId);
    if (!clinicId)
        throw new https_1.HttpsError("invalid-argument", "clinicId is required.");
    const overrideBaseUrl = asString((_c = req.data) === null || _c === void 0 ? void 0 : _c.publicActionBaseUrl, 500);
    const db = admin.firestore();
    const uid = req.auth.uid;
    // ─────────────────────────────
    // Membership + permission gate
    // ─────────────────────────────
    const member = await getMembershipData(db, clinicId, uid);
    if (!member || !isActiveMember(member)) {
        throw new https_1.HttpsError("permission-denied", "Inactive or missing membership.");
    }
    if (((_d = member.permissions) === null || _d === void 0 ? void 0 : _d["settings.write"]) !== true) {
        throw new https_1.HttpsError("permission-denied", "Missing settings.write permission.");
    }
    // ─────────────────────────────
    // Clinic existence + metadata
    // ─────────────────────────────
    const clinicRef = db.doc(`clinics/${clinicId}`);
    const clinicSnap = await clinicRef.get();
    if (!clinicSnap.exists)
        throw new https_1.HttpsError("not-found", "Clinic not found.");
    const clinic = ((_e = clinicSnap.data()) !== null && _e !== void 0 ? _e : {});
    const clinicName = safeStr((_f = clinic === null || clinic === void 0 ? void 0 : clinic.profile) === null || _f === void 0 ? void 0 : _f.name) ||
        safeStr(clinic === null || clinic === void 0 ? void 0 : clinic.clinicName) ||
        safeStr(clinic === null || clinic === void 0 ? void 0 : clinic.name) ||
        "";
    const logoUrl = safeStr((_g = clinic === null || clinic === void 0 ? void 0 : clinic.profile) === null || _g === void 0 ? void 0 : _g.logoUrl) ||
        safeStr(clinic === null || clinic === void 0 ? void 0 : clinic.logoUrl) ||
        "";
    const tzFromClinic = safeStr((_h = clinic === null || clinic === void 0 ? void 0 : clinic.profile) === null || _h === void 0 ? void 0 : _h.timezone) ||
        safeStr((_j = clinic === null || clinic === void 0 ? void 0 : clinic.settings) === null || _j === void 0 ? void 0 : _j.timezone) ||
        "Europe/Prague";
    const minNoticeFromClinic = typeof ((_l = (_k = clinic === null || clinic === void 0 ? void 0 : clinic.settings) === null || _k === void 0 ? void 0 : _k.bookingRules) === null || _l === void 0 ? void 0 : _l.minNoticeMinutes) === "number"
        ? clinic.settings.bookingRules.minNoticeMinutes
        : 0;
    const maxAdvanceFromClinic = typeof ((_o = (_m = clinic === null || clinic === void 0 ? void 0 : clinic.settings) === null || _m === void 0 ? void 0 : _m.bookingRules) === null || _o === void 0 ? void 0 : _o.maxDaysInAdvance) === "number"
        ? clinic.settings.bookingRules.maxDaysInAdvance
        : 90;
    // ─────────────────────────────
    // Canonical defaults
    // ─────────────────────────────
    const defaults = {
        timezone: tzFromClinic,
        minNoticeMinutes: minNoticeFromClinic,
        maxAdvanceDays: maxAdvanceFromClinic,
        slotStepMinutes: 15,
        weeklyHours: {
            mon: [{ start: "08:00", end: "18:00" }],
            tue: [{ start: "08:00", end: "18:00" }],
            wed: [{ start: "08:00", end: "18:00" }],
            thu: [{ start: "08:00", end: "18:00" }],
            fri: [{ start: "08:00", end: "16:00" }],
            sat: [],
            sun: [],
        },
        corporatePrograms: [],
        publicServiceNames: {},
        // PRIVATE (not mirrored)
        emails: {
            publicActionBaseUrl: overrideBaseUrl !== null && overrideBaseUrl !== void 0 ? overrideBaseUrl : "https://example.com/public/booking/manage",
            brevo: {
                senderName: clinicName,
                senderEmail: "",
                patientTemplateId: null,
                clinicianTemplateId: null,
                manageBookingTemplateId: null,
            },
            clinicianRecipients: [],
        },
        // SAFE (mirrored)
        patientCopy: {
            whatsappLine: "",
            whatToBring: "",
            arrivalInfo: "",
            cancellationPolicy: "",
            cancellationUrl: "",
        },
        bookingStructure: {
            publicSlotMinutes: 60,
        },
        schemaVersion: 1,
    };
    const settingsRef = db
        .collection("clinics")
        .doc(clinicId)
        .collection("settings")
        .doc("publicBooking");
    const settingsSnap = await settingsRef.get();
    const now = admin.firestore.FieldValue.serverTimestamp();
    // ─────────────────────────────
    // CREATE
    // ─────────────────────────────
    if (!settingsSnap.exists) {
        await settingsRef.set({
            ...defaults,
            createdAt: now,
            createdByUid: uid,
            updatedAt: now,
            updatedByUid: uid,
        });
        await (0, writePublicBookingMirror_1.writePublicBookingMirror)(clinicId, defaults);
        return {
            ok: true,
            created: true,
            merged: false,
            path: settingsRef.path,
            publicPath: `clinics/${clinicId}/public/config/publicBooking/publicBooking`,
        };
    }
    // ─────────────────────────────
    // MERGE MISSING FIELDS
    // ─────────────────────────────
    const cur = ((_p = settingsSnap.data()) !== null && _p !== void 0 ? _p : {});
    const patch = {};
    if (cur.timezone == null)
        patch.timezone = defaults.timezone;
    if (cur.minNoticeMinutes == null)
        patch.minNoticeMinutes = defaults.minNoticeMinutes;
    if (cur.maxAdvanceDays == null)
        patch.maxAdvanceDays = defaults.maxAdvanceDays;
    if (cur.slotStepMinutes == null)
        patch.slotStepMinutes = defaults.slotStepMinutes;
    if (cur.weeklyHours == null) {
        patch.weeklyHours = defaults.weeklyHours;
    }
    else {
        const whPatch = {};
        for (const d of ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]) {
            if (cur.weeklyHours[d] == null)
                whPatch[d] = defaults.weeklyHours[d];
        }
        if (Object.keys(whPatch).length) {
            patch.weeklyHours = { ...cur.weeklyHours, ...whPatch };
        }
    }
    if (cur.corporatePrograms == null)
        patch.corporatePrograms = [];
    if (cur.publicServiceNames == null)
        patch.publicServiceNames = {};
    if (cur.bookingStructure == null) {
        patch.bookingStructure = defaults.bookingStructure;
    }
    else if (cur.bookingStructure.publicSlotMinutes == null) {
        patch.bookingStructure = {
            ...cur.bookingStructure,
            publicSlotMinutes: 60,
        };
    }
    if (cur.emails == null)
        patch.emails = defaults.emails;
    if (cur.patientCopy == null)
        patch.patientCopy = defaults.patientCopy;
    patch.schemaVersion = (_q = cur.schemaVersion) !== null && _q !== void 0 ? _q : 1;
    patch.updatedAt = now;
    patch.updatedByUid = uid;
    const meaningful = Object.keys(patch).filter((k) => !["schemaVersion", "updatedAt", "updatedByUid"].includes(k));
    if (meaningful.length) {
        await settingsRef.set(patch, { merge: true });
    }
    const latestSnap = await settingsRef.get();
    await (0, writePublicBookingMirror_1.writePublicBookingMirror)(clinicId, (_r = latestSnap.data()) !== null && _r !== void 0 ? _r : {});
    return {
        ok: true,
        created: false,
        merged: meaningful.length > 0,
        path: settingsRef.path,
        publicPath: `clinics/${clinicId}/public/config/publicBooking/publicBooking`,
    };
}
//# sourceMappingURL=bootstrapPublicBookingSettings.js.map