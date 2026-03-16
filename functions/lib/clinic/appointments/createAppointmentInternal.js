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
/** Safely get milliseconds from a Firestore Timestamp (or legacy { _seconds, _nanoseconds }). */
function toMillisSafe(ts) {
    var _a, _b, _c;
    if (ts == null)
        return null;
    if (typeof ts.toMillis === "function")
        return ts.toMillis();
    const sec = (_a = ts._seconds) !== null && _a !== void 0 ? _a : ts.seconds;
    const nan = (_c = (_b = ts._nanoseconds) !== null && _b !== void 0 ? _b : ts.nanoseconds) !== null && _c !== void 0 ? _c : 0;
    if (typeof sec === "number" && Number.isFinite(sec))
        return sec * 1000 + nan / 1e6;
    return null;
}
async function assertNoClosureOverlap(params) {
    var _a, _b, _c, _d;
    const { db, clinicId, startAt, endAt } = params;
    const startMs = (_b = (_a = startAt.toMillis) === null || _a === void 0 ? void 0 : _a.call(startAt)) !== null && _b !== void 0 ? _b : null;
    const endMs = (_d = (_c = endAt.toMillis) === null || _c === void 0 ? void 0 : _c.call(endAt)) !== null && _d !== void 0 ? _d : null;
    if (startMs == null || endMs == null)
        return;
    const snap = await db
        .collection(`clinics/${clinicId}/closures`)
        .where("active", "==", true)
        .where("fromAt", "<", endAt)
        .get();
    for (const doc of snap.docs) {
        const data = doc.data();
        const fromAt = data === null || data === void 0 ? void 0 : data.fromAt;
        const toAt = data === null || data === void 0 ? void 0 : data.toAt;
        const fromMs = toMillisSafe(fromAt);
        const toMs = toMillisSafe(toAt);
        if (fromMs == null || toMs == null)
            continue;
        const overlaps = startMs < toMs && endMs > fromMs;
        if (overlaps) {
            throw new https_1.HttpsError("failed-precondition", "Appointment overlaps a clinic closure.", {
                closureId: doc.id,
            });
        }
    }
}
async function readPractitionerDoc(db, clinicId, practitionerId) {
    var _a, _b;
    const candidates = [
        `clinics/${clinicId}/memberships/${practitionerId}`,
        `clinics/${clinicId}/members/${practitionerId}`,
        `clinics/${clinicId}/practitioners/${practitionerId}`,
        `clinics/${clinicId}/staff/${practitionerId}`,
    ];
    let memberData = null;
    let active = false;
    for (const path of candidates) {
        const snap = await db.doc(path).get();
        if (!snap.exists)
            continue;
        const d = ((_a = snap.data()) !== null && _a !== void 0 ? _a : {});
        active =
            d.active === true ||
                d.status === "active" ||
                getNested(d, "status.active") === true;
        memberData = d;
        break;
    }
    // Also read the practitioners doc for booking metadata
    let bookingMeta = null;
    const pracSnap = await db
        .doc(`clinics/${clinicId}/practitioners/${practitionerId}`)
        .get();
    if (pracSnap.exists) {
        bookingMeta = ((_b = pracSnap.data()) !== null && _b !== void 0 ? _b : {});
    }
    return { data: memberData, active, bookingMeta };
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
function toDateSafe(v) {
    if (v instanceof Date && !Number.isNaN(v.getTime()))
        return v;
    if (v && typeof v.toDate === "function")
        return v.toDate();
    if (v != null && typeof v === "object" && "seconds" in v) {
        const s = v.seconds;
        if (typeof s === "number" && Number.isFinite(s))
            return new Date(s * 1000);
    }
    if (typeof v === "number" && Number.isFinite(v))
        return new Date(v);
    return null;
}
async function createAppointmentInternal(db, input) {
    var _a;
    try {
        return await createAppointmentInternalImpl(db, input);
    }
    catch (err) {
        if (err instanceof https_1.HttpsError)
            throw err;
        const msg = (_a = err === null || err === void 0 ? void 0 : err.message) !== null && _a !== void 0 ? _a : String(err);
        logger_1.logger.error("createAppointmentInternal unexpected error", {
            kind: input.kind,
            err: msg,
            stack: err === null || err === void 0 ? void 0 : err.stack,
        });
        throw new https_1.HttpsError("internal", msg || "Create appointment failed.", {
            original: msg,
        });
    }
}
async function createAppointmentInternalImpl(db, input) {
    var _a, _b, _c, _d, _e;
    const clinicId = input.clinicId.trim();
    const kind = input.kind;
    const actorUid = input.actorUid;
    if (!clinicId)
        throw new https_1.HttpsError("invalid-argument", "clinicId is required.");
    const startDt = toDateSafe(input.startDt);
    const endDt = toDateSafe(input.endDt);
    if (!startDt || !endDt) {
        throw new https_1.HttpsError("invalid-argument", "Invalid start or end time.");
    }
    if (endDt <= startDt) {
        throw new https_1.HttpsError("invalid-argument", "Invalid start/end (end must be after start).");
    }
    const startTs = admin.firestore.Timestamp.fromDate(startDt);
    const endTs = admin.firestore.Timestamp.fromDate(endDt);
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
        // Booking eligibility checks (from practitioners/{uid} doc)
        const bmeta = pracResult.bookingMeta;
        if (bmeta) {
            if (bmeta.activeForBooking === false) {
                throw new https_1.HttpsError("failed-precondition", "Selected practitioner is not available for booking.");
            }
            const allowedServices = Array.isArray(bmeta.serviceIdsAllowed)
                ? bmeta.serviceIdsAllowed.filter((x) => typeof x === "string" && x.trim())
                : [];
            if (allowedServices.length > 0 && !allowedServices.includes(serviceId)) {
                throw new https_1.HttpsError("failed-precondition", "Selected practitioner cannot provide this appointment type.");
            }
            const allowedLocations = Array.isArray(bmeta.allowedLocationIds)
                ? bmeta.allowedLocationIds.filter((x) => typeof x === "string" && x.trim())
                : [];
            const locId = safeString(input.locationId);
            if (allowedLocations.length > 0 && locId && !allowedLocations.includes(locId)) {
                throw new https_1.HttpsError("failed-precondition", "Selected practitioner does not work at this location.");
            }
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
    const payload = {
        clinicId,
        kind,
        patientId: kind === "admin" ? "" : patientId,
        serviceId: kind === "admin" ? "" : serviceId,
        practitionerId: kind === "admin" ? "" : practitionerId,
        ...(input.locationId && input.locationId.trim()
            ? { locationId: input.locationId.trim() }
            : {}),
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
    };
    // Commit 47: Overlap check and write in one transaction so two concurrent requests cannot double-book.
    if (kind !== "admin" && practitionerId) {
        const col = db.collection(`clinics/${clinicId}/appointments`);
        await db.runTransaction(async (tx) => {
            var _a, _b, _c;
            const query = col
                .where("practitionerId", "==", practitionerId)
                .where("endAt", ">", startTs);
            const snap = await tx.get(query);
            const startMs = startTs.toMillis();
            const endMs = endTs.toMillis();
            for (const doc of snap.docs) {
                const data = doc.data();
                const status = ((_a = data === null || data === void 0 ? void 0 : data.status) !== null && _a !== void 0 ? _a : "").toString().toLowerCase();
                if (status === "cancelled")
                    continue;
                const sMs = toMillisSafe((_b = data === null || data === void 0 ? void 0 : data.startAt) !== null && _b !== void 0 ? _b : data === null || data === void 0 ? void 0 : data.start);
                const eMs = toMillisSafe((_c = data === null || data === void 0 ? void 0 : data.endAt) !== null && _c !== void 0 ? _c : data === null || data === void 0 ? void 0 : data.end);
                if (sMs == null || eMs == null)
                    continue;
                if (sMs < endMs && eMs > startMs) {
                    throw new https_1.HttpsError("failed-precondition", "slot_no_longer_available");
                }
            }
            tx.set(apptRef, payload);
        });
    }
    else {
        try {
            await apptRef.set(payload);
        }
        catch (err) {
            logger_1.logger.error("createAppointmentInternal: apptRef.set failed", {
                clinicId,
                kind,
                err: (_d = err === null || err === void 0 ? void 0 : err.message) !== null && _d !== void 0 ? _d : String(err),
                stack: err === null || err === void 0 ? void 0 : err.stack,
            });
            throw new https_1.HttpsError("internal", (_e = err === null || err === void 0 ? void 0 : err.message) !== null && _e !== void 0 ? _e : "Failed to write appointment.", { original: err === null || err === void 0 ? void 0 : err.message });
        }
    }
    return { success: true, appointmentId: apptRef.id };
}
//# sourceMappingURL=createAppointmentInternal.js.map