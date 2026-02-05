"use strict";
// functions/src/clinic/intake/submitIntakeSession.ts
//
// ✅ Updated in full:
// - Keeps transaction read-before-write discipline
// - ✅ Supports generalVisit submissions (regionSelection optional for generalVisit)
// - ✅ Adds top-level flowId/flowVersion for easier querying
// - ✅ Adds flowCategory: "general" | "region" for clean tab queries
// - ✅ FIX: never allocates a new session id when caller provides a non-draft id
//   (critical for invite/link flows so sessionId stays stable)
// - Keeps idempotency + invite usedAt handling
//
// IMPORTANT:
// - This file MUST be compiled to functions/lib before deploy:
//     cd functions
//     npm run build
//     cd ..
//     firebase deploy --only functions:submitIntakeSessionFn
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
exports.submitIntakeSession = submitIntakeSession;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const logger_1 = require("firebase-functions/logger");
const schemaVersions_1 = require("../../schema/schemaVersions");
function assertString(x, field) {
    if (typeof x !== "string" || x.trim().length === 0) {
        throw new https_1.HttpsError("invalid-argument", `Missing/invalid ${field}`);
    }
}
function assertNumber(x, field) {
    if (typeof x !== "number" || Number.isNaN(x)) {
        throw new https_1.HttpsError("invalid-argument", `Missing/invalid ${field}`);
    }
}
function assertBool(x, field) {
    if (typeof x !== "boolean") {
        throw new https_1.HttpsError("invalid-argument", `Missing/invalid ${field}`);
    }
}
function normalizeRegion(bodyArea) {
    const s = (bodyArea !== null && bodyArea !== void 0 ? bodyArea : "").toString().trim();
    if (!s)
        return s;
    return s.startsWith("region.") ? s : `region.${s}`;
}
function validateAnswerValue(v, key) {
    if (!v || typeof v !== "object") {
        throw new https_1.HttpsError("invalid-argument", `Answer ${key} invalid`);
    }
    if (typeof v.t !== "string") {
        throw new https_1.HttpsError("invalid-argument", `Answer ${key} missing t`);
    }
    if (!("v" in v)) {
        throw new https_1.HttpsError("invalid-argument", `Answer ${key} missing v`);
    }
    switch (v.t) {
        case "bool":
            if (typeof v.v !== "boolean") {
                throw new https_1.HttpsError("invalid-argument", `Answer ${key} must be bool`);
            }
            break;
        case "int":
            if (typeof v.v !== "number" || !Number.isInteger(v.v)) {
                throw new https_1.HttpsError("invalid-argument", `Answer ${key} must be int`);
            }
            break;
        case "num":
            if (typeof v.v !== "number") {
                throw new https_1.HttpsError("invalid-argument", `Answer ${key} must be num`);
            }
            break;
        case "text":
            if (typeof v.v !== "string") {
                throw new https_1.HttpsError("invalid-argument", `Answer ${key} must be text`);
            }
            break;
        case "single":
            if (typeof v.v !== "string") {
                throw new https_1.HttpsError("invalid-argument", `Answer ${key} must be single`);
            }
            break;
        case "multi":
            if (!Array.isArray(v.v) || v.v.some((x) => typeof x !== "string")) {
                throw new https_1.HttpsError("invalid-argument", `Answer ${key} must be multi`);
            }
            break;
        case "date":
            if (typeof v.v !== "string") {
                throw new https_1.HttpsError("invalid-argument", `Answer ${key} must be date`);
            }
            break;
        case "map":
            if (typeof v.v !== "object" || v.v === null || Array.isArray(v.v)) {
                throw new https_1.HttpsError("invalid-argument", `Answer ${key} must be map`);
            }
            break;
        default:
            throw new https_1.HttpsError("invalid-argument", `Answer ${key} has invalid t=${v.t}`);
    }
}
async function submitIntakeSession(req) {
    var _a, _b;
    try {
        logger_1.logger.info("🔥 submitIntakeSessionFn HIT", { hasAuth: !!req.auth });
        const data = ((_a = req.data) !== null && _a !== void 0 ? _a : {});
        assertString(data.clinicId, "clinicId");
        assertString(data.sessionId, "sessionId");
        assertNumber(data.intakeSchemaVersion, "intakeSchemaVersion");
        assertString(data.flowId, "flowId");
        assertNumber(data.flowVersion, "flowVersion");
        if (!data.consent)
            throw new https_1.HttpsError("invalid-argument", "Missing consent");
        if (!data.patientDetails)
            throw new https_1.HttpsError("invalid-argument", "Missing patientDetails");
        if (!data.answers)
            throw new https_1.HttpsError("invalid-argument", "Missing answers");
        const clinicId = data.clinicId.trim();
        const sessionIdRaw = data.sessionId.trim();
        const intakeSchemaVersion = data.intakeSchemaVersion;
        const flowId = data.flowId.trim();
        const flowVersion = data.flowVersion;
        const isGeneralVisit = flowId === "generalVisit";
        const flowCategory = isGeneralVisit
            ? "general"
            : "region";
        const db = admin.firestore();
        const clinicSnap = await db.collection("clinics").doc(clinicId).get();
        if (!clinicSnap.exists) {
            throw new https_1.HttpsError("not-found", "Clinic does not exist");
        }
        const expected = (0, schemaVersions_1.schemaVersion)("intakeSession");
        if (intakeSchemaVersion !== expected) {
            throw new https_1.HttpsError("failed-precondition", `Schema mismatch client=${intakeSchemaVersion} server=${expected}`);
        }
        const c = data.consent;
        assertString(c.policyBundleId, "consent.policyBundleId");
        assertNumber(c.policyBundleVersion, "consent.policyBundleVersion");
        assertString(c.locale, "consent.locale");
        assertBool(c.termsAccepted, "consent.termsAccepted");
        assertBool(c.privacyAccepted, "consent.privacyAccepted");
        assertBool(c.dataStorageAccepted, "consent.dataStorageAccepted");
        assertBool(c.notEmergencyAck, "consent.notEmergencyAck");
        assertBool(c.noDiagnosisAck, "consent.noDiagnosisAck");
        assertBool(c.consentToContact, "consent.consentToContact");
        if (!c.termsAccepted ||
            !c.privacyAccepted ||
            !c.dataStorageAccepted ||
            !c.notEmergencyAck ||
            !c.noDiagnosisAck) {
            throw new https_1.HttpsError("failed-precondition", "Consent incomplete");
        }
        const p = data.patientDetails;
        assertString(p.firstName, "patientDetails.firstName");
        assertString(p.lastName, "patientDetails.lastName");
        // ✅ Region selection: required for region flows, optional for generalVisit
        let normalizedBodyArea = "";
        let regionSelectionToWrite = null;
        if (!isGeneralVisit) {
            if (!data.regionSelection) {
                throw new https_1.HttpsError("invalid-argument", "Missing regionSelection");
            }
            const r = data.regionSelection;
            assertString(r.bodyArea, "regionSelection.bodyArea");
            assertString(r.side, "regionSelection.side");
            assertNumber(r.regionSetVersion, "regionSelection.regionSetVersion");
            normalizedBodyArea = normalizeRegion(r.bodyArea);
            regionSelectionToWrite = {
                ...r,
                bodyArea: normalizedBodyArea,
                // selectedAt gets written inside transaction with `now`
            };
        }
        else {
            // If a client accidentally sends regionSelection, ignore it for generalVisit.
            regionSelectionToWrite = null;
        }
        const answers = data.answers;
        for (const [k, v] of Object.entries(answers))
            validateAnswerValue(v, k);
        logger_1.logger.info("✅ payload validated", {
            clinicId,
            sessionIdRaw,
            flowId,
            flowVersion,
            flowCategory,
            bodyArea: normalizedBodyArea,
            hasRegionSelection: !!regionSelectionToWrite,
            answersCount: Object.keys(answers).length,
        });
        const now = admin.firestore.FieldValue.serverTimestamp();
        const sessionsCol = db
            .collection("clinics")
            .doc(clinicId)
            .collection("intakeSessions");
        const invitesCol = db
            .collection("clinics")
            .doc(clinicId)
            .collection("intakeInvites");
        const shouldAutoCreate = sessionIdRaw.toLowerCase() === "draft";
        let finalSessionId = sessionIdRaw;
        await db.runTransaction(async (tx) => {
            // ─────────────────────────────────────────────
            // READS (ALL reads must happen before ANY writes)
            // ─────────────────────────────────────────────
            var _a, _b, _c;
            // ✅ If draft: allocate new doc id
            // ✅ If non-draft: ALWAYS use the provided id (never swap ids)
            const intakeRef = shouldAutoCreate
                ? sessionsCol.doc()
                : sessionsCol.doc(sessionIdRaw);
            const intakeSnap = await tx.get(intakeRef);
            finalSessionId = intakeRef.id;
            const existing = intakeSnap.exists ? ((_a = intakeSnap.data()) !== null && _a !== void 0 ? _a : {}) : {};
            // Read invite (Option B) before any writes
            const inviteQ = await tx.get(invitesCol.where("sessionId", "==", intakeRef.id).limit(1));
            const invDoc = inviteQ.empty ? null : inviteQ.docs[0];
            const invRef = (_b = invDoc === null || invDoc === void 0 ? void 0 : invDoc.ref) !== null && _b !== void 0 ? _b : null;
            const inv = invDoc === null || invDoc === void 0 ? void 0 : invDoc.data();
            // Idempotency (if already submitted, do nothing)
            if (existing.submittedAt ||
                existing.status === "submitted") {
                return;
            }
            // ─────────────────────────────────────────────
            // WRITES (ONLY after reads)
            // ─────────────────────────────────────────────
            tx.set(intakeRef, {
                schemaVersion: intakeSchemaVersion,
                clinicId,
                createdBy: { kind: "patient" },
                status: "submitted",
                submittedAt: now,
                lockedAt: now,
                updatedAt: now,
                // ✅ Keep nested flow, plus top-level for easy querying/indexing
                flow: { flowId, flowVersion },
                flowId,
                flowVersion,
                flowCategory, // "general" | "region"
                consent: { ...c, acceptedAt: now },
                patientDetails: {
                    ...p,
                    firstName: p.firstName.trim(),
                    lastName: p.lastName.trim(),
                    confirmedAt: now,
                },
                // ✅ Only write regionSelection for region flows
                ...(regionSelectionToWrite
                    ? {
                        regionSelection: {
                            ...regionSelectionToWrite,
                            selectedAt: now,
                        },
                    }
                    : {}),
                answers,
                // Region flows still use triage; generalVisit can default to green (harmless)
                triage: { status: "green", reasons: [] },
                // Preserve original createdAt if it exists; otherwise set now.
                createdAt: (_c = existing.createdAt) !== null && _c !== void 0 ? _c : now,
            }, { merge: true });
            if (invRef && inv && !inv.usedAt) {
                tx.set(invRef, { usedAt: now, submittedSessionId: intakeRef.id }, { merge: true });
            }
        });
        logger_1.logger.info("✅ intakeSession submitted", {
            clinicId,
            sessionId: finalSessionId,
            flowId,
            flowCategory,
        });
        return { ok: true, intakeSessionId: finalSessionId };
    }
    catch (err) {
        if (err instanceof https_1.HttpsError) {
            logger_1.logger.warn("submitIntakeSession rejected", {
                code: err.code,
                message: err.message,
            });
            throw err;
        }
        logger_1.logger.error("submitIntakeSession crashed", err);
        throw new https_1.HttpsError("internal", "submitIntakeSession crashed", {
            message: (_b = err === null || err === void 0 ? void 0 : err.message) !== null && _b !== void 0 ? _b : String(err),
        });
    }
}
//# sourceMappingURL=submitIntakeSession.js.map