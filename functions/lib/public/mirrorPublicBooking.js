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
exports.onPractitionerWritten = void 0;
exports.runPublicBookingMirrorForClinic = runPublicBookingMirrorForClinic;
// functions/src/public/mirrorPublicBooking.ts
// CP-P2: Public mirror includes curated locations, practitioners, appointmentTypes (active + visibility).
const admin = __importStar(require("firebase-admin"));
const logger_1 = require("firebase-functions/logger");
const firestore_1 = require("firebase-functions/v2/firestore");
const publicProjection_1 = require("../clinic/publicProjection");
const questionnaireTemplates_1 = require("../clinic/questionnaires/questionnaireTemplates");
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
function safeStr(v) {
    return typeof v === "string" ? v.trim() : (v !== null && v !== void 0 ? v : "").toString().trim();
}
function asMap(v) {
    return v && typeof v === "object" ? v : {};
}
const PUBLIC_PATH_PREFIX = "public/";
/** Asserts all write paths are under clinics/{clinicId}/public/** (projection boundary). */
function assertOnlyPublicWrites(clinicId, path) {
    const expectedPrefix = `clinics/${clinicId}/${PUBLIC_PATH_PREFIX}`;
    if (!path.startsWith(expectedPrefix)) {
        throw new Error(`runPublicBookingMirrorForClinic may only write under clinics/{clinicId}/public/**. Got: ${path}`);
    }
}
const DAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
/** When private config is deleted, write a safe empty projection (no admin/private fields). */
function buildSafeDefaultPublicProjection(clinicId) {
    const emptyWeeklyHours = Object.fromEntries(DAY_KEYS.map((k) => [k, []]));
    return {
        timezone: "Europe/London",
        weeklyHours: emptyWeeklyHours,
        slotStepMinutes: 15,
        minNoticeMinutes: 60,
        maxAdvanceDays: 365,
        schemaVersion: 1,
        locations: [],
        practitioners: [],
        appointmentTypes: [],
    };
}
/** Compare payloads for no-op; exclude updatedAt/updatedBy. */
function payloadsEqual(a, b) {
    const strip = (o) => {
        const out = { ...o };
        delete out.updatedAt;
        delete out.updatedBy;
        return out;
    };
    return JSON.stringify(strip(a)) === JSON.stringify(strip(b));
}
/** Recursively remove undefined values so Firestore accepts the document. Leaves Timestamp/FieldValue intact. */
function removeUndefined(val) {
    if (val === undefined)
        return undefined;
    if (val === null || typeof val !== "object")
        return val;
    if (val instanceof admin.firestore.Timestamp)
        return val;
    if (Array.isArray(val))
        return val.map((item) => removeUndefined(item));
    // Plain object only; do not recurse into FieldValue or other sentinels
    if (Object.getPrototypeOf(val) !== Object.prototype)
        return val;
    const out = {};
    for (const [k, v] of Object.entries(val)) {
        if (v === undefined)
            continue;
        out[k] = removeUndefined(v);
    }
    return out;
}
/**
 * CP-P2: Run mirror for a clinic (trigger or callable). Reads settings/publicBooking, locations,
 * practitioners, appointmentTypes; writes public doc only.
 *
 * Main public booking projection: clinics/{clinicId}/public/config/publicBooking/publicBooking.
 * This is the single doc written by onPublicBookingConfigMirror when settings/publicBooking
 * changes; listPublicSlots and public booking UI read from here (no direct client writes).
 */
async function runPublicBookingMirrorForClinic(clinicId) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q, _r, _s;
    const cid = safeStr(clinicId);
    if (!cid)
        return;
    const publicDocPath = `clinics/${cid}/public/config/publicBooking/publicBooking`;
    assertOnlyPublicWrites(cid, publicDocPath);
    const publicDocRef = db.doc(publicDocPath);
    const settingsRef = db.doc(`clinics/${cid}/settings/publicBooking`);
    const settingsSnap = await settingsRef.get().catch(() => null);
    if (!(settingsSnap === null || settingsSnap === void 0 ? void 0 : settingsSnap.exists)) {
        // Private config deleted: write safe empty projection (do not hard-delete public doc).
        const safeDefaults = buildSafeDefaultPublicProjection(cid);
        const defaultPayload = removeUndefined({
            ...safeDefaults,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedBy: "mirrorPublicBooking-defaults",
        });
        await publicDocRef.set(defaultPayload, { merge: true });
        logger_1.logger.info("mirrorPublicBooking: source deleted, wrote safe defaults", { clinicId: cid });
        return;
    }
    const publicBookingSettingsDoc = asMap(settingsSnap.data());
    const publicQuestionnaireFlow = await (0, questionnaireTemplates_1.buildPublicQuestionnaireFlow)(db, cid, publicBookingSettingsDoc.questionnaireFlow);
    const publicBookingSettingsForProjection = {
        ...publicBookingSettingsDoc,
        questionnaireFlow: publicQuestionnaireFlow,
    };
    const clinicRef = db.doc(`clinics/${cid}`);
    const servicesCol = db.collection(`clinics/${cid}/services`);
    const practitionersCol = db.collection(`clinics/${cid}/practitioners`);
    const membersCol = db.collection(`clinics/${cid}/members`);
    const locationsCol = db.collection(`clinics/${cid}/locations`);
    const appointmentTypesCol = db.collection(`clinics/${cid}/appointmentTypes`);
    const staffProfilesCol = db.collection(`clinics/${cid}/staffProfiles`);
    const membershipsCol = db.collection(`clinics/${cid}/memberships`);
    const [clinicSnap, servicesSnap, practitionersSnap, membersSnap, membershipsSnap, locationsSnap, typesSnap, staffProfilesSnap] = await Promise.all([
        clinicRef.get().catch(() => null),
        servicesCol.where("active", "==", true).get().catch(() => null),
        practitionersCol.get().catch(() => null),
        membersCol.get().catch(() => null),
        membershipsCol.get().catch(() => null),
        locationsCol.get().catch(() => null),
        appointmentTypesCol.get().catch(() => null),
        staffProfilesCol.get().catch(() => null),
    ]);
    const clinicDoc = (clinicSnap === null || clinicSnap === void 0 ? void 0 : clinicSnap.exists) ? asMap(clinicSnap.data()) : {};
    const profile = asMap(clinicDoc.profile);
    const clinicName = safeStr(clinicDoc.name) ||
        safeStr(profile.name) ||
        safeStr(clinicDoc.clinicName) ||
        safeStr(clinicDoc.publicName) ||
        "Clinic";
    const logoUrl = safeStr(clinicDoc.logoUrl) ||
        safeStr(profile.logoUrl) ||
        safeStr(asMap(clinicDoc.branding).logoUrl) ||
        safeStr(asMap(asMap(clinicDoc.settings).appearance).logoUrl) ||
        "";
    const services = (_a = servicesSnap === null || servicesSnap === void 0 ? void 0 : servicesSnap.docs.map((d) => ({ id: d.id, data: asMap(d.data()) }))) !== null && _a !== void 0 ? _a : [];
    // Merge members (canonical) + memberships (legacy); prefer members.
    const memberById = new Map();
    for (const d of (_b = membersSnap === null || membersSnap === void 0 ? void 0 : membersSnap.docs) !== null && _b !== void 0 ? _b : []) {
        memberById.set(d.id, { id: d.id, data: asMap(d.data()) });
    }
    for (const d of (_c = membershipsSnap === null || membershipsSnap === void 0 ? void 0 : membershipsSnap.docs) !== null && _c !== void 0 ? _c : []) {
        if (!memberById.has(d.id)) {
            memberById.set(d.id, { id: d.id, data: asMap(d.data()) });
        }
    }
    const memberships = Array.from(memberById.values());
    // Pass all practitioners; buildPublicPractitioners filters (same as settings trigger).
    const practitioners = (_d = practitionersSnap === null || practitionersSnap === void 0 ? void 0 : practitionersSnap.docs.map((d) => ({ id: d.id, data: asMap(d.data()) }))) !== null && _d !== void 0 ? _d : [];
    const staffProfiles = (_e = staffProfilesSnap === null || staffProfilesSnap === void 0 ? void 0 : staffProfilesSnap.docs.map((d) => ({ id: d.id, data: asMap(d.data()) }))) !== null && _e !== void 0 ? _e : [];
    const input = {
        clinicId: cid,
        clinicName,
        logoUrl,
        clinicDoc,
        publicBookingSettingsDoc: publicBookingSettingsForProjection,
        services,
        practitioners,
        memberships,
        staffProfiles,
    };
    const projection = (0, publicProjection_1.buildPublicBookingProjection)(input);
    // CP-P2: Curated lists for public booking (active + visibility only; no addresses/PII)
    const locationsList = (_g = (_f = locationsSnap === null || locationsSnap === void 0 ? void 0 : locationsSnap.docs) === null || _f === void 0 ? void 0 : _f.filter((d) => {
        const dta = d.data();
        return (dta === null || dta === void 0 ? void 0 : dta.active) === true && (dta === null || dta === void 0 ? void 0 : dta.showInOnlineBooking) === true;
    }).map((d) => {
        const dta = d.data() || {};
        return { id: d.id, name: safeStr(dta.name) || d.id };
    })) !== null && _g !== void 0 ? _g : [];
    const practitionersList = (_h = projection.practitioners) !== null && _h !== void 0 ? _h : [];
    const appointmentTypesList = (_k = (_j = typesSnap === null || typesSnap === void 0 ? void 0 : typesSnap.docs) === null || _j === void 0 ? void 0 : _j.filter((d) => {
        const dta = d.data();
        return (dta === null || dta === void 0 ? void 0 : dta.active) === true && (dta === null || dta === void 0 ? void 0 : dta.showInOnlineBooking) === true;
    }).map((d) => {
        const dta = d.data() || {};
        // Backend stores durationMinutes; mirror exposes defaultDurationMinutes for public consumers.
        const durationMinutes = typeof dta.durationMinutes === "number" ? dta.durationMinutes : 30;
        const allowedLocs = Array.isArray(dta.allowedLocationIds)
            ? dta.allowedLocationIds.filter((x) => typeof x === "string" && x.trim())
            : undefined;
        const allowedPractitioners = Array.isArray(dta.allowedPractitionerIds)
            ? dta.allowedPractitionerIds.filter((x) => typeof x === "string" && x.trim())
            : undefined;
        return {
            id: d.id,
            name: safeStr(dta.name) || d.id,
            defaultDurationMinutes: durationMinutes,
            description: safeStr(dta.description) || undefined,
            defaultPrice: typeof dta.defaultPrice === "number" ? dta.defaultPrice : undefined,
            colorHex: safeStr(dta.colorHex) || undefined,
            allowedLocationIds: allowedLocs && allowedLocs.length > 0 ? allowedLocs : undefined,
            telehealth: dta.telehealth === true,
            allowedPractitionerIds: allowedPractitioners && allowedPractitioners.length > 0 ? allowedPractitioners : undefined,
        };
    })) !== null && _k !== void 0 ? _k : [];
    const practitionersForDoc = practitionersList.map((p) => {
        var _a, _b, _c, _d, _e;
        return ({
            id: p.id,
            displayName: (_a = p.displayName) !== null && _a !== void 0 ? _a : p.id,
            title: (_c = (_b = p.title) !== null && _b !== void 0 ? _b : p.designation) !== null && _c !== void 0 ? _c : undefined,
            photoUrl: (_d = p.photoUrl) !== null && _d !== void 0 ? _d : undefined,
            bio: (_e = p.bio) !== null && _e !== void 0 ? _e : undefined,
            serviceIdsAllowed: Array.isArray(p.serviceIdsAllowed) ? p.serviceIdsAllowed : undefined,
            sortOrder: typeof p.sortOrder === "number" ? p.sortOrder : undefined,
            allowedLocationIds: Array.isArray(p.allowedLocationIds) ? p.allowedLocationIds : undefined,
        });
    });
    const newPayload = {
        ...projection,
        locations: locationsList,
        practitioners: practitionersForDoc,
        appointmentTypes: appointmentTypesList,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: "mirrorPublicBooking-v2",
    };
    const currentSnap = await publicDocRef.get().catch(() => null);
    if (currentSnap === null || currentSnap === void 0 ? void 0 : currentSnap.exists) {
        const currentData = asMap(currentSnap.data());
        if (payloadsEqual(newPayload, currentData)) {
            logger_1.logger.info("mirrorPublicBooking: unchanged, skip write", { clinicId: cid });
            return;
        }
    }
    const payloadToWrite = removeUndefined(newPayload);
    await publicDocRef.set(payloadToWrite, { merge: true });
    if (practitionersList.length === 0) {
        const withVisibility = (_m = (_l = practitionersSnap === null || practitionersSnap === void 0 ? void 0 : practitionersSnap.docs) === null || _l === void 0 ? void 0 : _l.filter((d) => { var _a, _b; return ((_a = d.data()) === null || _a === void 0 ? void 0 : _a.showInPublicBooking) === true && ((_b = d.data()) === null || _b === void 0 ? void 0 : _b.active) !== false; }).length) !== null && _m !== void 0 ? _m : 0;
        const memberByIdLog = new Map();
        for (const m of memberships) {
            memberByIdLog.set(m.id, m.data);
        }
        const whyExcluded = [];
        for (const d of (_o = practitionersSnap === null || practitionersSnap === void 0 ? void 0 : practitionersSnap.docs) !== null && _o !== void 0 ? _o : []) {
            const dta = (_p = d.data()) !== null && _p !== void 0 ? _p : {};
            const show = dta.showInPublicBooking === true;
            if (!show)
                continue;
            const mem = memberByIdLog.get(d.id);
            const memStatus = mem ? (safeStr(mem.status).toLowerCase() || (mem.active === true ? "active" : "inactive")) : "none";
            const memActive = memStatus === "none" || memStatus === "active";
            whyExcluded.push({
                id: d.id,
                show,
                active: dta.active !== false,
                activeForBooking: dta.activeForBooking !== false,
                memStatus,
                memActive,
            });
        }
        logger_1.logger.warn("mirrorPublicBooking: 0 practitioners in mirror", {
            clinicId: cid,
            practitionersWithPublicVisibility: withVisibility,
            totalPractitioners: (_q = practitionersSnap === null || practitionersSnap === void 0 ? void 0 : practitionersSnap.size) !== null && _q !== void 0 ? _q : 0,
            membersCount: (_r = membersSnap === null || membersSnap === void 0 ? void 0 : membersSnap.size) !== null && _r !== void 0 ? _r : 0,
            membershipsCount: (_s = membershipsSnap === null || membershipsSnap === void 0 ? void 0 : membershipsSnap.size) !== null && _s !== void 0 ? _s : 0,
            whyExcluded,
        });
    }
    else {
        logger_1.logger.info("mirrorPublicBooking: mirror updated", {
            clinicId: cid,
            locations: locationsList.length,
            practitioners: practitionersList.length,
            appointmentTypes: appointmentTypesList.length,
        });
    }
}
/** When a practitioner doc is written (e.g. showInPublicBooking toggled), refresh the public mirror so public booking sees the change. */
exports.onPractitionerWritten = (0, firestore_1.onDocumentWritten)({
    region: "europe-west3",
    document: "clinics/{clinicId}/practitioners/{practitionerId}",
}, async (event) => {
    var _a;
    const clinicId = safeStr((_a = event.params) === null || _a === void 0 ? void 0 : _a.clinicId);
    if (!clinicId)
        return;
    logger_1.logger.info("onPractitionerWritten: refreshing public mirror", { clinicId });
    await runPublicBookingMirrorForClinic(clinicId);
});
// Trigger on settings/publicBooking is onPublicBookingConfigMirror (see onPublicBookingConfigMirror.ts).
//# sourceMappingURL=mirrorPublicBooking.js.map