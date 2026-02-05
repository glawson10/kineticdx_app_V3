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
exports.createAppointment = createAppointment;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const firebase_functions_1 = require("firebase-functions");
const createAppointmentInternal_1 = require("./appointments/createAppointmentInternal");
function getBoolPerm(perms, key) {
    return typeof perms === "object" && perms !== null && perms[key] === true;
}
function requirePerm(perms, keys, message) {
    const ok = keys.some((k) => getBoolPerm(perms, k));
    if (!ok)
        throw new https_1.HttpsError("permission-denied", message);
}
function parseMillis(label, ms) {
    if (ms == null)
        return null;
    if (typeof ms !== "number" || !Number.isFinite(ms) || ms <= 0) {
        throw new https_1.HttpsError("invalid-argument", `Invalid ${label}Ms.`);
    }
    return new Date(ms);
}
function parseIso(label, value) {
    if (!value)
        return null;
    const d = new Date(value);
    if (Number.isNaN(d.getTime())) {
        throw new https_1.HttpsError("invalid-argument", `Invalid ${label}. Must be ISO8601 string.`);
    }
    return d;
}
async function getMembershipData(db, clinicId, uid) {
    var _a, _b;
    const canonical = db.collection("clinics").doc(clinicId).collection("memberships").doc(uid);
    const legacy = db.collection("clinics").doc(clinicId).collection("members").doc(uid);
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
        return true;
    return data.active === true;
}
async function createAppointment(req) {
    var _a, _b, _c, _d, _e;
    try {
        if (!req.auth)
            throw new https_1.HttpsError("unauthenticated", "Sign in required.");
        const data = ((_a = req.data) !== null && _a !== void 0 ? _a : {});
        const clinicId = ((_b = data.clinicId) !== null && _b !== void 0 ? _b : "").toString().trim();
        const kind = data.kind === "admin" || data.kind === "new" || data.kind === "followup"
            ? data.kind
            : "followup";
        if (!clinicId)
            throw new https_1.HttpsError("invalid-argument", "clinicId is required.");
        // ─────────────────────────────
        // Time parsing (prefer millis)
        // ─────────────────────────────
        const startMsProvided = data.startMs != null;
        const endMsProvided = data.endMs != null;
        const startIsoProvided = data.start != null;
        const endIsoProvided = data.end != null;
        const anyTimeProvided = startMsProvided || endMsProvided || startIsoProvided || endIsoProvided;
        if (!anyTimeProvided) {
            throw new https_1.HttpsError("invalid-argument", "startMs/endMs (or start/end) are required.");
        }
        let startDt = null;
        let endDt = null;
        if (startMsProvided || endMsProvided) {
            if (startMsProvided !== endMsProvided) {
                throw new https_1.HttpsError("invalid-argument", "Provide both startMs and endMs.");
            }
            startDt = parseMillis("start", data.startMs);
            endDt = parseMillis("end", data.endMs);
        }
        else {
            if (startIsoProvided !== endIsoProvided) {
                throw new https_1.HttpsError("invalid-argument", "Provide both start and end.");
            }
            startDt = parseIso("start", data.start);
            endDt = parseIso("end", data.end);
        }
        if (!startDt || !endDt)
            throw new https_1.HttpsError("invalid-argument", "Invalid start/end.");
        if (endDt <= startDt) {
            throw new https_1.HttpsError("invalid-argument", "Invalid start/end (end must be after start).");
        }
        const db = admin.firestore();
        const uid = req.auth.uid;
        // ─────────────────────────────
        // Membership + permissions (canonical)
        // ─────────────────────────────
        const member = await getMembershipData(db, clinicId, uid);
        if (!member || !isActiveMember(member)) {
            throw new https_1.HttpsError("permission-denied", "Not an active clinic member.");
        }
        const perms = (_c = member.permissions) !== null && _c !== void 0 ? _c : {};
        const allowClosedOverride = data.allowClosedOverride === true;
        if (allowClosedOverride) {
            requirePerm(perms, ["settings.write"], "No permission to override clinic closures (settings.write required).");
        }
        else {
            requirePerm(perms, ["schedule.read"], "No schedule access (schedule.read required).");
            requirePerm(perms, ["schedule.write", "schedule.manage"], "No scheduling permission (schedule.write required).");
        }
        if (kind !== "admin") {
            requirePerm(perms, ["patients.read"], "No patient access (patients.read required).");
        }
        return await (0, createAppointmentInternal_1.createAppointmentInternal)(db, {
            clinicId,
            kind,
            patientId: data.patientId,
            serviceId: data.serviceId,
            practitionerId: data.practitionerId,
            startDt,
            endDt,
            resourceIds: data.resourceIds,
            actorUid: uid,
            allowClosedOverride,
        });
    }
    catch (err) {
        firebase_functions_1.logger.error("createAppointment failed", {
            err: (_d = err === null || err === void 0 ? void 0 : err.message) !== null && _d !== void 0 ? _d : String(err),
            stack: err === null || err === void 0 ? void 0 : err.stack,
            code: err === null || err === void 0 ? void 0 : err.code,
            details: err === null || err === void 0 ? void 0 : err.details,
        });
        if (err instanceof https_1.HttpsError)
            throw err;
        throw new https_1.HttpsError("internal", "createAppointment crashed. Check function logs.", {
            original: (_e = err === null || err === void 0 ? void 0 : err.message) !== null && _e !== void 0 ? _e : String(err),
        });
    }
}
//# sourceMappingURL=createAppointment.js.map