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
exports.submitAssessment = submitAssessment;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const authz_1 = require("../authz");
const schemaVersions_1 = require("../../schema/schemaVersions");
const audit_1 = require("../audit/audit");
async function submitAssessment(req) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q, _r, _s;
    if (!req.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const clinicId = ((_b = (_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId) !== null && _b !== void 0 ? _b : "").trim();
    const packId = ((_d = (_c = req.data) === null || _c === void 0 ? void 0 : _c.packId) !== null && _d !== void 0 ? _d : "").trim();
    const regionKey = ((_f = (_e = req.data) === null || _e === void 0 ? void 0 : _e.regionKey) !== null && _f !== void 0 ? _f : "").trim();
    const patientId = ((_h = (_g = req.data) === null || _g === void 0 ? void 0 : _g.patientId) !== null && _h !== void 0 ? _h : "").trim() || null;
    const appointmentId = ((_k = (_j = req.data) === null || _j === void 0 ? void 0 : _j.appointmentId) !== null && _k !== void 0 ? _k : "").trim() || null;
    const answers = (_m = (_l = req.data) === null || _l === void 0 ? void 0 : _l.answers) !== null && _m !== void 0 ? _m : null;
    const consentGiven = ((_o = req.data) === null || _o === void 0 ? void 0 : _o.consentGiven) === true;
    const triageStatus = ((_q = (_p = req.data) === null || _p === void 0 ? void 0 : _p.triageStatus) !== null && _q !== void 0 ? _q : null);
    const clinicianSummary = ((_s = (_r = req.data) === null || _r === void 0 ? void 0 : _r.clinicianSummary) !== null && _s !== void 0 ? _s : "").trim() || null;
    if (!clinicId || !packId || !regionKey) {
        throw new https_1.HttpsError("invalid-argument", "clinicId, packId, regionKey are required.");
    }
    if (!answers || typeof answers !== "object" || Array.isArray(answers)) {
        throw new https_1.HttpsError("invalid-argument", "answers (object) is required.");
    }
    if (consentGiven !== true) {
        throw new https_1.HttpsError("failed-precondition", "Consent must be true to submit.");
    }
    const db = admin.firestore();
    const uid = req.auth.uid;
    await (0, authz_1.requireActiveMemberWithPerm)(db, clinicId, uid, "clinical.write");
    const packRef = db.collection("clinics").doc(clinicId).collection("assessmentPacks").doc(packId);
    const packSnap = await packRef.get();
    if (!packSnap.exists)
        throw new https_1.HttpsError("not-found", "assessmentPack not found.");
    const now = admin.firestore.FieldValue.serverTimestamp();
    const ref = db.collection("clinics").doc(clinicId).collection("assessments").doc();
    await ref.set({
        schemaVersion: (0, schemaVersions_1.schemaVersion)("assessment"),
        clinicId,
        packId,
        regionKey,
        patientId,
        appointmentId,
        consentGiven: true,
        triageStatus: triageStatus !== null && triageStatus !== void 0 ? triageStatus : null,
        answers,
        clinicianSummary,
        status: "finalized",
        submittedAt: now,
        finalizedAt: now,
        pdf: {
            status: "queued",
            storagePath: null,
            url: null,
            updatedAt: now,
        },
        createdAt: now,
        updatedAt: now,
        createdByUid: uid,
        updatedByUid: uid,
    });
    await (0, audit_1.writeAuditEvent)(db, clinicId, {
        type: "assessment.submitted",
        actorUid: uid,
        patientId: patientId !== null && patientId !== void 0 ? patientId : undefined,
        metadata: {
            packId,
            regionKey,
            appointmentId,
            assessmentId: ref.id,
            triageStatus,
        },
    });
    return { success: true, assessmentId: ref.id };
}
//# sourceMappingURL=submitAssessment.js.map