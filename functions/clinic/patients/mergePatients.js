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
exports.mergePatients = mergePatients;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const logger_1 = require("firebase-functions/logger");
const authz_1 = require("../authz");
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
}
function isEmptyValue(v) {
    if (v === null || v === undefined)
        return true;
    if (typeof v === "string")
        return v.trim().length === 0;
    return false;
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
function setNested(obj, path, value) {
    const parts = path.split(".");
    let cur = obj;
    for (let i = 0; i < parts.length - 1; i++) {
        const p = parts[i];
        if (!cur[p] || typeof cur[p] !== "object")
            cur[p] = {};
        cur = cur[p];
    }
    cur[parts[parts.length - 1]] = value;
}
function buildPatientDisplayName(patient) {
    var _a, _b;
    const fn = safeStr((_a = getNested(patient, "identity.firstName")) !== null && _a !== void 0 ? _a : patient.firstName);
    const ln = safeStr((_b = getNested(patient, "identity.lastName")) !== null && _b !== void 0 ? _b : patient.lastName);
    const full = `${fn} ${ln}`.trim();
    return full || safeStr(patient.fullName) || "";
}
function fillIfEmptyPatch(params) {
    const { target, source, fields } = params;
    const patch = {};
    for (const f of fields) {
        const t = getNested(target, f);
        if (!isEmptyValue(t))
            continue;
        const s = getNested(source, f);
        if (isEmptyValue(s))
            continue;
        setNested(patch, f, s);
    }
    return patch;
}
async function reassignRefs(params) {
    const { db, clinicId, sourcePatientId, targetPatientId, targetPatientName } = params;
    let updated = 0;
    const col = db.collection("clinics").doc(clinicId).collection("appointments");
    const pageSize = 400;
    while (true) {
        const snap = await col.where("patientId", "==", sourcePatientId).limit(pageSize).get();
        if (snap.empty)
            break;
        const batch = db.batch();
        for (const doc of snap.docs) {
            const update = {
                patientId: targetPatientId,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            };
            if (safeStr(targetPatientName))
                update.patientName = targetPatientName;
            batch.update(doc.ref, update);
            updated++;
        }
        await batch.commit();
        if (snap.size < pageSize)
            break;
    }
    return updated;
}
/**
 * Firestore transactions sometimes rethrow errors as plain objects.
 * This preserves the original callable error code/message if present.
 */
function throwIfHttpsErrorLike(err) {
    const code = err === null || err === void 0 ? void 0 : err.code;
    const message = err === null || err === void 0 ? void 0 : err.message;
    const details = err === null || err === void 0 ? void 0 : err.details;
    const allowed = new Set([
        "cancelled",
        "unknown",
        "invalid-argument",
        "deadline-exceeded",
        "not-found",
        "already-exists",
        "permission-denied",
        "resource-exhausted",
        "failed-precondition",
        "aborted",
        "out-of-range",
        "unimplemented",
        "internal",
        "unavailable",
        "data-loss",
        "unauthenticated",
    ]);
    if (typeof code === "string" && allowed.has(code) && typeof message === "string") {
        throw new https_1.HttpsError(code, message, details);
    }
    throw err;
}
async function mergePatients(req) {
    var _a, _b, _c, _d, _e;
    if (!req.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const clinicId = safeStr((_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId);
    const sourcePatientId = safeStr((_b = req.data) === null || _b === void 0 ? void 0 : _b.sourcePatientId);
    const targetPatientId = safeStr((_c = req.data) === null || _c === void 0 ? void 0 : _c.targetPatientId);
    if (!clinicId)
        throw new https_1.HttpsError("invalid-argument", "clinicId is required.");
    if (!sourcePatientId)
        throw new https_1.HttpsError("invalid-argument", "sourcePatientId is required.");
    if (!targetPatientId)
        throw new https_1.HttpsError("invalid-argument", "targetPatientId is required.");
    if (sourcePatientId === targetPatientId) {
        throw new https_1.HttpsError("invalid-argument", "sourcePatientId and targetPatientId must differ.");
    }
    const uid = req.auth.uid;
    const db = admin.firestore();
    await (0, authz_1.requireActiveMemberWithPerm)(db, clinicId, uid, "patients.write");
    const sourceRef = db.collection("clinics").doc(clinicId).collection("patients").doc(sourcePatientId);
    const targetRef = db.collection("clinics").doc(clinicId).collection("patients").doc(targetPatientId);
    const fillFields = [
        "identity.firstName",
        "identity.lastName",
        "identity.preferredName",
        "identity.dateOfBirth",
        "contact.email",
        "contact.phone",
        "contact.preferredMethod",
        "contact.address.line1",
        "contact.address.city",
        "contact.address.postcode",
        "contact.address.country",
        "emergencyContact.name",
        "emergencyContact.relationship",
        "emergencyContact.phone",
        "adminNotes",
    ];
    const legacyFillFields = ["firstName", "lastName", "dob", "email", "phone", "address"];
    try {
        const now = admin.firestore.FieldValue.serverTimestamp();
        const result = await db.runTransaction(async (tx) => {
            var _a, _b;
            const [sourceSnap, targetSnap] = await Promise.all([tx.get(sourceRef), tx.get(targetRef)]);
            if (!sourceSnap.exists) {
                throw new https_1.HttpsError("not-found", "Source patient not found.");
            }
            if (!targetSnap.exists) {
                throw new https_1.HttpsError("not-found", "Target patient not found.");
            }
            const source = ((_a = sourceSnap.data()) !== null && _a !== void 0 ? _a : {});
            const target = ((_b = targetSnap.data()) !== null && _b !== void 0 ? _b : {});
            const alreadyMergedInto = safeStr(source.mergedIntoPatientId);
            if (alreadyMergedInto) {
                throw new https_1.HttpsError("failed-precondition", `Source patient is already merged into ${alreadyMergedInto}.`);
            }
            const patch1 = fillIfEmptyPatch({ target, source, fields: fillFields });
            const patch2 = fillIfEmptyPatch({ target, source, fields: legacyFillFields });
            const targetTags = Array.isArray(target.tags) ? target.tags : [];
            const sourceTags = Array.isArray(source.tags) ? source.tags : [];
            const targetAlerts = Array.isArray(target.alerts) ? target.alerts : [];
            const sourceAlerts = Array.isArray(source.alerts) ? source.alerts : [];
            const tagPatch = {};
            if (targetTags.length === 0 && sourceTags.length > 0)
                tagPatch.tags = sourceTags;
            const alertPatch = {};
            if (targetAlerts.length === 0 && sourceAlerts.length > 0)
                alertPatch.alerts = sourceAlerts;
            const mergedTargetUpdate = {
                ...patch1,
                ...patch2,
                ...tagPatch,
                ...alertPatch,
                updatedAt: now,
                updatedByUid: uid,
                lastMergeAt: now,
                lastMergeFromPatientId: sourcePatientId,
            };
            tx.set(targetRef, mergedTargetUpdate, { merge: true });
            const sourceStatus = source.status && typeof source.status === "object" ? source.status : {};
            tx.set(sourceRef, {
                updatedAt: now,
                updatedByUid: uid,
                active: false,
                status: {
                    ...sourceStatus,
                    active: false,
                    archived: true,
                    archivedAt: now,
                },
                mergedIntoPatientId: targetPatientId,
                mergedAt: now,
                mergedByUid: uid,
            }, { merge: true });
            const mergedTargetSim = { ...target, ...mergedTargetUpdate };
            const targetPatientName = buildPatientDisplayName(mergedTargetSim);
            return { targetPatientName };
        });
        const updatedRefs = await reassignRefs({
            db,
            clinicId,
            sourcePatientId,
            targetPatientId,
            targetPatientName: result.targetPatientName,
        });
        logger_1.logger.info("mergePatients ok", {
            clinicId,
            sourcePatientId,
            targetPatientId,
            updatedRefs,
            uid,
        });
        return { ok: true, updatedRefs };
    }
    catch (err) {
        logger_1.logger.error("mergePatients failed", {
            clinicId,
            sourcePatientId,
            targetPatientId,
            uid,
            err: (_d = err === null || err === void 0 ? void 0 : err.message) !== null && _d !== void 0 ? _d : String(err),
            code: err === null || err === void 0 ? void 0 : err.code,
            stack: err === null || err === void 0 ? void 0 : err.stack,
            details: err === null || err === void 0 ? void 0 : err.details,
        });
        if (err instanceof https_1.HttpsError)
            throw err;
        // ✅ preserve HttpsError-like objects
        try {
            throwIfHttpsErrorLike(err);
        }
        catch (e) {
            if (e instanceof https_1.HttpsError)
                throw e;
        }
        throw new https_1.HttpsError("internal", "mergePatients crashed. Check logs.", {
            original: (_e = err === null || err === void 0 ? void 0 : err.message) !== null && _e !== void 0 ? _e : String(err),
        });
    }
}
//# sourceMappingURL=mergePatients.js.map