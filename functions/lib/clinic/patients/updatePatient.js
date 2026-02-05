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
exports.updatePatient = updatePatient;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
}
function normalizeEmail(v) {
    const s = safeStr(v);
    return s ? s.toLowerCase() : "";
}
function readBoolOrUndefined(v) {
    if (v === true)
        return true;
    if (v === false)
        return false;
    return undefined;
}
function isMemberActiveLike(data) {
    const status = safeStr(data.status);
    if (status === "suspended")
        return false;
    if (status === "invited")
        return false;
    const active = readBoolOrUndefined(data.active);
    if (active !== undefined)
        return active;
    return true; // missing active => active
}
function getPermissionsMap(data) {
    const p = data.permissions;
    if (p && typeof p === "object")
        return p;
    return {};
}
async function getMembershipDataWithFallback(db, clinicId, uid) {
    const canonRef = db.collection("clinics").doc(clinicId).collection("memberships").doc(uid);
    const canonSnap = await canonRef.get();
    if (canonSnap.exists)
        return (canonSnap.data() || {});
    const legacyRef = db.collection("clinics").doc(clinicId).collection("members").doc(uid);
    const legacySnap = await legacyRef.get();
    if (legacySnap.exists)
        return (legacySnap.data() || {});
    return null;
}
async function assertPatientWritePerm(db, clinicId, uid) {
    const data = await getMembershipDataWithFallback(db, clinicId, uid);
    if (!data)
        throw new https_1.HttpsError("permission-denied", "Not a clinic member.");
    if (!isMemberActiveLike(data)) {
        throw new https_1.HttpsError("permission-denied", "Membership not active.");
    }
    const perms = getPermissionsMap(data);
    if (perms["patients.write"] !== true) {
        throw new https_1.HttpsError("permission-denied", "No patient write permission.");
    }
}
function parseDobToTimestampOrNull(dobIsoOrNull) {
    if (dobIsoOrNull === undefined)
        return undefined; // not provided
    if (dobIsoOrNull === null)
        return null;
    const raw = safeStr(dobIsoOrNull);
    if (!raw)
        return null;
    const d = new Date(raw);
    if (Number.isNaN(d.getTime()))
        throw new https_1.HttpsError("invalid-argument", "Invalid dateOfBirth.");
    // Keep exact timestamp semantics for update (you can day-normalize if you prefer)
    return admin.firestore.Timestamp.fromDate(d);
}
async function updatePatient(req) {
    var _a, _b, _c, _d;
    if (!req.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const clinicId = safeStr((_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId);
    const patientId = safeStr((_b = req.data) === null || _b === void 0 ? void 0 : _b.patientId);
    if (!clinicId || !patientId) {
        throw new https_1.HttpsError("invalid-argument", "clinicId and patientId required.");
    }
    const db = admin.firestore();
    const uid = req.auth.uid;
    await assertPatientWritePerm(db, clinicId, uid);
    const patientRef = db.collection("clinics").doc(clinicId).collection("patients").doc(patientId);
    const snap = await patientRef.get();
    if (!snap.exists)
        throw new https_1.HttpsError("not-found", "Patient not found.");
    const patch = {};
    const setIf = (path, value) => {
        if (value !== undefined)
            patch[path] = value;
    };
    // Identity
    if (req.data.firstName !== undefined) {
        const v = safeStr(req.data.firstName);
        setIf("identity.firstName", v);
        setIf("firstName", v); // legacy mirror
    }
    if (req.data.lastName !== undefined) {
        const v = safeStr(req.data.lastName);
        setIf("identity.lastName", v);
        setIf("lastName", v); // legacy mirror
    }
    setIf("identity.preferredName", req.data.preferredName === undefined
        ? undefined
        : ((_d = (_c = req.data.preferredName) === null || _c === void 0 ? void 0 : _c.toString().trim()) !== null && _d !== void 0 ? _d : null));
    const dobTs = parseDobToTimestampOrNull(req.data.dateOfBirth);
    if (dobTs !== undefined) {
        setIf("identity.dateOfBirth", dobTs);
        setIf("dob", dobTs); // legacy mirror
    }
    // Contact
    if (req.data.email !== undefined) {
        const e = req.data.email === null ? null : normalizeEmail(req.data.email);
        setIf("contact.email", e);
        setIf("email", e); // legacy mirror
    }
    if (req.data.phone !== undefined) {
        const p = req.data.phone === null ? null : safeStr(req.data.phone);
        setIf("contact.phone", p);
        setIf("phone", p); // legacy mirror
    }
    setIf("contact.preferredMethod", req.data.preferredMethod);
    // Address (partial)
    if (req.data.address !== undefined) {
        const a = req.data.address;
        if (a === null) {
            patch["contact.address"] = null;
        }
        else {
            setIf("contact.address.line1", a.line1 === undefined ? undefined : a.line1);
            setIf("contact.address.line2", a.line2 === undefined ? undefined : a.line2);
            setIf("contact.address.city", a.city === undefined ? undefined : a.city);
            setIf("contact.address.postcode", a.postcode === undefined ? undefined : a.postcode);
            setIf("contact.address.country", a.country === undefined ? undefined : a.country);
        }
    }
    // Emergency contact (partial)
    if (req.data.emergencyContact !== undefined) {
        const e = req.data.emergencyContact;
        if (e === null) {
            patch["emergencyContact"] = null;
        }
        else {
            setIf("emergencyContact.name", e.name === undefined ? undefined : e.name);
            setIf("emergencyContact.relationship", e.relationship === undefined ? undefined : e.relationship);
            setIf("emergencyContact.phone", e.phone === undefined ? undefined : e.phone);
        }
    }
    // Workflow/admin
    if (req.data.tags !== undefined)
        patch["tags"] = req.data.tags.map((t) => String(t));
    if (req.data.alerts !== undefined)
        patch["alerts"] = req.data.alerts.map((t) => String(t));
    if (req.data.adminNotes !== undefined)
        patch["adminNotes"] = req.data.adminNotes;
    // Status
    if (req.data.active !== undefined) {
        patch["status.active"] = req.data.active;
        patch["active"] = req.data.active; // legacy mirror
    }
    if (req.data.archived !== undefined) {
        patch["status.archived"] = req.data.archived;
        patch["status.archivedAt"] = req.data.archived
            ? admin.firestore.FieldValue.serverTimestamp()
            : null;
        // legacy mirror
        patch["archived"] = req.data.archived;
        patch["archivedAt"] = req.data.archived
            ? admin.firestore.FieldValue.serverTimestamp()
            : null;
    }
    // System
    patch["updatedAt"] = admin.firestore.FieldValue.serverTimestamp();
    patch["updatedByUid"] = uid;
    // Prevent empty update (Firestore rejects update({}) and it's also pointless)
    if (Object.keys(patch).length <= 2) {
        // updatedAt + updatedByUid only
        throw new https_1.HttpsError("invalid-argument", "No fields to update.");
    }
    await patientRef.update(patch);
    return { ok: true };
}
//# sourceMappingURL=updatePatient.js.map