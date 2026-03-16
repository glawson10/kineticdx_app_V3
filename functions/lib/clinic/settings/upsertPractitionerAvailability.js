"use strict";
/**
 * Commit 31: settings.upsertPractitionerAvailability
 * Create or update base recurring availability for a practitioner.
 * Path: clinics/{clinicId}/practitioners/{practitionerId}/availability/{availabilityId}
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
exports.upsertPractitionerAvailability = upsertPractitionerAvailability;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const permissions_1 = require("../permissions");
const audit_1 = require("../audit/audit");
const validators_1 = require("./validators");
const practitionerAvailabilityValidation_1 = require("./practitionerAvailabilityValidation");
const validators_2 = require("./validators");
const mirrorPractitionerAvailabilityToLegacy_1 = require("./mirrorPractitionerAvailabilityToLegacy");
const db = admin.firestore();
const FV = admin.firestore.FieldValue;
const FREQUENCY_SET = new Set(["weekly", "biweekly", "monthly"]);
function validatePatch(patch) {
    var _a, _b;
    if (patch == null || typeof patch !== "object") {
        throw new https_1.HttpsError("invalid-argument", "patch is required.");
    }
    const p = patch;
    const locationId = (0, validators_1.requireNonEmptyString)(p.locationId, "locationId");
    const startDate = (0, practitionerAvailabilityValidation_1.assertIsoDate)(p.startDate, "startDate");
    const endDateRaw = p.endDate;
    let endDate = null;
    if (endDateRaw != null && endDateRaw !== "") {
        const parsedEnd = (0, practitionerAvailabilityValidation_1.assertIsoDate)(endDateRaw, "endDate");
        if (parsedEnd < startDate) {
            throw new https_1.HttpsError("invalid-argument", "endDate must be >= startDate.");
        }
        endDate = parsedEnd;
    }
    const rr = p.recurrenceRule;
    if (rr == null || typeof rr !== "object") {
        throw new https_1.HttpsError("invalid-argument", "recurrenceRule is required.");
    }
    const r = rr;
    const frequency = (0, validators_2.assertString)(r.frequency, "recurrenceRule.frequency", { required: true });
    if (!frequency || frequency.length === 0) {
        throw new https_1.HttpsError("invalid-argument", "recurrenceRule.frequency is required.");
    }
    if (!FREQUENCY_SET.has(frequency)) {
        throw new https_1.HttpsError("invalid-argument", "recurrenceRule.frequency must be one of: weekly, biweekly, monthly.");
    }
    const interval = (0, validators_2.assertIntRange)(r.interval, "recurrenceRule.interval", {
        min: 1,
        max: practitionerAvailabilityValidation_1.MAX_INTERVAL,
        required: true,
    });
    if (interval == null) {
        throw new https_1.HttpsError("invalid-argument", "recurrenceRule.interval is required.");
    }
    const description = (_a = (0, validators_2.assertString)(p.description, "description", { trim: true, maxLength: 500 })) !== null && _a !== void 0 ? _a : null;
    const active = (_b = (0, validators_2.assertBoolean)(p.active, "active")) !== null && _b !== void 0 ? _b : true;
    const blocksRaw = p.blocks;
    if (!Array.isArray(blocksRaw) || blocksRaw.length > practitionerAvailabilityValidation_1.MAX_BLOCKS) {
        throw new https_1.HttpsError("invalid-argument", `blocks must be an array of length 0 to ${practitionerAvailabilityValidation_1.MAX_BLOCKS}.`);
    }
    if (active && blocksRaw.length === 0) {
        throw new https_1.HttpsError("invalid-argument", "When active is true, at least one block is required.");
    }
    const blocks = [];
    for (let i = 0; i < blocksRaw.length; i++) {
        const b = blocksRaw[i];
        if (b == null || typeof b !== "object") {
            throw new https_1.HttpsError("invalid-argument", `blocks[${i}] must be an object.`);
        }
        const block = b;
        const dayOfWeek = (0, validators_2.assertIntRange)(block.dayOfWeek, "blocks[].dayOfWeek", {
            min: 1,
            max: 7,
            required: true,
        });
        if (dayOfWeek == null) {
            throw new https_1.HttpsError("invalid-argument", "blocks[].dayOfWeek is required (1–7).");
        }
        const startTime = (0, practitionerAvailabilityValidation_1.assertTimeHHmm)(block.startTime, "blocks[].startTime");
        const endTime = (0, practitionerAvailabilityValidation_1.assertTimeHHmm)(block.endTime, "blocks[].endTime");
        const bookableOnline = (0, validators_2.assertBoolean)(block.bookableOnline, "blocks[].bookableOnline");
        blocks.push({
            dayOfWeek,
            startTime,
            endTime,
            bookableOnline: bookableOnline !== null && bookableOnline !== void 0 ? bookableOnline : true,
        });
    }
    if (blocks.length > 0)
        (0, practitionerAvailabilityValidation_1.assertNoOverlaps)(blocks);
    return {
        locationId,
        startDate,
        endDate,
        recurrenceRule: { frequency, interval },
        blocks,
        description,
        active,
    };
}
async function upsertPractitionerAvailability(request) {
    var _a;
    if (!((_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid)) {
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    }
    const data = request.data;
    const clinicId = (0, validators_1.requireNonEmptyString)(data === null || data === void 0 ? void 0 : data.clinicId, "clinicId");
    const practitionerId = (0, validators_1.requireNonEmptyString)(data === null || data === void 0 ? void 0 : data.practitionerId, "practitionerId");
    const availabilityIdRaw = data === null || data === void 0 ? void 0 : data.availabilityId;
    const availabilityId = availabilityIdRaw === null || availabilityIdRaw === undefined || availabilityIdRaw === ""
        ? null
        : String(availabilityIdRaw).trim();
    const isCreate = !availabilityId || availabilityId.length === 0;
    let validated;
    try {
        validated = validatePatch(data === null || data === void 0 ? void 0 : data.patch);
    }
    catch (e) {
        if (e instanceof https_1.HttpsError)
            throw e;
        throw new https_1.HttpsError("invalid-argument", e instanceof Error ? e.message : "Invalid patch.");
    }
    const uid = request.auth.uid;
    await (0, permissions_1.requireClinicPermission)(db, clinicId, uid, "settings.write");
    try {
        return await upsertPractitionerAvailabilityImpl(db, clinicId, practitionerId, uid, availabilityId, isCreate, validated);
    }
    catch (e) {
        if (e instanceof https_1.HttpsError)
            throw e;
        const message = e instanceof Error ? e.message : String(e);
        throw new https_1.HttpsError("internal", message || "Failed to save availability rule.");
    }
}
async function upsertPractitionerAvailabilityImpl(db, clinicId, practitionerId, uid, availabilityId, isCreate, validated) {
    var _a, _b, _c, _d, _e, _f;
    const colRef = db
        .collection("clinics")
        .doc(clinicId)
        .collection("practitioners")
        .doc(practitionerId)
        .collection("availability");
    const now = FV.serverTimestamp();
    if (isCreate) {
        const docId = colRef.doc().id;
        const doc = {
            locationId: validated.locationId,
            startDate: validated.startDate,
            endDate: (_a = validated.endDate) !== null && _a !== void 0 ? _a : null,
            recurrenceRule: validated.recurrenceRule,
            blocks: validated.blocks,
            description: (_b = validated.description) !== null && _b !== void 0 ? _b : null,
            active: validated.active,
            createdAt: now,
            updatedAt: now,
        };
        await colRef.doc(docId).set(doc);
        const entityPath = `clinics/${clinicId}/practitioners/${practitionerId}/availability/${docId}`;
        await (0, audit_1.writeSettingsAuditEvent)(db, clinicId, "settings.availability.created", uid, entityPath, docId, { locationId: validated.locationId, startDate: validated.startDate, active: validated.active });
        await (0, mirrorPractitionerAvailabilityToLegacy_1.mirrorPractitionerAvailabilityToLegacy)(clinicId, practitionerId);
        return { ok: true, availabilityId: docId };
    }
    const ref = colRef.doc(availabilityId);
    const snap = await ref.get();
    if (!snap.exists) {
        throw new https_1.HttpsError("not-found", "Availability not found.");
    }
    const beforeActive = (_c = snap.data()) === null || _c === void 0 ? void 0 : _c.active;
    const updateData = {
        locationId: validated.locationId,
        startDate: validated.startDate,
        endDate: (_d = validated.endDate) !== null && _d !== void 0 ? _d : null,
        recurrenceRule: validated.recurrenceRule,
        blocks: validated.blocks,
        description: (_e = validated.description) !== null && _e !== void 0 ? _e : null,
        active: validated.active,
        updatedAt: now,
    };
    await ref.update(updateData);
    const entityPath = `clinics/${clinicId}/practitioners/${practitionerId}/availability/${availabilityId}`;
    const prev = (_f = snap.data()) !== null && _f !== void 0 ? _f : {};
    const keysExceptActive = ["locationId", "startDate", "endDate", "recurrenceRule", "blocks", "description"];
    const onlyActiveChanged = beforeActive !== validated.active &&
        keysExceptActive.every((k) => JSON.stringify(prev[k]) === JSON.stringify(updateData[k]));
    if (onlyActiveChanged) {
        const eventType = validated.active
            ? "settings.availability.activated"
            : "settings.availability.deactivated";
        await (0, audit_1.writeSettingsAuditEvent)(db, clinicId, eventType, uid, entityPath, availabilityId, {
            active: { before: beforeActive, after: validated.active },
        });
    }
    else {
        const { updatedAt: _unused, ...changesForAudit } = updateData;
        await (0, audit_1.writeSettingsAuditEvent)(db, clinicId, "settings.availability.updated", uid, entityPath, availabilityId, changesForAudit);
    }
    await (0, mirrorPractitionerAvailabilityToLegacy_1.mirrorPractitionerAvailabilityToLegacy)(clinicId, practitionerId);
    return { ok: true, availabilityId: availabilityId };
}
//# sourceMappingURL=upsertPractitionerAvailability.js.map