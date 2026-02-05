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
exports.updateAppointment = updateAppointment;
// functions/src/clinic/updateAppointment.ts
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const audit_1 = require("./audit/audit");
const ALLOW_KIND_CONVERSION = false;
function getBoolPerm(perms, key) {
    return typeof perms === "object" && perms !== null && perms[key] === true;
}
function requirePerm(perms, keys, message) {
    const ok = keys.some((k) => getBoolPerm(perms, k));
    if (!ok)
        throw new https_1.HttpsError("permission-denied", message);
}
function normalizeKind(k) {
    if (k == null)
        return null;
    const v = k.toLowerCase().trim();
    const allowed = new Set(["admin", "new", "followup"]);
    if (!allowed.has(v)) {
        throw new https_1.HttpsError("invalid-argument", "Invalid kind. Use admin|new|followup.");
    }
    return v;
}
function parseMillisToTimestamp(ms) {
    if (ms == null)
        return null;
    if (typeof ms !== "number" || !Number.isFinite(ms))
        return null;
    if (ms <= 0)
        return null;
    return admin.firestore.Timestamp.fromMillis(ms);
}
function parseIsoToTimestamp(v) {
    if (!v)
        return null;
    const d = new Date(v);
    if (Number.isNaN(d.getTime()))
        return null;
    return admin.firestore.Timestamp.fromDate(d);
}
/**
 * Returns IDs of closures overlapped by [startAt, endAt).
 * Overlap rule: start < closure.toAt && end > closure.fromAt
 *
 * Query optimization: only closures with fromAt < endAt can overlap.
 */
async function findOverlappingClosures(params) {
    const { db, clinicId, startAt, endAt } = params;
    const snap = await db
        .collection(`clinics/${clinicId}/closures`)
        .where("active", "==", true)
        .where("fromAt", "<", endAt)
        .get();
    const ids = [];
    for (const doc of snap.docs) {
        const data = doc.data();
        const fromAt = data === null || data === void 0 ? void 0 : data.fromAt;
        const toAt = data === null || data === void 0 ? void 0 : data.toAt;
        if (!fromAt || !toAt)
            continue;
        const overlaps = startAt.toMillis() < toAt.toMillis() && endAt.toMillis() > fromAt.toMillis();
        if (overlaps)
            ids.push(doc.id);
    }
    return ids;
}
// ✅ Canonical-first membership loader (with legacy fallback)
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
    // New model: status can exist
    const status = ((_a = data.status) !== null && _a !== void 0 ? _a : "").toString().toLowerCase().trim();
    if (status === "invited" || status === "suspended")
        return false;
    // Treat missing "active" as active (backwards compatible)
    if (!("active" in data))
        return true;
    return data.active === true;
}
async function updateAppointment(req) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q, _r, _s, _t, _u, _v, _w, _x, _y, _z, _0, _1;
    if (!req.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const clinicId = ((_b = (_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId) !== null && _b !== void 0 ? _b : "").toString().trim();
    const appointmentId = ((_d = (_c = req.data) === null || _c === void 0 ? void 0 : _c.appointmentId) !== null && _d !== void 0 ? _d : "").toString().trim();
    if (!clinicId || !appointmentId) {
        throw new https_1.HttpsError("invalid-argument", "clinicId and appointmentId are required.");
    }
    const db = admin.firestore();
    const uid = req.auth.uid;
    // ─────────────────────────────
    // Membership + perms (canonical-first)
    // ─────────────────────────────
    const memberData = await getMembershipData(db, clinicId, uid);
    if (!memberData || !isActiveMember(memberData)) {
        throw new https_1.HttpsError("permission-denied", "Not a clinic member.");
    }
    const perms = (_e = memberData.permissions) !== null && _e !== void 0 ? _e : {};
    // Two paths:
    // - normal reschedule => schedule.write OR schedule.manage
    // - override into closure => settings.write (explicitly required)
    const allowClosedOverride = ((_f = req.data) === null || _f === void 0 ? void 0 : _f.allowClosedOverride) === true;
    if (allowClosedOverride) {
        requirePerm(perms, ["settings.write"], "No permission to override clinic closures (settings.write required).");
    }
    else {
        requirePerm(perms, ["schedule.write", "schedule.manage"], "No scheduling permission.");
    }
    // Load appointment
    const apptRef = db
        .collection("clinics")
        .doc(clinicId)
        .collection("appointments")
        .doc(appointmentId);
    const apptSnap = await apptRef.get();
    if (!apptSnap.exists)
        throw new https_1.HttpsError("not-found", "Appointment not found.");
    const appt = (_g = apptSnap.data()) !== null && _g !== void 0 ? _g : {};
    // Build patch
    const patch = {};
    const now = admin.firestore.FieldValue.serverTimestamp();
    // Track whether time is changing (so we only check closures when needed)
    let newStartAt = null;
    let newEndAt = null;
    // ─────────────────────────────
    // Time update (start/end)
    // Prefer millis. Require both or neither.
    // ─────────────────────────────
    const startMsProvided = ((_h = req.data) === null || _h === void 0 ? void 0 : _h.startMs) != null;
    const endMsProvided = ((_j = req.data) === null || _j === void 0 ? void 0 : _j.endMs) != null;
    const startIsoProvided = ((_k = req.data) === null || _k === void 0 ? void 0 : _k.start) != null;
    const endIsoProvided = ((_l = req.data) === null || _l === void 0 ? void 0 : _l.end) != null;
    const anyTimeProvided = startMsProvided || endMsProvided || startIsoProvided || endIsoProvided;
    if (anyTimeProvided) {
        const useMillis = startMsProvided || endMsProvided;
        if (useMillis) {
            if (startMsProvided !== endMsProvided) {
                throw new https_1.HttpsError("invalid-argument", "Provide both startMs and endMs.");
            }
            const startTs = parseMillisToTimestamp((_m = req.data) === null || _m === void 0 ? void 0 : _m.startMs);
            const endTs = parseMillisToTimestamp((_o = req.data) === null || _o === void 0 ? void 0 : _o.endMs);
            if (!startTs)
                throw new https_1.HttpsError("invalid-argument", "Invalid startMs.");
            if (!endTs)
                throw new https_1.HttpsError("invalid-argument", "Invalid endMs.");
            if (startTs.toMillis() >= endTs.toMillis()) {
                throw new https_1.HttpsError("invalid-argument", "start must be before end.");
            }
            newStartAt = startTs;
            newEndAt = endTs;
            // Canonical
            patch.startAt = startTs;
            patch.endAt = endTs;
            // Legacy mirrors (keep while migrating)
            patch.start = startTs;
            patch.end = endTs;
        }
        else {
            // Legacy ISO fallback
            if (startIsoProvided !== endIsoProvided) {
                throw new https_1.HttpsError("invalid-argument", "Provide both start and end.");
            }
            const startTs = parseIsoToTimestamp((_p = req.data) === null || _p === void 0 ? void 0 : _p.start);
            const endTs = parseIsoToTimestamp((_q = req.data) === null || _q === void 0 ? void 0 : _q.end);
            if (!startTs)
                throw new https_1.HttpsError("invalid-argument", "Invalid start ISO string.");
            if (!endTs)
                throw new https_1.HttpsError("invalid-argument", "Invalid end ISO string.");
            if (startTs.toMillis() >= endTs.toMillis()) {
                throw new https_1.HttpsError("invalid-argument", "start must be before end.");
            }
            newStartAt = startTs;
            newEndAt = endTs;
            patch.startAt = startTs;
            patch.endAt = endTs;
            patch.start = startTs;
            patch.end = endTs;
        }
    }
    // ─────────────────────────────
    // kind update
    // ─────────────────────────────
    const kind = normalizeKind((_r = req.data) === null || _r === void 0 ? void 0 : _r.kind);
    if (kind != null) {
        const currentKind = ((_s = appt["kind"]) !== null && _s !== void 0 ? _s : "").toString().toLowerCase().trim();
        if (!ALLOW_KIND_CONVERSION) {
            const changingAdminness = (currentKind === "admin" && kind !== "admin") ||
                (currentKind !== "admin" && kind === "admin");
            if (changingAdminness) {
                throw new https_1.HttpsError("failed-precondition", "Converting between admin and patient bookings is disabled.");
            }
        }
        patch.kind = kind;
    }
    // ─────────────────────────────
    // serviceId update + denormalized serviceName
    // ─────────────────────────────
    if ("serviceId" in ((_t = req.data) !== null && _t !== void 0 ? _t : {})) {
        const raw = (_u = req.data) === null || _u === void 0 ? void 0 : _u.serviceId;
        const sid = (raw !== null && raw !== void 0 ? raw : "").toString().trim();
        patch.serviceId = sid;
        if (sid) {
            const serviceRef = db
                .collection("clinics")
                .doc(clinicId)
                .collection("services")
                .doc(sid);
            const serviceSnap = await serviceRef.get();
            if (!serviceSnap.exists) {
                throw new https_1.HttpsError("failed-precondition", "Selected service does not exist.");
            }
            const s = (_v = serviceSnap.data()) !== null && _v !== void 0 ? _v : {};
            patch.serviceName = ((_w = s["name"]) !== null && _w !== void 0 ? _w : "").toString();
        }
        else {
            patch.serviceName = "";
        }
    }
    // ─────────────────────────────
    // If kind changed away from admin, ensure required IDs exist
    // ─────────────────────────────
    if (patch.kind && patch.kind !== "admin") {
        const patientId = ((_x = appt["patientId"]) !== null && _x !== void 0 ? _x : "").toString().trim();
        const serviceId = ((_z = ((_y = patch.serviceId) !== null && _y !== void 0 ? _y : appt["serviceId"])) !== null && _z !== void 0 ? _z : "").toString().trim();
        const practitionerId = ((_0 = appt["practitionerId"]) !== null && _0 !== void 0 ? _0 : "").toString().trim();
        if (!patientId) {
            throw new https_1.HttpsError("failed-precondition", "Cannot set kind to new/followup without patientId.");
        }
        if (!serviceId) {
            throw new https_1.HttpsError("failed-precondition", "Cannot set kind to new/followup without serviceId.");
        }
        if (!practitionerId) {
            throw new https_1.HttpsError("failed-precondition", "Cannot set kind to new/followup without practitionerId.");
        }
    }
    const keys = Object.keys(patch);
    if (keys.length === 0) {
        throw new https_1.HttpsError("invalid-argument", "No changes provided.");
    }
    // ─────────────────────────────
    // Block closure overlaps (SERVER-SIDE ENFORCEMENT)
    // + Override marker fields + AUDIT (for override use)
    // ─────────────────────────────
    let overlappedClosureIds = [];
    let didUseClosureOverride = false;
    // Only check overlaps when time is changing.
    if (newStartAt && newEndAt) {
        overlappedClosureIds = await findOverlappingClosures({
            db,
            clinicId,
            startAt: newStartAt,
            endAt: newEndAt,
        });
        // If overlapping and NOT overriding => block
        if (!allowClosedOverride && overlappedClosureIds.length > 0) {
            throw new https_1.HttpsError("failed-precondition", "Appointment overlaps a clinic closure.", {
                closureId: overlappedClosureIds[0],
                closureIds: overlappedClosureIds,
            });
        }
        // If overriding and overlapping => mark appointment + audit
        if (allowClosedOverride && overlappedClosureIds.length > 0) {
            didUseClosureOverride = true;
            patch.closureOverride = true;
            patch.closureOverrideByUid = uid;
            patch.closureOverrideAt = now;
            // Store which closures were involved (handy for UI/reporting)
            patch.closureOverrideClosureIds = overlappedClosureIds;
        }
        // If moved OUT of closures, clear any previous override marker.
        if (overlappedClosureIds.length === 0) {
            patch.closureOverride = false;
            patch.closureOverrideByUid = admin.firestore.FieldValue.delete();
            patch.closureOverrideAt = admin.firestore.FieldValue.delete();
            patch.closureOverrideClosureIds = admin.firestore.FieldValue.delete();
        }
    }
    patch.updatedAt = now;
    patch.updatedByUid = uid;
    await apptRef.update(patch);
    // ✅ IMPORTANT: use the "clinic.closure.override.used" type so your Audit screen filter matches.
    if (didUseClosureOverride) {
        const startMs = newStartAt ? newStartAt.toMillis() : null;
        const endMs = newEndAt ? newEndAt.toMillis() : null;
        await (0, audit_1.writeAuditEvent)(db, clinicId, {
            type: "clinic.closure.override.used",
            actorUid: uid,
            appointmentId,
            metadata: {
                appointmentId,
                closureId: (_1 = overlappedClosureIds[0]) !== null && _1 !== void 0 ? _1 : null,
                closureIds: overlappedClosureIds,
                startMs,
                endMs,
                allowClosedOverride: true,
            },
        });
    }
    return { success: true, updatedKeys: Object.keys(patch) };
}
//# sourceMappingURL=updateAppointment.js.map