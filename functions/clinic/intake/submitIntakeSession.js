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
exports.submitIntakeSession = submitIntakeSession;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const firebase_functions_1 = require("firebase-functions");
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
    const s = bodyArea.trim();
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
        firebase_functions_1.logger.info("🔥 submitIntakeSessionFn HIT", { hasAuth: !!req.auth });
        const data = ((_a = req.data) !== null && _a !== void 0 ? _a : {});
        assertString(data.clinicId, "clinicId");
        assertString(data.sessionId, "sessionId"); // ✅ NEW
        assertNumber(data.intakeSchemaVersion, "intakeSchemaVersion");
        assertString(data.flowId, "flowId");
        assertNumber(data.flowVersion, "flowVersion");
        if (!data.consent)
            throw new https_1.HttpsError("invalid-argument", "Missing consent");
        if (!data.patientDetails)
            throw new https_1.HttpsError("invalid-argument", "Missing patientDetails");
        if (!data.regionSelection)
            throw new https_1.HttpsError("invalid-argument", "Missing regionSelection");
        if (!data.answers)
            throw new https_1.HttpsError("invalid-argument", "Missing answers");
        const clinicId = data.clinicId.trim();
        const sessionId = data.sessionId.trim();
        const intakeSchemaVersion = data.intakeSchemaVersion;
        const flowId = data.flowId.trim();
        const flowVersion = data.flowVersion;
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
        const r = data.regionSelection;
        assertString(r.bodyArea, "regionSelection.bodyArea");
        assertString(r.side, "regionSelection.side");
        assertNumber(r.regionSetVersion, "regionSelection.regionSetVersion");
        const bodyArea = normalizeRegion(r.bodyArea);
        const answers = data.answers;
        for (const [k, v] of Object.entries(answers)) {
            validateAnswerValue(v, k);
        }
        firebase_functions_1.logger.info("✅ payload validated", {
            clinicId,
            sessionId,
            flowId,
            flowVersion,
            bodyArea,
            answersCount: Object.keys(answers).length,
        });
        const now = admin.firestore.FieldValue.serverTimestamp();
        const intakeRef = db
            .collection("clinics")
            .doc(clinicId)
            .collection("intakeSessions")
            .doc(sessionId);
        await db.runTransaction(async (tx) => {
            var _a, _b;
            const intakeSnap = await tx.get(intakeRef);
            if (!intakeSnap.exists) {
                // If someone tries to submit without a valid session
                throw new https_1.HttpsError("failed-precondition", "Session does not exist (link may be invalid or expired).");
            }
            const existing = (_a = intakeSnap.data()) !== null && _a !== void 0 ? _a : {};
            // ✅ idempotent: if already submitted, do nothing
            if (existing.submittedAt || existing.status === "submitted") {
                return;
            }
            // Submit into the existing session doc
            tx.set(intakeRef, {
                schemaVersion: intakeSchemaVersion,
                clinicId,
                createdBy: { kind: "patient" },
                status: "submitted",
                submittedAt: now,
                lockedAt: now,
                flow: { flowId, flowVersion },
                consent: { ...c, acceptedAt: now },
                patientDetails: {
                    ...p,
                    firstName: p.firstName.trim(),
                    lastName: p.lastName.trim(),
                    confirmedAt: now,
                },
                regionSelection: {
                    ...r,
                    bodyArea,
                    selectedAt: now,
                },
                answers,
                triage: { status: "green", reasons: [] },
                // Keep createdAt from original draft (do NOT overwrite)
                createdAt: (_b = existing.createdAt) !== null && _b !== void 0 ? _b : now,
            }, { merge: true });
            // ✅ Option B: mark invite used ONLY on submit
            const invitesCol = db
                .collection("clinics")
                .doc(clinicId)
                .collection("intakeInvites");
            const inviteQ = await tx.get(invitesCol.where("sessionId", "==", sessionId).limit(1));
            if (!inviteQ.empty) {
                const invDoc = inviteQ.docs[0];
                const invRef = invDoc.ref;
                const inv = invDoc.data();
                // If already used, do nothing (idempotent)
                if (!inv.usedAt) {
                    tx.set(invRef, {
                        usedAt: now,
                        submittedSessionId: sessionId,
                    }, { merge: true });
                }
            }
        });
        firebase_functions_1.logger.info("✅ intakeSession submitted", { clinicId, sessionId });
        return { ok: true, intakeSessionId: sessionId };
    }
    catch (err) {
        if (err instanceof https_1.HttpsError) {
            firebase_functions_1.logger.warn("submitIntakeSession rejected", {
                code: err.code,
                message: err.message,
            });
            throw err;
        }
        firebase_functions_1.logger.error("submitIntakeSession crashed", err);
        throw new https_1.HttpsError("internal", "submitIntakeSession crashed", {
            message: (_b = err === null || err === void 0 ? void 0 : err.message) !== null && _b !== void 0 ? _b : String(err),
        });
    }
}
//# sourceMappingURL=submitIntakeSession.js.map