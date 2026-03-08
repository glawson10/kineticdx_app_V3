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
const MIN_DURATION_MINS = 5;
const MAX_DURATION_MINS = 240;
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
function parseTimestamp(v) {
    var _a;
    if (!v)
        return null;
    if (v instanceof admin.firestore.Timestamp)
        return v;
    if (typeof (v === null || v === void 0 ? void 0 : v.toMillis) === "function")
        return v;
    if (typeof v === "object" && typeof v._seconds === "number") {
        return new admin.firestore.Timestamp(v._seconds, (_a = v._nanoseconds) !== null && _a !== void 0 ? _a : 0);
    }
    if (typeof v === "number" && Number.isFinite(v))
        return admin.firestore.Timestamp.fromMillis(v);
    return null;
}
/**
 * Returns true if the given practitioner has any other non-cancelled appointment
 * overlapping [startAt, endAt), excluding excludeAppointmentId.
 * Used for overlap validation on update/reschedule.
 * When tx is provided, runs inside the transaction for consistency.
 */
async function hasPractitionerOverlap(params) {
    var _a, _b, _c;
    const { db, clinicId, practitionerId, startAt, endAt, excludeAppointmentId, tx } = params;
    const col = db.collection(`clinics/${clinicId}/appointments`);
    const query = col.where("practitionerId", "==", practitionerId).where("startAt", "<", endAt);
    const snap = tx ? await tx.get(query) : await query.get();
    const startMs = startAt.toMillis();
    const endMs = endAt.toMillis();
    for (const doc of snap.docs) {
        if (doc.id === excludeAppointmentId)
            continue;
        const d = doc.data();
        const status = ((_a = d === null || d === void 0 ? void 0 : d.status) !== null && _a !== void 0 ? _a : "").toString().toLowerCase();
        if (status === "cancelled")
            continue;
        const otherStart = parseTimestamp((_b = d === null || d === void 0 ? void 0 : d.startAt) !== null && _b !== void 0 ? _b : d === null || d === void 0 ? void 0 : d.start);
        const otherEnd = parseTimestamp((_c = d === null || d === void 0 ? void 0 : d.endAt) !== null && _c !== void 0 ? _c : d === null || d === void 0 ? void 0 : d.end);
        if (!otherStart || !otherEnd)
            continue;
        const otherStartMs = otherStart.toMillis();
        const otherEndMs = otherEnd.toMillis();
        const overlaps = otherStartMs < endMs && otherEndMs > startMs;
        if (overlaps)
            return true;
    }
    return false;
}
async function readPractitionerDoc(db, clinicId, practitionerId) {
    var _a, _b, _c, _d;
    const paths = [
        `clinics/${clinicId}/members/${practitionerId}`,
        `clinics/${clinicId}/memberships/${practitionerId}`,
        `clinics/${clinicId}/practitioners/${practitionerId}`,
        `clinics/${clinicId}/staff/${practitionerId}`,
    ];
    for (const path of paths) {
        const snap = await db.doc(path).get();
        if (!snap.exists)
            continue;
        const d = ((_a = snap.data()) !== null && _a !== void 0 ? _a : {});
        const active = d.active === true ||
            d.status === "active" ||
            ((_b = d.status) === null || _b === void 0 ? void 0 : _b.active) === true;
        const displayName = ((_d = (_c = d.displayName) !== null && _c !== void 0 ? _c : d.name) !== null && _d !== void 0 ? _d : "").toString().trim() || practitionerId;
        return { displayName, active };
    }
    return { displayName: practitionerId, active: false };
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
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q, _r, _s, _t, _u, _v, _w, _x, _y, _z, _0, _1, _2, _3, _4, _5, _6, _7, _8, _9, _10, _11, _12, _13, _14, _15, _16, _17, _18, _19;
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
            const durationMins = (endTs.toMillis() - startTs.toMillis()) / (60 * 1000);
            if (durationMins < MIN_DURATION_MINS || durationMins > MAX_DURATION_MINS) {
                throw new https_1.HttpsError("invalid-argument", `Duration must be between ${MIN_DURATION_MINS} and ${MAX_DURATION_MINS} minutes.`);
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
            const durationMins = (endTs.toMillis() - startTs.toMillis()) / (60 * 1000);
            if (durationMins < MIN_DURATION_MINS || durationMins > MAX_DURATION_MINS) {
                throw new https_1.HttpsError("invalid-argument", `Duration must be between ${MIN_DURATION_MINS} and ${MAX_DURATION_MINS} minutes.`);
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
    // practitionerId update + denormalized practitionerName
    // ─────────────────────────────
    if ("practitionerId" in ((_x = req.data) !== null && _x !== void 0 ? _x : {})) {
        const raw = (_y = req.data) === null || _y === void 0 ? void 0 : _y.practitionerId;
        const pid = (raw !== null && raw !== void 0 ? raw : "").toString().trim();
        const pracResult = await readPractitionerDoc(db, clinicId, pid || "x");
        if (pid && !pracResult.active) {
            throw new https_1.HttpsError("failed-precondition", "Selected practitioner is not an active clinic member.");
        }
        patch.practitionerId = pid || "";
        patch.practitionerName = pid ? pracResult.displayName : "";
    }
    // ─────────────────────────────
    // locationId update (BOOKING_DATA_CONTRACT)
    // ─────────────────────────────
    if ("locationId" in ((_z = req.data) !== null && _z !== void 0 ? _z : {})) {
        const raw = (_0 = req.data) === null || _0 === void 0 ? void 0 : _0.locationId;
        patch.locationId = (raw !== null && raw !== void 0 ? raw : "").toString().trim() || null;
    }
    // ─────────────────────────────
    // If kind changed away from admin, ensure required IDs exist
    // ─────────────────────────────
    if (patch.kind && patch.kind !== "admin") {
        const patientId = ((_1 = appt["patientId"]) !== null && _1 !== void 0 ? _1 : "").toString().trim();
        const serviceId = ((_3 = ((_2 = patch.serviceId) !== null && _2 !== void 0 ? _2 : appt["serviceId"])) !== null && _3 !== void 0 ? _3 : "").toString().trim();
        const practitionerId = ((_5 = ((_4 = patch.practitionerId) !== null && _4 !== void 0 ? _4 : appt["practitionerId"])) !== null && _5 !== void 0 ? _5 : "").toString().trim();
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
    // Resolve effective time and practitioner for overlap check
    const effectiveStartAt = (_7 = newStartAt !== null && newStartAt !== void 0 ? newStartAt : parseTimestamp((_6 = appt["startAt"]) !== null && _6 !== void 0 ? _6 : appt["start"])) !== null && _7 !== void 0 ? _7 : null;
    const effectiveEndAt = (_9 = newEndAt !== null && newEndAt !== void 0 ? newEndAt : parseTimestamp((_8 = appt["endAt"]) !== null && _8 !== void 0 ? _8 : appt["end"])) !== null && _9 !== void 0 ? _9 : null;
    const effectivePractitionerId = ((_10 = (patch.practitionerId !== undefined ? patch.practitionerId : appt["practitionerId"])) !== null && _10 !== void 0 ? _10 : "").toString().trim();
    const timeOrPractitionerChanged = (newStartAt != null || newEndAt != null) || "practitionerId" in patch;
    await db.runTransaction(async (tx) => {
        const freshSnap = await tx.get(apptRef);
        if (!freshSnap.exists)
            throw new https_1.HttpsError("not-found", "Appointment not found.");
        if (effectivePractitionerId && effectiveStartAt && effectiveEndAt && timeOrPractitionerChanged) {
            const overlap = await hasPractitionerOverlap({
                db,
                clinicId,
                practitionerId: effectivePractitionerId,
                startAt: effectiveStartAt,
                endAt: effectiveEndAt,
                excludeAppointmentId: appointmentId,
                tx,
            });
            if (overlap) {
                throw new https_1.HttpsError("failed-precondition", "This time slot is already booked for the selected practitioner.", { code: "practitioner_overlap" });
            }
        }
        tx.update(apptRef, patch);
    });
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
                closureId: (_11 = overlappedClosureIds[0]) !== null && _11 !== void 0 ? _11 : null,
                closureIds: overlappedClosureIds,
                startMs,
                endMs,
                allowClosedOverride: true,
            },
        });
    }
    await (0, audit_1.writeAuditEvent)(db, clinicId, {
        type: "appointment.updated",
        actorUid: uid,
        appointmentId,
        metadata: {
            appointmentId,
            updatedKeys: Object.keys(patch),
            startAtMs: (_13 = (_12 = newStartAt === null || newStartAt === void 0 ? void 0 : newStartAt.toMillis()) !== null && _12 !== void 0 ? _12 : effectiveStartAt === null || effectiveStartAt === void 0 ? void 0 : effectiveStartAt.toMillis()) !== null && _13 !== void 0 ? _13 : null,
            endAtMs: (_15 = (_14 = newEndAt === null || newEndAt === void 0 ? void 0 : newEndAt.toMillis()) !== null && _14 !== void 0 ? _14 : effectiveEndAt === null || effectiveEndAt === void 0 ? void 0 : effectiveEndAt.toMillis()) !== null && _15 !== void 0 ? _15 : null,
        },
    });
    const updatedFields = Object.keys(patch);
    return {
        success: true,
        appointmentId,
        updatedFields,
        startAt: (_17 = (_16 = newStartAt === null || newStartAt === void 0 ? void 0 : newStartAt.toMillis()) !== null && _16 !== void 0 ? _16 : effectiveStartAt === null || effectiveStartAt === void 0 ? void 0 : effectiveStartAt.toMillis()) !== null && _17 !== void 0 ? _17 : undefined,
        endAt: (_19 = (_18 = newEndAt === null || newEndAt === void 0 ? void 0 : newEndAt.toMillis()) !== null && _18 !== void 0 ? _18 : effectiveEndAt === null || effectiveEndAt === void 0 ? void 0 : effectiveEndAt.toMillis()) !== null && _19 !== void 0 ? _19 : undefined,
    };
}
//# sourceMappingURL=updateAppointment.js.map