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
exports.createAppointmentInternal = createAppointmentInternal;
// functions/src/clinic/appointments/createAppointmentInternal.ts
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const logger_1 = require("firebase-functions/logger");
function safeString(v) {
    return typeof v === "string" ? v.trim() : "";
}
function isNonEmptyString(v) {
    return typeof v === "string" && v.trim().length > 0;
}
function uniqStrings(arr) {
    if (!Array.isArray(arr))
        return [];
    const out = arr
        .filter((x) => typeof x === "string")
        .map((x) => x.trim())
        .filter((x) => x.length > 0);
    return Array.from(new Set(out));
}
function getNested(obj, path) {
    const parts = path.split(".");
    let cur = obj;
    for (const p of parts) {
        if (!cur || typeof cur !== "object")
            return undefined;
        cur = cur[p];
    }
    return cur;
}
function buildFullName(first, last) {
    return [safeString(first), safeString(last)].filter(Boolean).join(" ").trim();
}
async function assertNoClosureOverlap(params) {
    const { db, clinicId, startAt, endAt } = params;
    const snap = await db
        .collection(`clinics/${clinicId}/closures`)
        .where("active", "==", true)
        .where("fromAt", "<", endAt)
        .get();
    for (const doc of snap.docs) {
        const data = doc.data();
        const fromAt = data === null || data === void 0 ? void 0 : data.fromAt;
        const toAt = data === null || data === void 0 ? void 0 : data.toAt;
        if (!fromAt || !toAt)
            continue;
        const overlaps = startAt.toMillis() < toAt.toMillis() && endAt.toMillis() > fromAt.toMillis();
        if (overlaps) {
            throw new https_1.HttpsError("failed-precondition", "Appointment overlaps a clinic closure.", {
                closureId: doc.id,
            });
        }
    }
}
async function readPractitionerDoc(db, clinicId, practitionerId) {
    var _a;
    const candidates = [
        `clinics/${clinicId}/memberships/${practitionerId}`, // ✅ canonical first
        `clinics/${clinicId}/members/${practitionerId}`, // legacy fallback
        `clinics/${clinicId}/practitioners/${practitionerId}`,
        `clinics/${clinicId}/staff/${practitionerId}`,
    ];
    for (const path of candidates) {
        const snap = await db.doc(path).get();
        if (!snap.exists)
            continue;
        const d = ((_a = snap.data()) !== null && _a !== void 0 ? _a : {});
        const active = d.active === true ||
            d.status === "active" ||
            getNested(d, "status.active") === true;
        return { data: d, active };
    }
    return { data: null, active: false };
}
/**
 * Returns { name, source } where source is useful for debugging.
 */
function resolvePatientName(patientDoc) {
    const fnNested = safeString(getNested(patientDoc, "identity.firstName"));
    const lnNested = safeString(getNested(patientDoc, "identity.lastName"));
    const fullNested = buildFullName(fnNested, lnNested);
    if (fullNested)
        return { name: fullNested, source: "identity.firstName+identity.lastName" };
    const fn = safeString(patientDoc.firstName);
    const ln = safeString(patientDoc.lastName);
    const fullLegacy = buildFullName(fn, ln);
    if (fullLegacy)
        return { name: fullLegacy, source: "firstName+lastName" };
    const fullName = safeString(patientDoc.fullName);
    if (fullName)
        return { name: fullName, source: "fullName" };
    return { name: "", source: "none" };
}
async function createAppointmentInternal(db, input) {
    var _a, _b, _c;
    const clinicId = input.clinicId.trim();
    const kind = input.kind;
    const actorUid = input.actorUid;
    if (!clinicId)
        throw new https_1.HttpsError("invalid-argument", "clinicId is required.");
    if (!(input.startDt instanceof Date) || Number.isNaN(input.startDt.getTime())) {
        throw new https_1.HttpsError("invalid-argument", "Invalid start time.");
    }
    if (!(input.endDt instanceof Date) || Number.isNaN(input.endDt.getTime())) {
        throw new https_1.HttpsError("invalid-argument", "Invalid end time.");
    }
    if (input.endDt <= input.startDt) {
        throw new https_1.HttpsError("invalid-argument", "Invalid start/end (end must be after start).");
    }
    const startTs = admin.firestore.Timestamp.fromDate(input.startDt);
    const endTs = admin.firestore.Timestamp.fromDate(input.endDt);
    if (input.allowClosedOverride !== true) {
        await assertNoClosureOverlap({ db, clinicId, startAt: startTs, endAt: endTs });
    }
    let patientId = "";
    let serviceId = "";
    let practitionerId = "";
    let patientName = "";
    let patientNameSource = "";
    let serviceName = "";
    let practitionerName = "";
    if (kind !== "admin") {
        if (!isNonEmptyString(input.patientId) ||
            !isNonEmptyString(input.serviceId) ||
            !isNonEmptyString(input.practitionerId)) {
            throw new https_1.HttpsError("invalid-argument", "patientId, serviceId, practitionerId are required for patient bookings.");
        }
        patientId = input.patientId.trim();
        serviceId = input.serviceId.trim();
        practitionerId = input.practitionerId.trim();
        // Practitioner must be active
        const pracResult = await readPractitionerDoc(db, clinicId, practitionerId);
        if (!pracResult.data || pracResult.active !== true) {
            throw new https_1.HttpsError("failed-precondition", "Selected practitioner is not an active clinic member.");
        }
        // ✅ Patient must exist (do not silently proceed)
        const patientRef = db
            .collection("clinics")
            .doc(clinicId)
            .collection("patients")
            .doc(patientId);
        const patientSnap = await patientRef.get();
        if (!patientSnap.exists) {
            logger_1.logger.warn("createAppointmentInternal: patient not found", {
                clinicId,
                patientId,
                actorUid,
            });
            throw new https_1.HttpsError("failed-precondition", "Selected patient was not found in this clinic.");
        }
        const p = ((_a = patientSnap.data()) !== null && _a !== void 0 ? _a : {});
        const resolved = resolvePatientName(p);
        patientName = resolved.name;
        patientNameSource = resolved.source;
        // ✅ Patient name must be resolvable (prevents UI showing “someone else” via details line)
        if (!patientName.trim()) {
            logger_1.logger.warn("createAppointmentInternal: patient name missing/unresolvable", {
                clinicId,
                patientId,
                actorUid,
                patientNameSource,
                patientDocKeys: Object.keys(p || {}),
            });
            throw new https_1.HttpsError("failed-precondition", "Patient record is missing a name (firstName/lastName).");
        }
        // Service
        const serviceRef = db
            .collection("clinics")
            .doc(clinicId)
            .collection("services")
            .doc(serviceId);
        const serviceSnap = await serviceRef.get();
        if (serviceSnap.exists) {
            const s = (_b = serviceSnap.data()) !== null && _b !== void 0 ? _b : {};
            serviceName = safeString(s.name);
        }
        if (!serviceName)
            serviceName = safeString(input.serviceNameFallback) || serviceId;
        // Practitioner display name
        const prac = (_c = pracResult.data) !== null && _c !== void 0 ? _c : {};
        practitionerName =
            safeString(prac.displayName) || safeString(prac.name) || practitionerId;
        logger_1.logger.info("createAppointmentInternal: resolved denorm fields", {
            clinicId,
            kind,
            patientId,
            patientName,
            patientNameSource,
            serviceId,
            serviceName,
            practitionerId,
            practitionerName,
            actorUid,
        });
    }
    const apptRef = db.collection("clinics").doc(clinicId).collection("appointments").doc();
    const resourceIds = uniqStrings(input.resourceIds);
    await apptRef.set({
        clinicId,
        kind,
        patientId: kind === "admin" ? "" : patientId,
        serviceId: kind === "admin" ? "" : serviceId,
        practitionerId: kind === "admin" ? "" : practitionerId,
        patientName: kind === "admin" ? "" : patientName,
        patientNameSource: kind === "admin" ? "" : patientNameSource, // helpful while debugging
        serviceName: kind === "admin" ? "" : serviceName,
        practitionerName: kind === "admin" ? "" : practitionerName,
        resourceIds,
        startAt: startTs,
        endAt: endTs,
        // legacy mirrors
        start: startTs,
        end: endTs,
        status: "booked",
        createdByUid: actorUid,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedByUid: actorUid,
    });
    return { success: true, appointmentId: apptRef.id };
}
//# sourceMappingURL=createAppointmentInternal.js.map