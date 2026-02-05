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
exports.createAssessment = createAssessment;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const authz_1 = require("../authz");
const schemaVersions_1 = require("../../schema/schemaVersions");
const audit_1 = require("../audit/audit");
const paths_1 = require("../paths");
async function createAssessment(req) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q;
    if (!req.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const clinicId = ((_b = (_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId) !== null && _b !== void 0 ? _b : "").trim();
    const packId = ((_d = (_c = req.data) === null || _c === void 0 ? void 0 : _c.packId) !== null && _d !== void 0 ? _d : "").trim();
    const region = ((_f = (_e = req.data) === null || _e === void 0 ? void 0 : _e.region) !== null && _f !== void 0 ? _f : "").trim();
    const patientId = ((_h = (_g = req.data) === null || _g === void 0 ? void 0 : _g.patientId) !== null && _h !== void 0 ? _h : "").trim() || null;
    const episodeId = ((_k = (_j = req.data) === null || _j === void 0 ? void 0 : _j.episodeId) !== null && _k !== void 0 ? _k : "").trim() || null;
    const appointmentId = ((_m = (_l = req.data) === null || _l === void 0 ? void 0 : _l.appointmentId) !== null && _m !== void 0 ? _m : "").trim() || null;
    const consentGiven = ((_o = req.data) === null || _o === void 0 ? void 0 : _o.consentGiven) === true;
    const answers = (_q = (_p = req.data) === null || _p === void 0 ? void 0 : _p.answers) !== null && _q !== void 0 ? _q : {};
    if (!clinicId || !packId || !region) {
        throw new https_1.HttpsError("invalid-argument", "clinicId, packId, region required.");
    }
    if (typeof answers !== "object" || answers == null || Array.isArray(answers)) {
        throw new https_1.HttpsError("invalid-argument", "answers must be an object.");
    }
    const db = admin.firestore();
    const uid = req.auth.uid;
    await (0, authz_1.requireActiveMemberWithPerm)(db, clinicId, uid, "clinical.write");
    const packSnap = await (0, paths_1.assessmentPackRef)(db, clinicId, packId).get();
    if (!packSnap.exists)
        throw new https_1.HttpsError("not-found", "Assessment pack not found.");
    const now = admin.firestore.FieldValue.serverTimestamp();
    const id = db.collection("_").doc().id;
    const ref = (0, paths_1.assessmentRef)(db, clinicId, id);
    const doc = {
        schemaVersion: (0, schemaVersions_1.schemaVersion)("assessment"),
        clinicId,
        packId,
        patientId,
        episodeId,
        appointmentId,
        region,
        consentGiven,
        answers,
        triageStatus: null,
        pdf: {
            status: "none",
            storagePath: null,
            url: null,
            updatedAt: now,
        },
        status: "draft",
        createdAt: now,
        updatedAt: now,
        createdByUid: uid,
        updatedByUid: uid,
        submittedAt: null,
        finalizedAt: null,
    };
    await ref.set(doc);
    await (0, audit_1.writeAuditEvent)(db, clinicId, {
        type: "assessment.created",
        actorUid: uid,
        patientId: patientId !== null && patientId !== void 0 ? patientId : undefined,
        episodeId: episodeId !== null && episodeId !== void 0 ? episodeId : undefined,
        metadata: { assessmentId: id, packId, region, appointmentId },
    });
    return { success: true, assessmentId: id };
}
//# sourceMappingURL=createAssessment.js.map